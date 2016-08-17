## postgres.mk creates a postgres container and populates zookeeper config.
##
## Targets:
##  - pg_start
##  - pg_clean
## Requirements:
##  - base
## Options:
##  - $(PG_PORT):     default: 5432
##  - $(PG_USER):     default: `dbuser`
##  - $(PG_PASSWORD): default: ``
##  - $(PG_DB):       default: `dbname`
## Cache files:
##  - .pg_id
##  - .pg_port
##  - .pg_setup

PG_C            = $(NAME)_pg_c
PG_I            = mdillon/postgis:latest

PG_PORT        ?= 5432
PG_USER        ?= dbuser
PG_PASSWORD    ?=
PG_DB          ?= dbname
PG_CONF        ?= /var/lib/postgresql/data/postgresql.conf

ifneq ($(PG_PASSWORD),)
PG_PASSWORD    := WITH PASSWORD '$(PG_PASSWORD)'
endif

ifeq ($(NOPULL),)
.pg_pull        :
		@echo 'Pulling latest postgres image..'
		@docker pull $(PG_I) > $@
.pg_id          : .pg_pull
endif

.pg_id          : .docker
		@docker run -d -p $(PG_PORT) --name $(PG_C) $(PG_I) > /dev/null || (echo >&2; echo 'Postgres cache invalidated, please run `make clean`' >&2; exit 1)
		@while ! docker logs $(PG_C) 2>&1 | grep 'ready for start up' > /dev/null; do echo "Waiting for postgres to initialize..."; sleep 1; if [ "$(docker inspect -f '{{.State.Status}}' $(PG_C))" = "exited" ]; then echo 'Postgres failed to start.' >&2; docker logs $(PG_C) | tail -20; exit 1; fi; done
		@while ! docker exec $(PG_C) psql -h 127.0.0.1 -U postgres -c "SELECT NOW();" > /dev/null 2> /dev/null; do echo "Waiting for postgres to start..."; sleep 1; if [ "$(docker inspect -f '{{.State.Status}}' $(PG_C))" = "exited" ]; then echo 'Postgres failed to start.' >&2; docker logs $(PG_C) | tail -20; exit 1; fi; done
		@docker inspect -f '{{.Id}}' $(PG_C) > $@
		@echo "Postgres up and running."
.pg_port        : .pg_id .zk_conf
		@echo "Updating postgres config.."
		@$(eval PG_HOST_ACTUAL := $(shell docker inspect -f '{{.NetworkSettings.IPAddress}}' $(PG_C)))
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/postgres {}                       |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/postgres/port '$(PG_PORT)'        |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/postgres/host '$(PG_HOST_ACTUAL)' |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/postgres/user '$(PG_USER)'        |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/postgres/database '$(PG_DB)'      |  $(ZKCLI)
		@docker port $(PG_C) $(PG_PORT) | sed 's/.*://' > $@

.pg_setup       : .pg_logging
		@echo "CREATE USER $(PG_USER) $(PG_PASSWORD); CREATE DATABASE $(PG_DB) ENCODING 'UTF8';" | docker exec -i $(PG_C) psql -U postgres
		@echo "CREATE EXTENSION IF NOT EXISTS hstore; CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"" | docker exec -i $(PG_C) psql -U postgres -d $(PG_DB)
		@touch $@

.pg_logging     : .pg_port
		@docker exec $(PG_C) sed -i "s/#log_statement = 'none'/log_statement = 'all'/"    $(PG_CONF)
		@docker exec $(PG_C) sed -i "s/#log_min_error_statement/log_min_error_statement/" $(PG_CONF)
		@docker exec $(PG_C) sed -i "s/#log_duration = off/log_duration = on/"            $(PG_CONF)
		@echo 'SELECT pg_reload_conf();' | docker exec -i $(PG_C) psql -U postgres
		@touch $@

pg_start        : .pg_setup
start           : pg_start
test            : pg_start

clean           : pg_clean
pg_clean        :
		@docker rm -f -v $(PG_C) > /dev/null 2> /dev/null || true
		@rm -f .pg_port .pg_id .pg_setup .pg_logging .pg_pull

.PHONY          : pg_start pg_clean
