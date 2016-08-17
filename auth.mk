## auth.mk creates an auth container and populates zookeeper config.
##
## Targets:
##  - auth_start
##  - auth_clean
## Requirements:
##  - base
##  - postgres
##  - redis
##  - nsq
## Options:
##  - $(AUTH_PORT):      default: 8080
## Cache files:
##  - .auth_id
##  _ .auth_conf
##  - .auth_port
##  - .auth_register
##  - .auth_pull

AUTH_C          = $(NAME)_auth_c
AUTH_I          = leafcloud/auth:production

AUTH_VERSION    = v1

AUTH_PORT      ?= 8080
AUTH_USER      ?= test@example.com
AUTH_PASS      ?= aaaa
AUTH_KEY       ?= zzzz
AUTH_COMPANY   ?= testco

USERS_TABLES     = $(MAKE_PATH)/users_tables.sql
COMPANIES_TABLES = $(MAKE_PATH)/companies_tables.sql

MG_DOMAIN      ?= mail.co.ag
MG_PRIVKEY     ?= xxxx
MG_PUBKEY      ?= yyyy
MG_FROM        ?= 'noreply@mail.co.ag'

# Invite URL configuration.
# This URL must point to the confirmation form, which
# will be in a docker container locally.
WWW_HOST_PORT  ?= 3000
INVITE_URL     ?= http://$(DOCKER_IP):$(WWW_HOST_PORT)/\#/confirminvite

MODULES_DEPS   += postgres redis nsq

$(USERS_TABLES) :
		@echo "Missing users fixtures for auth."; exit 1
$(COMPANIES_TABLES):
		@echo "Missing companies fixtures for auth."; exit 1

.auth_conf      : .tags_setup .zk_conf .pg_setup $(USERS_TABLES) $(COMPANIES_TABLES)
		@echo "Setting up auth config..."
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/auth/$(AUTH_VERSION)/private_key '$(AUTH_KEY)' false false true   | $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/auth/$(AUTH_VERSION)/invite_url $(INVITE_URL)                     | $(ZKCLI)
		@cat $(COMPANIES_TABLES) | docker exec -i $(PG_C) psql -U $(PG_USER) $(PG_DB) > /dev/null
		@cat $(USERS_TABLES) | docker exec -i $(PG_C) psql -U $(PG_USER) $(PG_DB) > /dev/null
		@echo "Auth settings updated."
		@touch $@

ifeq ($(NOPULL),)
.auth_pull      :
		@echo 'Pulling latest auth image from tutum..'
		@docker pull $(AUTH_I) > $@
.auth_id        : .auth_pull
endif

.auth_id        : .auth_conf .pg_port .zk_port .redis_port .dd_sink_id .log_sink_id .discover_id .ec2meta_port .event_topic .mailer_conf
		@echo "Running auth..."
		@docker run -d -p $(AUTH_PORT) --name $(AUTH_C) \
		    -v '$(DISCOVERY_PATH):$(DISCOVERY_PATH)' \
		    -e DISCOVERY_PATH=$(DISCOVERY_PATH) \
		    -e EC2_META_ADDR=http://$(DOCKER_IP):$(shell cat .ec2meta_port) \
		    -e ENV_MODE=$(ENV_MODE) \
		    -e CONFIG_HOST=$(ZK_HOST):$(shell cat .zk_port) \
		    $(AUTH_I) ./app > /dev/null || (echo >&2; echo 'Auth cache invalidated, please run `make clean`' >&2; exit 1)
		@while ! docker run --rm --link '$(AUTH_C):auth' sequenceiq/alpine-curl \
			sh -c 'curl --fail -s http://$$AUTH_PORT_$(AUTH_PORT)_TCP_ADDR:$(AUTH_PORT)/health'; do echo "Waiting for auth to start..."; sleep 1; done
		@docker inspect -f '{{.Id}}' $(AUTH_C) > $@
		@echo "Auth up and running."

.event_topic    : .nsqlookupd_port .nsqd_port
		@docker run --rm --link '$(NSQD_C):nsq' sequenceiq/alpine-curl \
			sh -c 'curl --fail -s -d '"'"'{"event_type":"crud","data":{"kind":"Insert","resource_type":"users","resource":"{\"company_id\":1}"}'"'"' http://nsq:$(NSQ_HTTP_PORT)/put?topic=event'
		@touch $@

.auth_port      : .auth_id .zk_conf
		@echo "Updating auth config..."
		$(eval AUTH_HOST_ACTUAL := $(shell docker inspect -f '{{.NetworkSettings.IPAddress}}' $(AUTH_C)))
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/auth      {}                      |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/auth/port '$(AUTH_PORT)'          |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/auth/host '$(AUTH_HOST_ACTUAL)'   |  $(ZKCLI)
		@echo "Updated auth config."
		@docker port $(AUTH_C) $(AUTH_PORT) | sed 's/.*://' > $@

.mailer_conf    : .zk_conf
		@echo "Updating mailer config..."
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/mailer         {}                 |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/mailer/domain  '$(MG_DOMAIN)'     |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/mailer/privkey '$(MG_PRIVKEY)'    |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/mailer/pubkey  '$(MG_PUBKEY)'     |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/mailer/from    '$(MG_FROM)'       |  $(ZKCLI)
		@echo "Updated mailer config."
		@touch $@

.auth_register  : .auth_port
		@docker run --rm --link '$(AUTH_C):auth' sequenceiq/alpine-curl sh -c \
			'curl --fail -s -X POST -d '"'"'{"first_name":"testuser","last_name":"testuser","email":"$(AUTH_USER)","password":"$(AUTH_PASS)","company_name":"$(AUTH_COMPANY)","private_key":"$(AUTH_KEY)"}'"'"' http://$$AUTH_PORT_$(AUTH_PORT)_TCP_ADDR:$(AUTH_PORT)/register' || \
				(echo >&2; echo "Failed to create test user in auth service" >&2; echo "Auth logs:" >&2; docker logs --tail=15 $(AUTH_C) >&2; exit 1)
		@touch $@

auth_start      : .auth_register
start           : auth_start
test            : auth_start

clean           : auth_clean
auth_clean      :
		@docker rm -f -v $(AUTH_C) > /dev/null 2> /dev/null || true
		@rm -f .auth_port .auth_id .auth_conf .auth_register .auth_pull .mailer_conf .event_topic

.PHONY          : auth_start auth_clean
