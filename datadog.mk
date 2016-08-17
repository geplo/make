## datadog.mk creates a sink container for datadog.
##
## Targets:
##  - dd_sink_start
##  - dd_sink_clean
## Requirements:
##  - base
## Options:
##  - $(DD_SINK_PORT):   default: 8125
##  - $(DISCOVERY_PATH): default: `/tmp/.$(NAME)_discovery`
## Cache files:
##  - .dd_sink_id

DD_SINK_C       = $(NAME)_dd_sink_c
DD_SINK_I       = creack/sink:latest
DD_SINK_PORT   ?= 8125
DISCOVERY_PATH ?= /tmp/.$(NAME)_discovery

ifeq ($(NOPULL),)
.dd_sink_pull   :
		@echo 'Pulling latest datadog sink image..'
		@docker pull $(DD_SINK_I) > $@
.dd_sink_id     : .dd_sink_pull
endif

.dd_sink_id     : .docker
		@docker run -d -v '$(DISCOVERY_PATH):$(DISCOVERY_PATH)' -e DISCOVERY_PATH=$(DISCOVERY_PATH) -p $(DD_SINK_PORT) --name $(DD_SINK_C) --entrypoint /bin/bash $(DD_SINK_I) -c 'echo `hostname -i`:$(DD_SINK_PORT) > $(DISCOVERY_PATH)/datadog && ./sink -mode udp -port $(DD_SINK_PORT)' > /dev/null  || (echo >&2; echo 'Datadog cache invalidated, please run `make clean`' >&2; exit 1)
		@sleep 0.5
		@docker inspect -f '{{.Id}}' $(DD_SINK_C) > $@
		@echo "Datadog sink up and running."

svc_start       : dd_sink_start
svc_test        : dd_sink_start
dd_sink_start   : .dd_sink_id

clean           : dd_sink_clean
dd_sink_clean   :
		@docker rm -f -v $(DD_SINK_C) > /dev/null 2> /dev/null || true
		@rm -f .dd_sink_id .dd_sink_pull

.PHONY          : dd_sink_start dd_sink_clean
