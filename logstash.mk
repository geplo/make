## logstash.mk creates a sink container for logstash.
##
## Targets:
##  - log_sink_start
##  - log_sink_clean
## Requirements:
##  - base
## Options:
##  - $(LOG_SINK_PORT):  default: 5000
##  - $(DISCOVERY_PATH): default: `/tmp/.$(NAME)_discovery`
## Cache files:
##  - .log_sink_id

LOG_SINK_C      = $(NAME)_log_sink_c
LOG_SINK_I      = creack/sink:latest
LOG_SINK_PORT  ?= 5000
DISCOVERY_PATH ?= /tmp/.$(NAME)_discovery

ifeq ($(NOPULL),)
.log_sink_pull  :
		@echo 'Pulling latest logstash sink image..'
		@docker pull $(LOG_SINK_I) > $@
.log_sink_id    : .log_sink_pull
endif

.log_sink_id    : .docker
		@docker run -d -v '$(DISCOVERY_PATH):$(DISCOVERY_PATH)' -e DISCOVERY_PATH=$(DISCOVERY_PATH) -p $(LOG_SINK_PORT) --name $(LOG_SINK_C) --entrypoint /bin/bash $(LOG_SINK_I) -c 'echo `hostname -i`:$(LOG_SINK_PORT) > $(DISCOVERY_PATH)/logstash && ./sink -mode udp -port $(LOG_SINK_PORT)' > /dev/null || (echo >&2; echo 'Logstash cache invalidated, please run `make clean`' >&2; exit 1)
		@sleep 0.5
		@docker inspect -f '{{.Id}}' $(LOG_SINK_C) > $@
		@echo "Logstash sink up and running."

svc_start       : log_sink_start
svc_test        : log_sink_start
log_sink_start  : .log_sink_id

clean           : log_sink_clean
log_sink_clean  :
		@docker rm -f -v $(LOG_SINK_C) > /dev/null 2> /dev/null || true
		@rm -f .log_sink_id .log_sink_pull

.PHONY          : log_sink_start log_sink_clean

