import argparse
import csv
import json
import os
import sys
import time

from kafka import KafkaProducer
from kafka.serializer import Serializer


class JsonSerializer(Serializer):
    """Сериализатор сообщений: dict → JSON в UTF-8.

    Наследник нужен потому, что kafka-python с версии 3.0 ругается
    предупреждением на обычную lambda.
    """

    def serialize(self, topic: str, headers, data: dict) -> bytes:
        return json.dumps(data, ensure_ascii=False).encode("utf-8")


def build_row(parts: list) -> dict:
    """Строка CSV → сообщение для топика.

    Числа приводятся здесь, а не в ClickHouse: JSONEachRow разбирает
    значение по типу столбца, и Int64 из строки с пробелом уже не подойдёт.
    Поля берутся по индексу — заголовок фиксирован, словарь на 786k строк лишний.
    """
    return {
        "transaction_time": parts[0],
        "merch": parts[1],
        "cat_id": parts[2],
        "amount": float(parts[3]),
        "name_1": parts[4],
        "name_2": parts[5],
        "gender": parts[6],
        "street": parts[7],
        "one_city": parts[8],
        "us_state": parts[9],
        "post_code": parts[10],
        "lat": float(parts[11]),
        "lon": float(parts[12]),
        "population_city": int(float(parts[13])),
        "jobs": parts[14],
        "merchant_lat": float(parts[15]),
        "merchant_lon": float(parts[16]),
        "target": int(parts[17]),
    }


def iter_rows(path: str, limit: int | None):
    with open(path, newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        next(reader)  # заголовок
        for index, parts in enumerate(reader):
            if limit is not None and index >= limit:
                return
            yield build_row(parts)


def main() -> int:
    parser = argparse.ArgumentParser(description="Загрузка train.csv в топик Kafka")
    parser.add_argument("--csv", default=os.getenv("CSV_PATH", "/data/train.csv"))
    parser.add_argument("--topic", default=os.getenv("KAFKA_TOPIC", "transactions"))
    parser.add_argument(
        "--bootstrap",
        default=os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:29092"),
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Отправить только первые N строк (по умолчанию весь файл)",
    )
    parser.add_argument("--batch-size", type=int, default=10000)
    args = parser.parse_args()

    if not os.path.exists(args.csv):
        print(f"Файл не найден: {args.csv}", file=sys.stderr)
        print(
            "Положите train.csv из соревнования teta-ml-1-2025 в каталог "
            "teta-ml-1-2025/ — он монтируется в контейнер как /data.",
            file=sys.stderr,
        )
        return 1

    producer = KafkaProducer(
        bootstrap_servers=args.bootstrap,
        acks=1,
        # Копим сообщения: на 786k строк накладные расходы на запрос
        # заметнее, чем сериализация.
        linger_ms=50,
        batch_size=1 << 20,
        max_in_flight_requests_per_connection=5,
        compression_type="gzip",
        value_serializer=JsonSerializer(),
    )

    sent = 0
    started = time.monotonic()
    pending = 0

    for row in iter_rows(args.csv, args.limit):
        producer.send(args.topic, value=row)
        sent += 1
        pending += 1
        if pending >= args.batch_size:
            producer.flush()
            pending = 0
            elapsed = time.monotonic() - started
            print(f"отправлено {sent} строк за {elapsed:.1f} с", flush=True)

    producer.flush()
    producer.close()

    elapsed = time.monotonic() - started
    rate = sent / elapsed if elapsed else 0.0
    print(f"готово: {sent} строк в топик '{args.topic}' за {elapsed:.1f} с ({rate:.0f} строк/с)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
