## discover.mk creates a discover service container.
##
## Targets:
##  - discover_start
##  - discover_clean
## Requirements:
##  - base
## Options:
##  - $(DISCOVER_PORT):  default: 9090.
##  - $(DISCOVERY_PATH): default: `/tmp/.$(NAME)_discovery`.
## Cache files:
##  - .discover_id

## Source code available at https://github.com/agrarianlabs/localdiscovery.

DISCOVER_C      = $(NAME)_discover_c
DISCOVER_I      = creack/localdiscovery:latest
DISCOVER_PORT  ?= 9090
DISCOVERY_PATH ?= /tmp/.$(NAME)_discovery

# TODO: move the DISCOVERY_PATH in its own makefile.
# TODO: implement health endpoint in localdiscovery service.

ifeq ($(NOPULL),)
.discover_pull  :
		@echo 'Pulling latest discover image..'
		@docker pull $(DISCOVER_I) > $@
.discover_id    : .discover_pull
endif

.discover_id    :
		@docker run -d -v '/var/run/docker.sock:/var/run/docker.sock' -v '$(DISCOVERY_PATH):$(DISCOVERY_PATH)' -e DISCOVERY_PATH=$(DISCOVERY_PATH) -p $(DISCOVER_PORT) --name $(DISCOVER_C) --entrypoint /bin/bash $(DISCOVER_I) -c 'echo `hostname -i`:$(DISCOVER_PORT) > $(DISCOVERY_PATH)/discover && ./discover' > /dev/null  || (echo >&2; echo 'Discovery cache invalidated, please run `make clean`' >&2; exit 1)
		@sleep 0.5
		@docker inspect -f '{{.Id}}' $(DISCOVER_C) > $@
		@echo "Discover service up and running."

svc_start       : discover_start
svc_test        : discover_start
discover_start  : .discover_id

clean           : discover_clean
discover_clean  :
		@docker rm -f -v $(DISCOVER_C) > /dev/null 2> /dev/null || true
		@rm -f .discover_id .discover_pull

.PHONY          : discover_start discover_clean

