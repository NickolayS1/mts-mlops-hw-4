-- Дата транзакции не может быть в будущем: датасет заканчивается 2020 годом,
-- более поздняя дата означает ошибку разбора времени в staging.
select *
from {{ ref('stg_transactions') }}
where transaction_date > current_date()
