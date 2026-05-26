import json
import requests

BASE_URL = "https://raw.githubusercontent.com/herzen-vis-lab/heritage-data-exchange/main/schema/"

FILES = [
    "exchange-envelope.schema.json",
    "multilingual-string.schema.json",
    "object-card.schema.json",
    "organization.schema.json",
    "relation.schema.json"
]

schemas = {}

# 1. скачиваем все схемы
for file in FILES:
    url = BASE_URL + file
    print(f"Downloading {url}")
    
    r = requests.get(url)
    r.raise_for_status()
    
    name = file.replace(".schema.json", "")
    schemas[name] = r.json()

# 2. переписываем внутренние $ref под OpenAPI формат
def fix_refs(obj):
    if isinstance(obj, dict):
        new_obj = {}
        for k, v in obj.items():
            if k == "$ref" and isinstance(v, str):
                # превращаем локальные ссылки в OpenAPI-style
                if v.startswith("#"):
                    new_obj[k] = v
                else:
                    ref_name = v.split("/")[-1].replace(".schema.json", "")
                    new_obj[k] = f"#/components/schemas/{ref_name}"
            else:
                new_obj[k] = fix_refs(v)
        return new_obj
    
    if isinstance(obj, list):
        return [fix_refs(i) for i in obj]
    
    return obj

schemas_fixed = {k: fix_refs(v) for k, v in schemas.items()}

# 3. OpenAPI wrapper
openapi = {
    "openapi": "3.0.3",
    "info": {
        "title": "Heritage Data Exchange",
        "version": "1.0.0"
    },
    "paths": {},
    "components": {
        "schemas": schemas_fixed
    }
}

# 4. save
with open("openapi.json", "w", encoding="utf-8") as f:
    json.dump(openapi, f, indent=2, ensure_ascii=False)

print("Done → openapi.json")
