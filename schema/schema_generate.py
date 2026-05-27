import re
import json
import sys
import requests
from pathlib import Path

PROTOCOL_NAME = "federated-exchange-document"
PROTOCOL_BASE_URL = "https://raw.githubusercontent.com/herzen-vis-lab/heritage-data-exchange/refs/heads/main/"
PROTOCOL_DOCS_DIR = "docs/"
PROTOCOL_SCHEMA_DIR = "schema/"
PROTOCOL_MERMAID_URI = PROTOCOL_BASE_URL + PROTOCOL_DOCS_DIR + PROTOCOL_NAME + ".md"
PROTOCOL_FILE_NAME = PROTOCOL_NAME + ".schema.json"
PROTOCOL_URI = PROTOCOL_BASE_URL + PROTOCOL_SCHEMA_DIR + PROTOCOL_FILE_NAME

# ---------------------------------------------------------------------------
# Type mapping
# ---------------------------------------------------------------------------
 
TYPE_MAP = {
    "string":   {"type": "string"},
    "uri":      {"type": "string", "format": "uri"},
    "uuid":     {"type": "string", "format": "uuid",
                 "description": "Globally unique (UUID v4), immutable, lowercase"},
    "datetime": {"type": "string", "format": "date-time",
                 "description": "ISO 8601 UTC timestamp"},
    "semver":   {"type": "string", "pattern": r"^\d+\.\d+\.\d+$",
                 "description": "Semantic version (MAJOR.MINOR.PATCH)"},
    "scalar":   {"oneOf": [{"type": "string"}, {"type": "number"}, {"type": "boolean"}],
                 "description": "JSON scalar: string, number, or boolean"},
    "boolean":  {"type": "boolean"},
    "number":   {"type": "number"},
    "integer":  {"type": "integer"},
}
 
 
def field_type(mermaid_type: str) -> dict:
    return TYPE_MAP.get(mermaid_type.strip().lower(),
                        {"type": "string", "description": f"type: {mermaid_type}"})
 
 
# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------
 
def parse_mermaid(text: str) -> dict:
    """Parse Mermaid classDiagram into classes and relations."""
    classes = {}
    relations = []
 
    # Extract lines inside ```mermaid ... ``` block, skip %% comments
    in_block = False
    lines = []
    for raw in text.splitlines():
        stripped = raw.strip()
        if stripped.startswith("```mermaid"):
            in_block = True
            continue
        if stripped.startswith("```") and in_block:
            in_block = False
            continue
        if stripped.startswith("%%") or not stripped:
            continue
        if in_block:
            lines.append(stripped)
 
    # Fallback: no fenced block — use all non-comment lines
    if not lines:
        lines = [l.strip() for l in text.splitlines()
                 if l.strip() and not l.strip().startswith("%%")]
 
    current_class = None
    brace_depth = 0
 
    for line in lines:
        if line.lower() == "classdiagram":
            continue
 
        # ── Class declaration ──────────────────────────────────────────────
        m = re.match(r'^class\s+(\w+)\s*(\{)?', line)
        if m:
            current_class = m.group(1)
            classes.setdefault(current_class,
                               {"fields": [], "stereotype": None, "values": []})
            if m.group(2):
                brace_depth += 1
            continue
 
        if line == "{":
            brace_depth += 1
            continue
 
        if line == "}":
            brace_depth -= 1
            if brace_depth <= 0:
                current_class = None
                brace_depth = 0
            continue
 
        # ── Inside class body ──────────────────────────────────────────────
        if current_class:
            # Stereotype  <<enumeration>>
            m = re.match(r'^<<(.+)>>$', line)
            if m:
                classes[current_class]["stereotype"] = m.group(1).strip()
                continue
 
            # Field:  +Type name
            m = re.match(r'^[+\-#~]?(\S+)\s+(\S+)$', line)
            if m:
                ftype, fname = m.group(1), m.group(2)
                if classes[current_class]["stereotype"] == "enumeration":
                    classes[current_class]["values"].append(ftype)
                else:
                    classes[current_class]["fields"].append(
                        {"name": fname, "type": ftype})
                continue
 
            # Bare enum value (single token)
            m = re.match(r'^[+\-#~]?(\w+)$', line)
            if m and classes[current_class]["stereotype"] == "enumeration":
                classes[current_class]["values"].append(m.group(1))
                continue
 
        # ── Relationship ───────────────────────────────────────────────────
        # "From" "card" --> "card" To : label
        m = re.match(
            r'^(\w+)\s+"([^"]+)"\s+--[>|*o]+\s+"([^"]+)"\s+(\w+)(?:\s*:\s*(.+))?$',
            line)
        if m:
            relations.append({
                "from": m.group(1), "to": m.group(4),
                "to_card": m.group(3),
                "label": m.group(5).strip() if m.group(5) else None,
            })
            continue
 
        # From --> To : label  (no cardinality)
        m = re.match(r'^(\w+)\s+--[>|*o]+\s+(\w+)(?:\s*:\s*(.+))?$', line)
        if m:
            relations.append({
                "from": m.group(1), "to": m.group(2),
                "to_card": "*",
                "label": m.group(3).strip() if m.group(3) else None,
            })
 
    return {"classes": classes, "relations": relations}
 
 
# ---------------------------------------------------------------------------
# Schema builder
# ---------------------------------------------------------------------------
 
def build_schema(parsed: dict, protocol_uri: str) -> dict:
    """Build a single JSON Schema with $defs for all classes."""
    classes   = parsed["classes"]
    relations = parsed["relations"]
    defs      = {}
 
    # 1. Build $defs for every class
    for name, data in classes.items():
        if data["stereotype"] == "enumeration":
            defs[name] = {"title": name, "enum": data["values"]}
        else:
            props    = {}
            required = []
            for f in data["fields"]:
                props[f["name"]] = field_type(f["type"])
                required.append(f["name"])
            defs[name] = {
                "title": name,
                "type": "object",
                "properties": props,
                "required": required,
                "additionalProperties": False,
            }
 
    # 2. Add relationship properties to parent classes
    for rel in relations:
        src, tgt = rel["from"], rel["to"]
        if src not in defs or tgt not in defs:
            continue
        if "enum" in defs[src]:          # skip enumerations
            continue
 
        label    = (rel["label"] or tgt[0].lower() + tgt[1:]).replace(" ", "_").lower()
        to_card  = rel.get("to_card", "*")
        is_array = "*" in to_card or "+" in to_card
 
        ref  = {"$ref": f"#/$defs/{tgt}"}
        prop = {"type": "array", "items": ref} if is_array else ref
 
        defs[src].setdefault("properties", {})[label] = prop
 
    # 3. Assemble root schema
    return {
        "$schema":     "https://json-schema.org/draft/2020-12/schema",
        "$id":         protocol_uri,
        "title":       "FederatedExchangeDocument",
        "description": (
            "Federated exchange of digital cultural heritage objects "
            "in a loosely coupled network."
        ),
        "$ref":  "#/$defs/FederatedExchangeDocument",
        "$defs": defs,
    }
 
 
# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
 
r = requests.get(PROTOCOL_MERMAID_URI)
r.raise_for_status()
mermaid_text = r.content.decode('utf-8')
parsed = parse_mermaid(mermaid_text)
schema = build_schema(parsed, PROTOCOL_URI)
print(schema)
 
with open(PROTOCOL_FILE_NAME, "w", encoding="utf-8") as f:
  json.dump(schema, f, indent=2, ensure_ascii=False)
