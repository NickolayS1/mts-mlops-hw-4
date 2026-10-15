with transactions as (

    select * from {{ ref('stg_transactions') }}

),

by_hour as (

    select
        day_of_week,
        day_name,
        transaction_hour,

        count(*) as transactions_count,
        count(distinct customer_id) as unique_customers,

        sum(is_fraud) as fraud_count,
        sum(is_fraud) / count(*) * 100 as fraud_rate,

        sum(amount) as total_amount,
        avg(amount) as avg_amount,
        sumIf(amount, is_fraud = 1) as fraud_amount

    from transactions
    group by day_of_week, day_name, transaction_hour

),

enriched as (

    select
        *,
        -- Ключ витрины: одна строка на день недели и час.
        {{ dbt_utils.generate_surrogate_key(['day_of_week', 'transaction_hour']) }} as hour_slot_key,
        -- Общая средняя частота фрода — база для сравнения окон.
        avg(fraud_rate) over () as overall_fraud_rate,
        avg(transactions_count) over () as avg_transactions_per_slot
    from by_hour

),

final as (

    select
        hour_slot_key,
        day_of_week,
        day_name,
        transaction_hour,
        transactions_count,
        unique_customers,
        fraud_count,
        fraud_rate,
        overall_fraud_rate,
        total_amount,
        fraud_amount,
        avg_amount,
        avg_transactions_per_slot,

        -- Выходные: суббота и воскресенье.
        day_of_week in (6, 7) as is_weekend,
        -- Во сколько раз окно рискованнее среднего по всем окнам.
        fraud_rate / overall_fraud_rate as fraud_rate_index,
        -- Порог втрое выше среднего. Абсолютный порог не подходит:
        -- средняя доля фрода по окнам 0.59%, максимум 3.3%.
        fraud_rate > 3 * overall_fraud_rate as is_high_risk_window
    from enriched

)

select * from final
