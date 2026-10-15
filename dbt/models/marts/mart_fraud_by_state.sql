with transactions as (

    select * from {{ ref('stg_transactions') }}

),

by_state as (

    select
        state,

        count(*) as transactions_count,
        count(distinct customer_id) as unique_customers,
        count(distinct merchant_name) as unique_merchants,
        count(distinct city) as unique_cities,

        sum(is_fraud) as fraud_count,
        sum(is_fraud) / count(*) * 100 as fraud_rate,

        sum(amount) as total_amount,
        sumIf(amount, is_fraud = 1) as fraud_amount,
        avg(amount) as avg_amount,
        avgIf(amount, is_fraud = 1) as avg_fraud_amount,

        -- География: где в среднем находится клиент штата.
        avg(lat) as avg_lat,
        avg(lon) as avg_lon,

        -- Насколько клиент и мерчант далеко друг от друга. Разъезд
        -- координат — типичный признак подмены карты.
        avg(distance_km) as avg_distance_km,
        max(distance_km) as max_distance_km,

        -- Клиенты, у которых есть хотя бы одна мошенническая транзакция.
        uniqExactIf(customer_id, is_fraud = 1) as fraud_customers

    from transactions
    group by state

),

final as (

    select
        *,
        fraud_rate / avg(fraud_rate) over () as fraud_rate_index,
        round(fraud_customers / unique_customers * 100, 2) as fraud_customers_share,
        -- Средняя доля фрода по всем штатам — база для сравнения.
        avg(fraud_rate) over () as national_fraud_rate,
        fraud_rate > avg(fraud_rate) over () as above_national_average
    from by_state

)

select
    state,
    transactions_count,
    unique_customers,
    unique_merchants,
    unique_cities,
    fraud_count,
    fraud_rate,
    national_fraud_rate,
    fraud_rate_index,
    above_national_average,
    fraud_customers,
    fraud_customers_share,
    total_amount,
    fraud_amount,
    avg_amount,
    avg_fraud_amount,
    avg_distance_km,
    max_distance_km,
    avg_lat,
    avg_lon
from final
