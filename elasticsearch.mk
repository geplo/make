## elasticsearch.mk creates an elasticsearch container and populates zookeeper config.
##
## Targets:
##  - es_start
##  - es_clean
## Requirements:
##  - base
## Options:
##  - $(ES_PORT):     default: 9200
##  - $(ES_USER):     default: `admin`
##  - $(ES_PASSWORD): default: `password`
##  - $(ES_ROLE):     default: `admin`
## Cache files:
##  - .es_id
##  - .es_port
##  - .es_pull

# NOTE: image built from https://github.com/elbow-jason/elasticsearch-with-plugins

ES_C            = $(NAME)_es_c
ES_I            = leafcloud/elasticsearch:latest

ES_PORT        ?= 9200
ES_USER        ?= admin
ES_ROLE        ?= admin
ES_PASSWORD    ?= password

ifeq ($(NOPULL),)
.es_pull         :
		@echo "Pulling latest elasticsearch from tutum.."
		@docker pull $(ES_I) > $@
.es_id          : .es_pull
endif

.es_id          : .docker
		@echo "Running elasticsearch..."
		@docker run -d -p $(ES_PORT) --name $(ES_C) $(ES_I) > /dev/null || (echo >&2; echo 'Elasticsearch cache invalidated, please run `make clean`' >&2; exit 1)
		@while ! docker run --rm --link '$(ES_C):es' sequenceiq/alpine-curl sh -c 'curl -s http://$$ES_PORT_$(ES_PORT)_TCP_ADDR:$(ES_PORT)/ > /dev/null'; do echo "Waiting for elasticsearch to start..."; sleep 1; done
		@docker exec -u elasticsearch $(ES_C) /usr/share/elasticsearch/bin/shield/esusers useradd $(ES_USER) -p $(ES_PASSWORD) -r $(ES_ROLE)
		@docker inspect -f '{{.Id}}' $(ES_C) > $@
		@echo "ElasticSearch up and running."
.es_port        : .es_id .zk_conf
		@echo "Updating elasticsearch config.."
		@$(eval ES_HOST_ACTUAL := $(shell docker inspect -f '{{.NetworkSettings.IPAddress}}' $(ES_C)))
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/elasticsearch {}                           |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/elasticsearch/port     '$(ES_PORT)'        |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/elasticsearch/host     '$(ES_HOST_ACTUAL)' |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/elasticsearch/user     '$(ES_USER)'        |  $(ZKCLI)
		@echo create /$(ZK_PREFIX)/$(ENV_MODE)/config/base/v0/elasticsearch/password '$(ES_PASSWORD)'    |  $(ZKCLI)
		@docker port $(ES_C) $(ES_PORT) | sed 's/.*://' > $@

es_start        : .es_port
start           : es_start
test            : es_start

clean           : es_clean
es_clean        :
		@docker rm -f -v $(ES_C) > /dev/null 2> /dev/null || true
		@rm -f .es_port .es_id .es_pull

.PHONY          : es_start es_clean
