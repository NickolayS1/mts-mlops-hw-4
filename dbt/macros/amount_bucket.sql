{% macro amount_bucket(column_name) %}
    {#
      Сегмент суммы. Границы взяты из распределения amount: медиана 47,
      средний чек 70, максимум 27 390. Константы, а не квантили:
      квантили пришлось бы считать оконной функцией по всей таблице.
    #}
    CASE
        WHEN {{ column_name }} < 10 THEN 'micro'
        WHEN {{ column_name }} < 50 THEN 'small'
        WHEN {{ column_name }} < 200 THEN 'medium'
        WHEN {{ column_name }} < 1000 THEN 'large'
        ELSE 'extra_large'
    END
{% endmacro %}
