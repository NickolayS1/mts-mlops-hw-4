-- База-источник для dbt-проекта.
CREATE DATABASE IF NOT EXISTS transactions_db;

-- Слой raw: сюда Materialized View складывает данные из топика.
CREATE TABLE IF NOT EXISTS transactions_db.transactions
(
    transaction_time DateTime,
    merch            String,
    cat_id           String,
    -- Decimal, а не Float64: 9754.72 в double это 9754.7199999999993,
    -- и перевод в Decimal усекает его до 9754.71.
    amount           Decimal(9, 2),
    name_1           String,
    name_2           String,
    gender           String,
    street           String,
    one_city         String,
    us_state         String,
    post_code        String,
    lat              Float64,
    lon              Float64,
    population_city  Int64,
    jobs             String,
    merchant_lat     Float64,
    merchant_lon     Float64,
    -- Признак фрода, ради которого делается дз.
    target           UInt8
)
ENGINE = MergeTree()
ORDER BY tuple();

-- Консьюмер топика: на диске данных нет, движок держит пачку в памяти.
-- Настройки Kafka заданы только здесь, MV их не наследует.
CREATE TABLE IF NOT EXISTS transactions_db.transactions_queue
(
    -- Типы как в JSON; приведение делает MV.
    transaction_time String,
    merch            String,
    cat_id           String,
    -- JSONEachRow читает число из текста, поэтому в Decimal оно попадает
    -- точным и через double не проходит.
    amount           Decimal(9, 2),
    name_1           String,
    name_2           String,
    gender           String,
    street           String,
    one_city         String,
    us_state         String,
    post_code        String,
    lat              Float64,
    lon              Float64,
    population_city  Int64,
    jobs             String,
    merchant_lat     Float64,
    merchant_lon     Float64,
    target           UInt8
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:29092',
    kafka_topic_list = 'transactions',
    kafka_group_name = 'clickhouse_transactions',
    kafka_num_consumers = 3,
    kafka_format = 'JSONEachRow',
    kafka_max_block_size = 65536;

-- Накопилась пачка — MV прогоняет её через SELECT и вставляет результат
-- в целевую таблицу. Без TO данные остались бы у MV.
CREATE MATERIALIZED VIEW IF NOT EXISTS transactions_db.mv_transactions_to_raw
TO transactions_db.transactions
AS SELECT
    parseDateTimeBestEffort(transaction_time) AS transaction_time,
    merch,
    cat_id,
    amount,
    name_1,
    name_2,
    gender,
    street,
    one_city,
    us_state,
    post_code,
    lat,
    lon,
    population_city,
    jobs,
    merchant_lat,
    merchant_lon,
    target
FROM transactions_db.transactions_queue;
