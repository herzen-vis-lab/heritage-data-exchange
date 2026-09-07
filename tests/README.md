# Тесты протокола Heritage Data Exchange (v0.1.0)

Проверяемый набор правил: часть правил `docs/federated-exchange-document.rules.dsl`
выражена непосредственно в JSON Schema и/или закреплена фикстурами.

## Запуск

```bash
pip install jsonschema
python3 tests/run_tests.py
```

## Структура

- `run_tests.py` — раннер: мета-валидация схем, позитивные примеры обмена,
  негативные фикстуры.
- `negative/` — фикстуры, которые обязаны быть **отвергнуты** схемой
  (нарушения, закодированные в JSON Schema v0.1.0):

| Фикстура | Нарушенное правило |
|---|---|
| `digital-object-manifestation-without-work-guid.json` | `work.manifestation_item` — Manifestation без `work_guid` |
| `digital-object-item-without-owner-and-manifestation.json` | `work.manifestation_item` — Item без `manifestation_guid`/`owner_node_guid` |
| `digital-object-uuid-uppercase.json` | `document.uuid_format` — UUID не lowercase v4 |
| `digital-object-timestamp-with-offset.json` | `document.timestamp` — метка не UTC (offset вместо Z) |
| `metadata-status-without-claims.json` | `metadata.claims_status` — `status` без `claims` |
| `relation-unknown-type.json` | `relation.types` — `relation_type` вне базового словаря |

Позитивные фикстуры — `examples/exchange-envelope.publish-*.json`
(валидация конвертов целиком, со строгой проверкой форматов).

## CI

`.github/workflows/ci.yml` запускает раннер на каждый push и pull request.
