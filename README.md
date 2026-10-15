# dbt-проект: транзакции и фрод

Домашнее задание №4. Датасет из домашки по ClickHouse (`train.csv`
соревнования `teta-ml-1-2025`, 786 431 строка) описан слоистой
dbt-моделью: сырые данные → staging → 6 аналитических витрин.

Источник — таблица `transactions_db.transactions` в ClickHouse, куда
данные попадают из топика Kafka. Подъём источника описан ниже,
сам dbt-проект лежит в каталоге `dbt/`.

## Версии

| Компонент | Версия |
|---|---|
| `dbt-core` | 1.9.10 |
| `dbt-clickhouse` | 1.9.5 |
| `dbt_utils` | 1.4.1 |
| `dbt_date` | 0.10.1 |
| `dbt_expectations` | 0.10.4 |
| `sqlfluff` | 3.2.5 |
| ClickHouse | 24.8 |

## Что нужно

- Docker 20.10+ с плагином Compose
- Python 3.10+
- Свободные порты 9092 (Kafka), 8123 и 9000 (ClickHouse)
- `train.csv` из соревнования `teta-ml-1-2025` в каталоге `teta-ml-1-2025/`
  (в репозиторий не входит, датасет скачивается с Kaggle)

## Запуск

### 1. Поднять источник

```bash
docker compose up -d --build
docker compose run --rm producer
```

Загрузка занимает около двух с половиной минут. Проверить, что данные доехали:

```bash
docker compose exec clickhouse clickhouse-client \
  --query "SELECT count(), sum(target) FROM transactions_db.transactions"
```

Ожидаемый ответ — `786431` и `4504`. Число растёт ещё несколько секунд
после завершения producer'а: Materialized View забирает пачки по мере накопления.

Entrypoint образа ClickHouse при первом старте создаёт файл
`users.d/default-user.xml`, который пускает пользователя `default`
только с `127.0.0.1` внутри контейнера. Через проброшенный порт запрос
приходит с адреса docker-сети, и сервер отвечает ошибкой аутентификации,
хотя пароль пустой — проверка сети маскируется под проверку пароля.
dbt ходит в базу по сети, поэтому в `clickhouse/config/users.d/`
лежит свой файл по тому же пути, он перекрывает созданный entrypoint'ом
и открывает доступ с хоста. Файл смонтирован в контейнер.

### 2. Поставить dbt

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt      # Linux и macOS
.venv\Scripts\pip install -r requirements.txt  # Windows
```

### 3. Прогнать проект

```bash
cd dbt
dbt deps
dbt seed
dbt run
dbt test
```

Полный цикл одной командой:

```bash
make full
```

`make` есть в Linux и macOS. В Windows команды из `dbt/` выполняются
напрямую, как показано выше, либо через `make` из WSL или Git Bash.

### 4. Документация

```bash
cd dbt
dbt docs generate
dbt docs serve
```

Открывается на `http://localhost:8080`. Описания моделей и колонок берутся
из `schema.yml`-файлов, граф зависимостей строится по `ref()`.

## Результаты прогона

Все скриншоты лежат в `docs/screenshots/`.

| Файл | Что на нём |
|---|---|
| `dbt_test_versions.png` | начало `dbt test`: версии `dbt-core 1.9.10` и `dbt-clickhouse 1.9.5`, состав проекта |
| `dbt_test_result.png` | итог `dbt test`: `PASS=114 WARN=0 ERROR=0 SKIP=0 TOTAL=114`, `Completed successfully` |
| `dbt_docs_dag.png` | граф моделей из dbt Docs |
| `dbt_docs_model.png` | страница витрины `mart_fraud_by_category`: описания и типы колонок, тесты |
| `dbt_docs_macro.png` | страница макроса `amount_bucket` |

Содержимое витрин после прогона:

| Витрина | Строк |
|---|---|
| `mart_daily_state_metrics` | 21 386 |
| `mart_customer_risk_profile` | 965 |
| `mart_merchant_analytics` | 693 |
| `mart_hourly_fraud_pattern` | 168 |
| `mart_fraud_by_state` | 51 |
| `mart_fraud_by_category` | 14 |

## Модели

```
raw (transactions_db.transactions)
  │
  ▼
stg_transactions          очистка, типы, вычисляемые поля
  │
  ├── mart_daily_state_metrics     дневные метрики по штатам
  ├── mart_fraud_by_category       фрод по категориям
  ├── mart_fraud_by_state          фрод по штатам
  ├── mart_customer_risk_profile   профиль риска клиентов
  ├── mart_hourly_fraud_pattern    фрод по дням недели и часам
  └── mart_merchant_analytics      аналитика по мерчантам
```

### stg_transactions

Приводит типы, раскладывает время на дату, час и день недели, собирает
ключи клиента и транзакции, считает расстояние между клиентом и мерчантом
по формуле гаверсинуса. Сумма проходит через макрос `amount_bucket`
и получает сегмент: `micro`, `small`, `medium`, `large`, `extra_large`.

### Поддержка ClickHouse в dbt_date

Пакет `dbt_date` не знает про ClickHouse и для неизвестного адаптера
берёт реализацию по умолчанию, а она печатает `to_char` и `date_part`,
которых в ClickHouse нет. В `macros/dbt_date_clickhouse.sql` эти два
макроса переопределены через `adapter.dispatch` — dbt сам выбирает
clickhouse-версию. Дополнительно учтено, что коды формата в ClickHouse
как в MySQL: полное имя дня недели даёт `%W`, а не `%A`.

### Ключи и сегментация

`customer_id` собирается из имени, фамилии и города. Без города несколько
тысяч строк склеиваются в одного клиента: полных тёзок по стране много,
а в пределах одного города совпадений нет.

`mart_hourly_fraud_pattern`, `mart_fraud_by_category` и
`mart_merchant_analytics` помечают риск относительным порогом — вдвое
или втрое выше среднего по своей размерности. Абсолютные пороги
не работают: средняя доля фрода в данных 0.57%, и даже худшая категория
не дотягивает до 2%.

### Витрины

| Модель | Зерно | Что показывает |
|---|---|---|
| `mart_daily_state_metrics` | дата + штат | количество транзакций, суммы, средний чек, P95, доля крупных |
| `mart_fraud_by_category` | категория | доля фрода и суммы по 14 категориям, индекс риска |
| `mart_fraud_by_state` | штат | доля фрода, клиенты, мерчанты, суммы, сравнение со средним по стране |
| `mart_customer_risk_profile` | клиент | риск `HIGH`/`MEDIUM`/`LOW`, история транзакций, доля фрода |
| `mart_hourly_fraud_pattern` | день недели + час | 168 временных окон, индекс риска, окна с повышенным фродом |
| `mart_merchant_analytics` | мерчант | оборот, доля фрода, флаг подозрительности |

`mart_daily_state_metrics` и `mart_hourly_fraud_pattern` дополнительно
несут признаки фрода, чтобы витрины были самодостаточны.

## Тесты

Базовые тесты (`not_null`, `unique`, `accepted_values`, `relationships`)
описаны в `models/sources/sources.yml`, `models/staging/stg_transactions.yml`
и `models/marts/_marts.yml`. Отдельно проверяются:

- уникальность ключей витрин через `dbt_utils.unique_combination_of_columns`:
  дата + штат, день недели + час, имя клиента + город;
- границы процентов через `dbt_expectations.expect_column_values_to_be_between`:
  `fraud_rate`, `large_transactions_rate`, `fraud_amount_share` лежат в 0..100;
- ссылочная целостность: `stg_transactions.state` и `mart_fraud_by_state.state`
  ссылаются на seed `states`.

Singular tests в `tests/`:

| Файл | Что проверяет |
|---|---|
| `assert_no_negative_amounts.sql` | нет транзакций с отрицательной суммой |
| `assert_fraud_rate_bounds.sql` | доля фрода в витринах лежит в 0..100 |
| `assert_transaction_date_not_in_future.sql` | дата транзакции не в будущем |

Unit tests в `models/staging/stg_transactions_unit_tests.yml` проверяют
макрос `amount_bucket` на границах сегментов и разбор признака фрода:

```bash
dbt test --select "test_type:unit"
```

## Seed

`seeds/states.csv` — справочник 51 штата с регионом и часовым поясом.
Используется тестами `relationships` для проверки кодов штатов.

## Линтинг

```bash
cd dbt
sqlfluff lint models macros tests seeds   # проверка
sqlfluff fix models tests seeds          # автоисправление
```

Или из корня репозитория: `make lint` и `make fix`.

Настройки в `dbt/.sqlfluff`: диалект `clickhouse`, длина строки 120,
шаблонизатор `dbt`. Часть правил отключена осознанно:

- `CP03`, `CP05` — регистр имён. ClickHouse различает регистр в именах
  функций (`sumIf` работает, `sumif` нет), а sqlfluff требует нижний
  регистр и своим `fix` ломает рабочий SQL;
- `RF04` — колонки `state` и `gender` пришли из источника;
- `LT05` — длинные строки в шаблонах dbt;
- `AL03` — диалект не разбирает агрегат с параметром
  `quantile(0.95)(amount)`, в этой строке стоит точечный `noqa`.

Pre-commit проверяет файлы: пробелы в конце строк, перевод строки
в конце файла, синтаксис YAML, маркеры конфликтов, размер файлов.
`TASK.md` и `AGENTS.md` исключены, чтобы hooks не переписывали
исходный текст задания.

```bash
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

SQL линтер в pre-commit не включён: ему нужен собранный dbt-проект,
а не изолированное окружение hook'а. Запускать через `make lint`.

## Структура

```
docker-compose.yml               zookeeper, kafka, clickhouse, producer
producer/producer.py             выгрузка train.csv в топик Kafka
clickhouse/init/01_ddl.sql       DDL: MergeTree + Kafka engine + MV
clickhouse/config/users.d/       доступ пользователя default с хоста
docs/screenshots/                скриншоты прогона для сдачи
dbt/
├── dbt_project.yml
├── packages.yml                 dbt_utils, dbt_date, dbt_expectations
├── profiles.yml                 подключение к ClickHouse
├── .sqlfluff                    настройки линтера
├── models/
│   ├── docs.md                  doc-блоки для описаний макросов
│   ├── sources/sources.yml
│   ├── staging/                 stg_transactions + описания + unit tests
│   └── marts/                   6 витрин + описания и тесты
├── macros/amount_bucket.sql     сегментация сумм
├── macros/dbt_date_clickhouse.sql  поддержка ClickHouse для dbt_date
├── tests/                       singular tests
└── seeds/states.csv             справочник штатов
Makefile                         команды проекта
.pre-commit-config.yaml          проверки файлов
requirements.txt                 зависимости Python
```
