# Скриншоты прогона

Сняты на полной загрузке датасета — 786 431 строка.

| Файл | Что видно |
|---|---|
| `dbt_test_versions.png` | начало `dbt test`: версии `dbt-core 1.9.10` и `dbt-clickhouse 1.9.5`, состав проекта (7 моделей, 113 data tests, 1 unit test) |
| `dbt_test_result.png` | конец `dbt test`: `PASS=114 WARN=0 ERROR=0 SKIP=0 TOTAL=114`, `Completed successfully` |
| `dbt_docs_dag.png` | граф моделей из dbt Docs: `raw.transactions` → `stg_transactions` → 6 витрин, отдельно seed `states` и тесты |
| `dbt_docs_model.png` | страница витрины `mart_fraud_by_category`: описания и типы колонок, отметки о тестах |
| `dbt_docs_macro.png` | страница макроса `amount_bucket`: описание, аргументы, кто использует |

Как воспроизвести:

```bash
cd dbt
dbt test
dbt docs serve        # http://localhost:8080, иконка графа справа внизу
```
