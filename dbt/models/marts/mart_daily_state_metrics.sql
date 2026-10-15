with transactions as (

    select * from {{ ref('stg_transactions') }}

),

daily as (

    select
        transaction_date,
        state,

        count(*) as transactions_count,
        count(distinct customer_id) as unique_customers,
        count(distinct merchant_name) as unique_merchants,

        sum(amount) as total_amount,
        avg(amount) as avg_amount,
        median(amount) as median_amount,

        -- 95-й процентиль: граница, выше которой лежат самые крупные
        -- чеки дня. sqlfluff не разбирает агрегат с параметром.
        quantile(0.95)(amount) as p95_amount,  -- noqa: PRS,AL03

        sum(is_fraud) as fraud_count,
        sum(is_fraud) / count(*) * 100 as fraud_rate,

        -- Крупной считаем транзакцию дороже 500 долларов: это заметно
        -- выше среднего чека по данным (около 70).
        countIf(amount > 500) as large_transactions_count,
        countIf(amount > 500) / count(*) * 100 as large_transactions_rate,

        -- Разброс сумм внутри дня: средний чек сам по себе не показывает,
        -- насколько он устойчив.
        stddevPop(amount) as amount_stddev

    from transactions
    group by transaction_date, state

),

final as (

    select
        -- Ключ витрины: одна строка на сочетание даты и штата.
        {{ dbt_utils.generate_surrogate_key(['transaction_date', 'state']) }} as daily_state_key,
        *,
        -- Понедельник = 1, воскресенье = 7.
        toDayOfWeek(transaction_date) as weekday_number
    from daily

)

select
    daily_state_key,
    transaction_date,
    weekday_number,
    state,
    transactions_count,
    unique_customers,
    unique_merchants,
    total_amount,
    avg_amount,
    median_amount,
    p95_amount,
    amount_stddev,
    large_transactions_count,
    large_transactions_rate,
    fraud_count,
    fraud_rate
from final
