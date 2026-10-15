.PHONY: help install up down load deps seed run test unit full docs lint fix clean

# Команды проекта. make есть в Linux и macOS; в Windows те же шаги
# выполняются вручную из каталога dbt/ (см. README).
DBT_DIR := dbt

# Путь к dbt: на Linux и macOS бинарь лежит в .venv/bin,
# в Windows — в .venv\Scripts и с расширением .exe.
ifeq ($(wildcard .venv/bin/dbt),)
  DBT      := ../.venv/Scripts/dbt.exe
  SQLFLUFF := ../.venv/Scripts/sqlfluff.exe
else
  DBT      := ../.venv/bin/dbt
  SQLFLUFF := ../.venv/bin/sqlfluff
endif

help:
	@echo "make install   - создать venv и поставить зависимости"
	@echo "make up        - поднять стек и загрузить данные из CSV"
	@echo "make load      - только залить train.csv в топик Kafka"
	@echo "make deps      - установить пакеты dbt"
	@echo "make seed      - загрузить seed states.csv"
	@echo "make run       - собрать модели"
	@echo "make test      - прогнать тесты"
	@echo "make unit      - прогнать unit tests"
	@echo "make full      - deps + seed + run + test"
	@echo "make docs      - сгенерировать документацию"
	@echo "make lint      - проверить SQL линтером"
	@echo "make fix       - применить автоисправления линтера"
	@echo "make down      - остановить стек"
	@echo "make clean     - удалить артефакты сборки"

install:
	python3 -m venv .venv
	.venv/bin/pip install --upgrade pip
	.venv/bin/pip install -r requirements.txt

up:
	docker compose up -d --build
	docker compose run --rm producer

load:
	docker compose run --rm producer

down:
	docker compose down

deps:
	cd $(DBT_DIR) && $(DBT) deps

seed:
	cd $(DBT_DIR) && $(DBT) seed

run:
	cd $(DBT_DIR) && $(DBT) run

test:
	cd $(DBT_DIR) && $(DBT) test

unit:
	cd $(DBT_DIR) && $(DBT) test --select "test_type:unit"

full: deps seed run test

docs:
	cd $(DBT_DIR) && $(DBT) docs generate
	@echo "Документация: $(DBT_DIR)/target/index.html"

lint:
	cd $(DBT_DIR) && $(SQLFLUFF) lint models macros tests seeds

fix:
	cd $(DBT_DIR) && $(SQLFLUFF) fix models tests seeds

clean:
	rm -rf $(DBT_DIR)/target $(DBT_DIR)/dbt_packages $(DBT_DIR)/logs
