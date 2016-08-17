## Targets:
##  - zk_setup
##  - zk_start
##  - zk_clean
## Requirements:
##  - base
##  - $(DOCKER_IP) or $(ZK_HOST) defined.
## Options:
##  - $(ZK_HOST):     default: $(DOCKER_IP)
##  - $(ZK_PORT):     default: 2181
## Cache files:
##  - .zk_id
##  - .zk_port
##  - .zk_conf

ZK_PREFIX      ?= "service"
ZK_HOST        ?= $(DOCKER_IP)
ZK_PORT        ?= 2181
ZK_I            = jplock/zookeeper
ZK_C            = $(NAME)_zk_c

ZKCLI           = docker run -i --rm --link $(ZK_C):zk creack/zk-shell bash -c 'zk-shell --run-from-stdin $$ZK_PORT_3888_TCP_ADDR' 2> /dev/null

ifeq ($(NOPULL),)
.zk_pull        :
		@echo 'Pulling latest zookeeper image from tutum..'
		@docker pull $(ZK_I) > $@
.zk_id          : .zk_pull
endif

.zk_id          : .docker
		@docker run -d --name $(ZK_C) -p $(ZK_PORT) $(ZK_I) > $@ || (echo >&2; echo 'Zookeeper cache invalidated, please run `make clean`' >&2; exit 1)
		@sleep 2

.zk_port        : .zk_id
		@docker port $(ZK_C) $(ZK_PORT) | sed 's/.*://' > $@

zk_start        : .zk_id

.zk_conf        : .zk_id .zk_port
		@echo 'create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0 {} false false true'               | $(ZKCLI)
		@echo 'create /$(ZK_PREFIX)/$(ENV_MODE)/config/$(NAME)/$(VERSION) {} false false true'    | $(ZKCLI)
		@echo 'create /$(ZK_PREFIX)/$(ENV_MODE)/discovery/$(NAME)/$(VERSION) {} false false true' | $(ZKCLI)
		@touch $@

start           : zk_setup
test            : zk_setup
zk_setup        : start_zk .zk_conf

clean           : zk_clean
zk_clean        :
		@docker rm -f -v $(ZK_C) 2> /dev/null > /dev/null || true
		@rm -f .zk_conf .zk_id .zk_port .zk_pull

.PHONY          : zk_setup start_zk zk_clean
