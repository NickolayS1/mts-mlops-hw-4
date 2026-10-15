with transactions as (

    select * from {{ ref('stg_transactions') }}

),

by_customer as (

    select
        customer_id,
        -- Клиент опознаётся по имени и городу, они же идут в профиль.
        any(customer_name) as customer_name,
        any(city) as city,
        any(state) as state,
        any(gender) as gender,
        any(jobs) as jobs,

        count(*) as transactions_count,
        count(distinct merchant_name) as unique_merchants,
        count(distinct category) as unique_categories,

        min(transaction_date) as first_transaction_date,
        max(transaction_date) as last_transaction_date,
        -- Сколько дней клиент активен: считаем по календарю, а не по
        -- числу транзакций, иначе активный клиент и клиент с одной
        -- покупкой в день выглядят одинаково.
        dateDiff('day', min(transaction_date), max(transaction_date)) + 1 as active_days,

        sum(amount) as total_amount,
        avg(amount) as avg_amount,
        max(amount) as max_amount,
        median(amount) as median_amount,

        sum(is_fraud) as fraud_count,
        sum(is_fraud) / count(*) * 100 as fraud_rate,
        sumIf(amount, is_fraud = 1) as fraud_amount,

        -- Ночные транзакции: с 0 до 5 часов.
        countIf(transaction_hour between 0 and 5) as night_transactions_count,
        avg(distance_km) as avg_distance_km

    from transactions
    group by customer_id

),

scored as (

    select
        *,
        night_transactions_count / transactions_count * 100 as night_transactions_share,
        -- Средний чек клиента относительно среднего по всем клиентам.
        -- 1.0 — клиент ровно на среднем уровне.
        avg_amount / avg(avg_amount) over () as amount_vs_average
    from by_customer

),

profiled as (

    select
        *,
        {#
          Риск собирается из четырёх признаков. Каждый добавляет балл:
          сам факт фрода, высокая частота, ночная активность и
          крупный средний чек. Порог 3 из 4 отделяет явные случаи,
          1-2 балла — серая зона.
        #}
        (fraud_count > 0)::UInt8
        + (fraud_rate > 50)::UInt8
        + (night_transactions_share > 20)::UInt8
        + (amount_vs_average > 2)::UInt8 as risk_score
    from scored

)

select
    customer_id,
    customer_name,
    city,
    state,
    gender,
    jobs,
    transactions_count,
    unique_merchants,
    unique_categories,
    first_transaction_date,
    last_transaction_date,
    active_days,
    total_amount,
    avg_amount,
    median_amount,
    max_amount,
    amount_vs_average,
    fraud_count,
    fraud_rate,
    fraud_amount,
    night_transactions_count,
    night_transactions_share,
    avg_distance_km,
    risk_score,
    multiIf(
        risk_score >= 3, 'HIGH',
        risk_score = 2, 'MEDIUM',
        'LOW'
    ) as risk_level
from profiled
