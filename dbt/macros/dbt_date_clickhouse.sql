{#
  Пакет dbt_date не поддерживает ClickHouse: его макросы уходят
  в реализацию по умолчанию и печатают to_char и date_part, которых
  в ClickHouse нет. Здесь эти два макроса переопределяются через
  adapter.dispatch — dbt сам выберет clickhouse-версию при сборке.
#}

{% macro clickhouse__day_of_week(date, isoweek=true) -%}
    {%- if isoweek -%}
    toDayOfWeek({{ date }})
    {%- else -%}
    -- День недели без ISO: воскресенье первое.
    toDayOfWeek({{ date }}) % 7 + 1
    {%- endif -%}
{%- endmacro %}


{% macro clickhouse__day_name(date, short=true) -%}
    {#- В ClickHouse коды формата как в MySQL, а не как в strftime:
        короткое имя даёт '%a', полное — '%W'. -#}
    {%- if short -%}
    formatDateTime({{ date }}, '%a')
    {%- else -%}
    formatDateTime({{ date }}, '%W')
    {%- endif -%}
{%- endmacro %}
