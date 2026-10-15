with source as (

    select * from {{ source('raw', 'transactions') }}

),

cleaned as (

    select
        -- Ключ строки: у источника нет суррогатного, собираем из полей,
        -- которые в сумме уникальны для транзакции.
        {{ dbt_utils.generate_surrogate_key([
            'transaction_time', 'merch', 'name_1', 'name_2', 'amount'
        ]) }} as transaction_id,

        transaction_time,
        toDate(transaction_time) as transaction_date,
        toHour(transaction_time) as transaction_hour,

        -- dbt_date даёт номер дня недели и его название одной строкой.
        {{ dbt_date.day_of_week('transaction_time', isoweek=false) }} as day_of_week,
        {{ dbt_date.day_name('transaction_time', short=false) }} as day_name,

        merch as merchant_name,
        cat_id as category,

        -- Decimal → Float64: суммы умножаются и делятся в витринах,
        -- а точность до копейки при агрегатах там не нужна.
        toFloat64(amount) as amount,
        {{ amount_bucket('amount') }} as amount_bucket,

        concat(name_1, ' ', name_2) as customer_name,
        name_1 as first_name,
        name_2 as last_name,
        gender,
        -- Один клиент = имя + фамилия + город: полных тёзок в одном городе
        -- в данных не встречается, а без города несколько тысяч строк
        -- склеиваются в одного «клиента».
        {{ dbt_utils.generate_surrogate_key([
            'name_1', 'name_2', 'one_city'
        ]) }} as customer_id,

        us_state as state,
        one_city as city,
        post_code,
        population_city,
        jobs,
        street,
        lat,
        lon,
        merchant_lat,
        merchant_lon,

        -- Расстояние между клиентом и мерчантом в километрах.
        -- Формула гаверсинуса: 6371 — средний радиус Земли.
        -- radians() переводит градусы, cos(radians(lat)) сжимает долготу
        -- к полюсам, иначе расстояние в Монтане и во Флориде считалось бы
        -- одинаково при разной длине градуса.
        2 * 6371 * asin(sqrt(
            pow(sin(radians(merchant_lat - lat) / 2), 2)
            + cos(radians(lat)) * cos(radians(merchant_lat))
            * pow(sin(radians(merchant_lon - lon) / 2), 2)
        )) as distance_km,

        toUInt8(target) as is_fraud

    from source

)

select * from cleaned
