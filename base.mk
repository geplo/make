DOCKER_IP      ?= "MISSING DOCKER_IP"
DOCKER_C        = $(NAME)_docker_c
MODULES        += release godeps test zookeeper logstash datadog ec2meta discover
MODULES_DEPS    =
ENV_MODE       ?= local

MODULES        := $(sort $(MODULES))
include $(addprefix $(MAKE_PATH)/, $(MODULES:=.mk))

# Include the dependencies from the loaded modules.
# NOTE: filter out already included ones.
MODULES_DEPS   := $(sort $(filter-out $(MODULES),$(MODULES_DEPS)))
ifneq ($(MODULES_DEPS),)
include $(addprefix $(MAKE_PATH)/, $(MODULES_DEPS:=.mk))
endif

ifeq ($(NOPULL),)
.nopull_warning :
		@echo 'NOTE: NOPULL is not set, will try to pull all required images from remote (unless already done, in which case, run `make clean` to force re-download). Run `make <target> NOPULL=1` to skip.'
		@echo > $@
else
.nopull_warning :
		@echo 'NOTE: NOPULL is set, no remote asset will be pulled. Run `make <target> NOPULL=""` to enable remote pull.'
		@echo > $@
endif
.docker_check   : .nopull_warning

.docker_check   :
		@echo "Using docker on: '$(DOCKER_IP)'."
		@docker ps > /dev/null || (echo >&2; echo "Docker is not accessible." >&2; echo 'Please setup your env so `docker ps` works.' >&2; exit 1)
		@echo "Checking Docker config."
		@docker run -d -i -p 8080 --name $(DOCKER_C) 'alpine:latest' nc -lkp 8080 -e echo > /dev/null
		@while ! docker run --rm --link $(DOCKER_C):docker alpine:latest sh -c 'echo test | nc $$DOCKER_PORT_8080_TCP_ADDR 8080' > /dev/null; do echo "Waiting for docker-check container to start...."; sleep 1; done
		@touch $@
		@echo "Docker Check container up and running."

.docker         : .docker_check
		@$(eval DOCKER_C_PORT := $(shell docker port $(DOCKER_C) 8080 | sed 's/.*://'))
		@docker run --rm alpine:latest sh -c 'echo test | nc $(DOCKER_IP) $(DOCKER_C_PORT)' > /dev/null 2> /dev/null || (echo >&2; echo "Error checking Docker configuration (missing \$$DOCKER_IP?)." >&2; echo 'Linux: export DOCKER_IP=`hostname -i`' >&2; echo 'OSX: export DOCKER_IP=`docker-machine ip <machine name>`' >&2; exit 1)
		@docker rm -f -v $(DOCKER_C) > /dev/null 2> /dev/null || true
		@touch $@
		@echo "Docker is properly configured."

clean           : base_clean
base_clean      :
		@rm -f .docker .docker_check .nopull_warning
		@docker rm -f -v $(DOCKER_C) > /dev/null 2> /dev/null || true

.PHONY          : base_clean
