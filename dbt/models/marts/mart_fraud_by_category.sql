with transactions as (

    select * from {{ ref('stg_transactions') }}

),

by_category as (

    select
        category,

        count(*) as transactions_count,
        count(distinct customer_id) as unique_customers,
        count(distinct merchant_name) as unique_merchants,

        sum(is_fraud) as fraud_count,
        sum(is_fraud) / count(*) * 100 as fraud_rate,

        sum(amount) as total_amount,
        sumIf(amount, is_fraud = 1) as fraud_amount,
        avg(amount) as avg_amount,
        avgIf(amount, is_fraud = 1) as avg_fraud_amount,

        -- Доля категории в общем обороте: показывает, где сосредоточены
        -- деньги, а не только где много транзакций.
        sum(amount) / sum(sum(amount)) over () * 100 as amount_share

    from transactions
    group by category

),

final as (

    select
        *,
        -- Средняя доля фрода по всем категориям — база для сравнения.
        avg(fraud_rate) over () as overall_fraud_rate,
        -- 1.0 — категория ровно на среднем уровне.
        fraud_rate / avg(fraud_rate) over () as fraud_rate_index,
        -- Порог вдвое выше среднего по категориям (0.56%). Абсолютный
        -- порог тут не работает: даже худшая категория не дотягивает
        -- до 2%, поэтому фиксированное значение не срабатывало бы.
        fraud_rate > 2 * avg(fraud_rate) over () as is_high_risk_category
    from by_category

)

select
    category,
    transactions_count,
    unique_customers,
    unique_merchants,
    fraud_count,
    fraud_rate,
    fraud_rate_index,
    is_high_risk_category,
    total_amount,
    fraud_amount,
    avg_amount,
    avg_fraud_amount,
    amount_share
from final
