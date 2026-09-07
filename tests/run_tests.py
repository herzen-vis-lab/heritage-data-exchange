#!/usr/bin/env python3
"""Heritage Data Exchange — проверяемый набор правил (v0.1.0).

Запуск:  python3 tests/run_tests.py   (требует: pip install jsonschema)

Что проверяется:
1. Мета-валидация обеих JSON Schema (draft 2020-12).
2. Позитивные фикстуры: примеры обмена (examples/*.json) валидны против
   exchange-envelope.schema.json со строгой проверкой форматов (FormatChecker:
   RFC 3339, URI, и т.д.) и разрешением кросс-ссылок между схемами.
3. Негативные фикстуры (tests/negative/*.json): каждая ДОЛЖНА быть отвергнута
   целевой подсхемой модели данных (правила, выраженные в JSON Schema):
   - Manifestation без work_guid, Item без manifestation_guid/owner_node_guid
     (условные требования entity_type);
   - UUID не v4/верхний регистр;
   - метка времени с произвольным offset (не UTC-Z);
   - status атрибута без claims;
   - relation_type вне базового словаря.
"""
import json
import pathlib
import sys

from jsonschema import Draft202012Validator, FormatChecker, RefResolver
from jsonschema.validators import validate

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMA_DIR = ROOT / "schema"
EXAMPLES_DIR = ROOT / "examples"
NEGATIVE_DIR = pathlib.Path(__file__).resolve().parent / "negative"

DOC_SCHEMA_FILE = SCHEMA_DIR / "federated-exchange-document.schema.json"
ENV_SCHEMA_FILE = SCHEMA_DIR / "exchange-envelope.schema.json"

# Негативные фикстуры и целевая подсхема модели данных, против которой
# фикстура обязана быть отвергнута.
NEGATIVE_TARGETS = {
    "digital-object-manifestation-without-work-guid.json": "DigitalObject",
    "digital-object-item-without-owner-and-manifestation.json": "DigitalObject",
    "digital-object-uuid-uppercase.json": "DigitalObject",
    "digital-object-timestamp-with-offset.json": "DigitalObject",
    "metadata-status-without-claims.json": "Metadata",
    "relation-unknown-type.json": "Relation",
}


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def main():
    failures = []
    doc = load(DOC_SCHEMA_FILE)
    env = load(ENV_SCHEMA_FILE)
    store = {doc["$id"]: doc, env["$id"]: env}
    fc = FormatChecker()

    # 1. Мета-валидация схем
    for label, schema in (("federated-exchange-document", doc), ("exchange-envelope", env)):
        try:
            Draft202012Validator.check_schema(schema)
            print(f"ok    meta: {label}")
        except Exception as exc:  # noqa: BLE001
            failures.append(f"meta {label}: {exc}")
            print(f"FAIL  meta: {label}: {exc}")

    res_doc = RefResolver.from_schema(doc, store=store)
    res_env = RefResolver.from_schema(env, store=store)

    # 2. Позитивные фикстуры — примеры обмена
    for example in sorted(EXAMPLES_DIR.glob("exchange-envelope.*.json")):
        data = load(example)
        try:
            validate(data, env, resolver=res_env, format_checker=fc)
            print(f"ok    positive: {example.name}")
        except Exception as exc:  # noqa: BLE001
            failures.append(f"positive {example.name}: {exc}")
            print(f"FAIL  positive: {example.name}: {exc}")

    # 3. Негативные фикстуры
    for filename, defname in sorted(NEGATIVE_TARGETS.items()):
        fixture = load(NEGATIVE_DIR / filename)
        target = {"$ref": f"{doc['$id']}#/$defs/{defname}"}
        try:
            validate(fixture, target, resolver=res_doc, format_checker=fc)
            failures.append(f"negative {filename}: unexpectedly valid")
            print(f"FAIL  negative: {filename}: фикстура НЕ отвергнута")
        except Exception:  # noqa: BLE001 — ожидаемая ошибка валидации
            print(f"ok    negative: {filename}")

    # Запрещённые лишние файлы в каталоге фикстур (опечатки имён не остаются незамеченными)
    unknown = sorted(set(p.name for p in NEGATIVE_DIR.glob("*.json")) - set(NEGATIVE_TARGETS))
    for name in unknown:
        failures.append(f"negative {name}: файл не описан в NEGATIVE_TARGETS")
        print(f"FAIL  negative: {name}: файл не описан в NEGATIVE_TARGETS")

    if failures:
        print(f"\n{len(failures)} failure(s)")
        return 1
    print("\nAll checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
