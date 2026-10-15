-- Доля фрода — это процент, он не выходит за границы 0 и 100.
-- Проверяем все витрины, где колонка fraud_rate вообще есть.
{% set marts = [
    'mart_fraud_by_category',
    'mart_fraud_by_state',
    'mart_hourly_fraud_pattern'
] %}

{% for mart in marts %}
    select
        '{{ mart }}' as model_name,
        fraud_rate
    from {{ ref(mart) }}
    where fraud_rate > 100 or fraud_rate < 0
    {% if not loop.last %}union all{% endif %}
{% endfor %}
