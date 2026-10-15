with transactions as (

    select * from {{ ref('stg_transactions') }}

),

-- Счётчик транзакций по каждой паре мерчант-категория. Нужен, чтобы
-- выбрать основную категорию мерчанта: у 99% она одна, но не у всех.
merchant_category_counts as (

    select
        merchant_name,
        category,
        count(*) as category_transactions
    from transactions
    group by merchant_name, category

),

main_category as (

    select
        merchant_name,
        argMax(category, category_transactions) as main_category
    from merchant_category_counts
    group by merchant_name

),

by_merchant as (

    select
        merchant_name,

        count(*) as transactions_count,
        count(distinct customer_id) as unique_customers,
        count(distinct category) as unique_categories,

        min(transaction_date) as first_transaction_date,
        max(transaction_date) as last_transaction_date,

        sum(amount) as total_amount,
        avg(amount) as avg_amount,
        max(amount) as max_amount,
        median(amount) as median_amount,

        sum(is_fraud) as fraud_count,
        sum(is_fraud) / count(*) * 100 as fraud_rate,
        sumIf(amount, is_fraud = 1) as fraud_amount,

        -- Доля мошеннических сумм в обороте мерчанта: показывает,
        -- сколько денег проходит через фрод, а не только как часто.
        sumIf(amount, is_fraud = 1) / sum(amount) * 100 as fraud_amount_share,

        uniqExactIf(customer_id, is_fraud = 1) as fraud_customers

    from transactions
    group by merchant_name

),

joined as (

    select
        by_merchant.*,
        main_category.main_category
    from by_merchant
    inner join main_category using (merchant_name)

),

scored as (

    select
        *,
        fraud_customers / unique_customers * 100 as fraud_customers_share,
        -- Средний чек мерчанта против среднего по всем мерчантам.
        avg_amount / avg(avg_amount) over () as amount_vs_average_baseline
    from joined

),

flagged as (

    select
        *,
        {#
          Подозрительным мерчант считается, если сработали минимум два
          признака из трёх: доля фрода заметно выше средней по мерчантам,
          высокая доля мошеннических сумм или задранный средний чек.
          Пороги относительные: средняя доля фрода по данным 0.56%,
          у худшего мерчанта 2.7%, поэтому абсолютные значения
          не срабатывали бы никогда.
        #}
        (fraud_rate > 2 * avg(fraud_rate) over ())::UInt8
        + (fraud_amount_share > 2 * avg(fraud_amount_share) over ())::UInt8
        + (amount_vs_average_baseline > 2)::UInt8 as suspicion_score
    from scored

)

select
    merchant_name,
    main_category,
    transactions_count,
    unique_customers,
    unique_categories,
    first_transaction_date,
    last_transaction_date,
    total_amount,
    avg_amount,
    median_amount,
    max_amount,
    amount_vs_average_baseline,
    fraud_count,
    fraud_rate,
    fraud_amount,
    fraud_amount_share,
    fraud_customers,
    fraud_customers_share,
    suspicion_score,
    suspicion_score >= 2 as is_suspicious
from flagged
