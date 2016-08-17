## nsq.mk creates a sink container for datadog.
##
## Targets:
##  - nsq_start
##  - nsq_clean
## Requirements:
##  - base
## Cache files:
##  - .nsqd_port
##  - .nsqlookupd_id
##  - .nsqlookupd_port

NSQD_C          = $(NAME)_nsqd_c
NSQA_C          = $(NAME)_nsqadmin_c
NSQLD_C         = $(NAME)_nsqlookupd_c
NSQ_I           = nsqio/nsq:latest
NSQ_PORT       ?= 4150
NSQ_HTTP_PORT  ?= 4151
NSQL_PORT      ?= 4160
NSQL_HTTP_PORT ?= 4161
NSQA_HTTP_PORT ?= 4171
DISCOVERY_PATH ?= /tmp/.$(NAME)_discovery

ifeq ($(NOPULL),)
.nsq_pull       :
		@echo 'Pulling latest nsq..'
		@docker pull $(NSQ_I) > $@
.nsqlookupd_id  : .nsq_pull
endif

.nsqadmin_id    : .nsqd_port
		@docker run -d                                   \
                        -v '$(DISCOVERY_PATH):$(DISCOVERY_PATH)' \
                        -e DISCOVERY_PATH=$(DISCOVERY_PATH)      \
                        -p $(NSQA_HTTP_PORT)                     \
                        --name $(NSQA_C)                         \
                        --link $(NSQD_C):nsqd                    \
                        $(NSQ_I)                                 \
                        sh -c '/nsqadmin --nsqd-http-address=nsqd:$(NSQ_HTTP_PORT)' > /dev/null || (echo >&2; echo 'NSQ cache invalidated, please run `make clean`' >&2; exit 1)
		@while ! docker run --rm --link '$(NSQA_C):nsqadmin' sequenceiq/alpine-curl sh -c 'curl --fail -s http://nsqadmin:$(NSQA_HTTP_PORT)/ping > /dev/null'; do echo "Waiting for nsqadmin to start..."; sleep 1; done
		@docker inspect -f '{{.Id}}' $(NSQA_C) > $@
		@echo "nsqadmin up and running."
.nsqadmin_port  : .nsqadmin_id .zk_conf
		@echo "Updating nsqadmin config.."
		@$(eval NSQA_HOST_ACTUAL := $(shell docker inspect -f '{{.NetworkSettings.IPAddress}}' $(NSQA_C)))
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/nsqadmin array                                     | $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/nsqadmin/$(NSQA_HOST_ACTUAL):$(NSQA_HTTP_PORT) '{}'| $(ZKCLI)
		@docker port $(NSQA_C) $(NSQA_HTTP_PORT) | sed 's/.*://' > $@

.nsqd_port      : .nsqlookupd_id
		@docker run -d                                   \
                        -v '$(DISCOVERY_PATH):$(DISCOVERY_PATH)' \
                        -e DISCOVERY_PATH=$(DISCOVERY_PATH)      \
                        -p $(NSQ_PORT)                           \
                        -p $(NSQ_HTTP_PORT)                      \
                        --name $(NSQD_C)                         \
                        --link $(NSQLD_C):$(NSQLD_C)             \
                        $(NSQ_I)                                 \
                        sh -c 'echo `hostname -i`:$(NSQ_PORT) > $(DISCOVERY_PATH)/nsq && \
                               /nsqd --broadcast-address=`hostname -i` --lookupd-tcp-address=$(NSQLD_C):$(NSQL_PORT)' > /dev/null || (echo >&2; echo 'NSQ cache invalidated, please run `make clean`' >&2; exit 1)
		@while ! docker run --rm --link '$(NSQD_C):nsqd' sequenceiq/alpine-curl sh -c 'curl --fail -s http://$$NSQD_PORT_$(NSQ_HTTP_PORT)_TCP_ADDR:$(NSQ_HTTP_PORT)/ping > /dev/null'; do echo "Waiting for nsqd to start..."; sleep 1; done
		@docker port $(NSQD_C) $(NSQ_HTTP_PORT) | sed 's/.*://' > $@
		@echo "nsqd up and running."

.nsqlookupd_id  : .docker
		@docker run -d               \
                        -p $(NSQL_PORT)      \
                        -p $(NSQL_HTTP_PORT) \
                        --name $(NSQLD_C)    \
                        $(NSQ_I) sh -c '/nsqlookupd --broadcast-address `hostname -i`' > /dev/null || (echo >&2; echo 'NSQ cache invalidated, please run `make clean`' >&2; exit 1)
		@while ! docker run --rm --link '$(NSQLD_C):nsqlookupd' sequenceiq/alpine-curl sh -c 'curl --fail -s http://$$NSQLOOKUPD_PORT_$(NSQL_HTTP_PORT)_TCP_ADDR:$(NSQL_HTTP_PORT)/ping > /dev/null'; do echo "Waiting for nsqlookupd to start..."; sleep 1; done
		@docker inspect -f '{{.Id}}' $(NSQLD_C) > $@
		@echo "nsqlookupd up and running."
.nsqlookupd_port: .nsqlookupd_id .zk_conf
		@echo "Updating nsqdlookupd config.."
		@$(eval NSQL_HOST_ACTUAL := $(shell docker inspect -f '{{.NetworkSettings.IPAddress}}' $(NSQLD_C)))
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/nsqlookupd array                                | $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/nsqlookupd/$(NSQL_HOST_ACTUAL):$(NSQL_HTTP_PORT) '{}'| $(ZKCLI)
		@docker port $(NSQLD_C) $(NSQL_HTTP_PORT) | sed 's/.*://' > $@

start           : nsq_start
test            : nsq_start
nsq_start       : .nsqlookupd_port .nsqd_port .nsqadmin_port

clean           : nsq_clean
nsq_clean       :
		@docker rm -f $(NSQD_C) $(NSQLD_C) $(NSQA_C) > /dev/null 2> /dev/null || true
		@rm -f .nsqd_port .nsqlookupd_id .nsqlookupd_port .nsqadmin_port .nsq_pull

.PHONY          : nsq_start nsq_clean
