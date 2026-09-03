-include .env

SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help env bootstrap up down down-v restart logs logs-all ps check urls

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

env: ## Create .env from .env.example if it doesn't exist yet
	@test -f .env || cp .env.example .env
	@echo "Edit .env (especially KRAKEND_CONFIG_DIR) before running 'make up'."

bootstrap: env ## Create data/ subdirectories, normalize ownership on Linux
	mkdir -p data/{mariadb,postgres,mongodb,redis,rabbitmq,redisinsight,pgadmin,cloudbeaver}
ifeq ($(shell uname -s),Linux)
	sudo chown -R $(shell id -u):$(shell id -g) data
endif

up: ## Start the whole stack
	docker compose --env-file .env up -d
	docker compose ps

down: ## Stop the stack, keep data
	docker compose down

down-v: ## Stop the stack and WIPE all data in ./data (asks to confirm)
	@read -p "This deletes everything in ./data — continue? [y/N] " ans; \
		[ "$$ans" = "y" ] || [ "$$ans" = "Y" ] || (echo "Aborted." && exit 1)
	docker compose down -v

restart: ## Restart one service, e.g. make restart SERVICE=postgres
	docker compose restart $(SERVICE)

logs: ## Tail one service's logs, e.g. make logs SERVICE=krakend
	docker compose logs -f --tail=100 $(SERVICE)

logs-all: ## Tail every service's logs
	docker compose logs -f --tail=100

ps: ## List container status
	docker compose ps

check: ## Smoke-check that every data/messaging service responds
	docker compose exec mariadb mariadb-admin -uroot -p"$(MARIADB_ROOT_PASSWORD)" ping
	docker compose exec postgres pg_isready -U "$(POSTGRES_USER)" -d "$(POSTGRES_DB)"
	docker compose exec mongodb mongosh --quiet -u "$(MONGO_INITDB_ROOT_USERNAME)" -p "$(MONGO_INITDB_ROOT_PASSWORD)" --authenticationDatabase admin --eval 'db.adminCommand({ ping: 1 })'
	docker compose exec redis redis-cli -a "$(REDIS_PASSWORD)" ping
	curl -sf -u "$(RABBITMQ_DEFAULT_USER):$(RABBITMQ_DEFAULT_PASS)" http://localhost:$(RABBITMQ_MGMT_PORT)/api/overview
	curl -i http://localhost:$(KRAKEND_PORT)/__health

urls: ## Print every web UI's local URL
	@echo "Portainer:      http://localhost:$(PORTAINER_PORT)"
	@echo "RabbitMQ mgmt:  http://localhost:$(RABBITMQ_MGMT_PORT)"
	@echo "RedisInsight:   http://localhost:$(REDISINSIGHT_PORT)"
	@echo "Mongo Express:  http://localhost:$(MONGO_EXPRESS_PORT)"
	@echo "pgAdmin:        http://localhost:$(PGADMIN_PORT)"
	@echo "CloudBeaver:    http://localhost:$(CLOUDBEAVER_PORT)"
