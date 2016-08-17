## redis.mk creates a redis container and populates zookeeper config.
##
## Targets:
##  - redis_start
##  - redis_clean
## Requirements:
##  - base
## Options:
##  - $(REDIS_PORT):  default: 6379
## Cache files:
##  - .redis_id
##  - .redids_port

REDIS_PASSWORD ?= ""

REDIS_C         = $(NAME)_redis_c
REDIS_I         = redis:latest
REDIS_PORT     ?= 6379

ifeq ($(NOPULL),)
.redis_pull     :
		@echo 'Pulling latest postgres image..'
		@docker pull $(REDIS_I) > $@
.redis_id       : .redis_pull
endif

.redis_id       : .docker
		@docker run -d -p $(REDIS_PORT) --name $(REDIS_C) $(REDIS_I) > /dev/null || (echo >&2; echo 'Redis cache invalidated, please run `make clean`' >&2; exit 1)
		@while ! docker run --rm --link $(REDIS_C):redis alpine:latest sh -c 'echo stats | nc $$REDIS_PORT_$(REDIS_PORT)_TCP_ADDR $(REDIS_PORT)' > /dev/null 2> /dev/null; do echo "Waiting for redis to start..."; sleep 1; done
		@docker inspect -f '{{.Id}}' $(REDIS_C) > $@
		@echo "Redis up and running."

.redis_port     : .redis_id .zk_conf
		@echo "Updating redis config.."
		@$(eval REDIS_HOST_ACTUAL := $(shell docker inspect -f '{{.NetworkSettings.IPAddress}}' $(REDIS_C)))
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/redis {}                              |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/redis/port     '$(REDIS_PORT)'        |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/redis/host     '$(REDIS_HOST_ACTUAL)' |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/redis/password '$(REDIS_PASSWORD)'    |  $(ZKCLI)
		@docker port $(REDIS_C) $(REDIS_PORT) | sed 's/.*://' > $@

start           : redis_start
test            : redis_start
redis_start     : .redis_port

clean           : redis_clean
redis_clean     :
		@docker rm -f -v $(REDIS_C) > /dev/null 2> /dev/null || true
		@rm -f .redis_port .redis_id .redis_pull

.PHONY          : redis_start redis_clean

