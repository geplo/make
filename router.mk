## router.mk creates a router container and populates zookeeper config.
##
## Targets:
##  - router_start
##  - router_clean
## Requirements:
##  - base
## Options:
##  - $(ROUTER_PORT):  Internal port where the router listen to.  default: 8080
##  - $(ROUTER_PORT):  Public port for the router.                default: none
## Cache files:
##  - .router_id
##  - .router_port
##  - .router_pull

ROUTER_C        = $(NAME)_router_c
ROUTER_I        = leafcloud/router:production

ROUTER_PORT    ?= 8080
ROUTER_PUBLIC  ?=

ROUTER_PORT_D  = $(ROUTER_PORT)
ifneq ($(ROUTER_PUBLIC),)
ROUTER_PORT_D := $(ROUTER_PUBLIC):$(ROUTER_PORT_D)
endif

MODULES_DEPS           += redis

ifeq ($(NOPULL),)
.router_pull    :
		@echo "Pulling latest router from tutum.."
		@docker pull $(ROUTER_I) > $@
.router_id      : .router_pull
endif

.router_id      : .zk_port .dd_sink_id .log_sink_id .discover_id .ec2meta_port .redis_port
		@echo "Running router..."
		@docker run -d -p $(ROUTER_PORT_D) --name $(ROUTER_C) \
                         -v '$(DISCOVERY_PATH):$(DISCOVERY_PATH)' \
                         -e DISCOVERY_PATH=$(DISCOVERY_PATH) \
                         -e EC2_META_ADDR=http://$(DOCKER_IP):$(shell cat .ec2meta_port) \
                         -e ENV_MODE=$(ENV_MODE) \
                         -e CONFIG_HOST=$(ZK_HOST):$(shell cat .zk_port) \
                         $(ROUTER_I) ./app > /dev/null || (echo >&2; echo 'Router cache invalidated, please run `make clean`' >&2; exit 1)
		@while ! docker run --rm --link '$(ROUTER_C):router' sequenceiq/alpine-curl sh -c 'curl --fail -s http://$$ROUTER_PORT_$(ROUTER_PORT)_TCP_ADDR:$(ROUTER_PORT)/health'; do echo "Waiting for router to start..."; sleep 1; done
		@docker inspect -f '{{.Id}}' $(ROUTER_C) > $@
		@echo "Router up and running."

.router_port    : .router_id .zk_conf
		@echo "Updating router config..."
		$(eval ROUTER_HOST_ACTUAL := $(shell docker inspect -f '{{.NetworkSettings.IPAddress}}' $(ROUTER_C)))
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/router {}                           |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/router/port '$(ROUTER_PORT)'        |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/router/host '$(ROUTER_HOST_ACTUAL)' |  $(ZKCLI)
		@echo "Updated router config."
ifeq ($(ROUTER_PORT_PUB),)
		@docker port $(ROUTER_C) $(ROUTER_PORT_PUB) | sed 's/.*://' > $@
else
		@docker port $(ROUTER_C) $(ROUTER_PORT) | sed 's/.*://' > $@
endif

router_start    : .router_port
start           : router_start
test            : router_start

clean           : router_clean
router_clean    :
		@docker rm -f -v $(ROUTER_C) > /dev/null 2> /dev/null || true
		@rm -f .router_port .router_id .router_pull

.PHONY          : router_start router_clean
