## release.mk builds the release and developement docker images for the project.
##
## Targets:
##  - build:      builds the developement image.
##  - localbuild: builds without docker, to be called within the Dockerfile.
##  - release:    creates the release image.
##  - testing:    pushes the release image to testing.
##  - production: pushes the release image to production.
##  - qa:         pushes the release image to qa.
##  - svc_start:  starts the service container.
##  - confirm:    helper to display a confirmation prompt.
##  - release_clean
## Requirements:
##  - base
## Options:
##  - $(ENVS):           available environements.                         default: qa production testing local.
##  - $(SVC_OPTS):       commandline arguments for the service on start.  default: none.
##  - $(DOCKER_OPTS):    commandline arguments for docker on start.       default: none.
##  - $(TAR_OPTS):       commandline arguments for tar on asset extract.  default: none.
##  - $(ASSETS):         list of files to extract from the build.         default: `./app /etc/ssl`
##  - $(SRCS):           list of files to watch for the cache.            default: `find . -name '*.go'`.
##  - $(RELEASE_I):      name of the release image.                       default: `$(NAME)`.
##  - $(ENV_MODE):       for svc_start, the env_mode to use.              default: `local`.
##  - $(DISCOVERY_PATH): discovery path to use when starting.             default: `/tmp/.$(NAME)_discovery`.
##  - $(LD_FLAGS):       linker flags for `go build`.                     default: `-d` for static linking and multiple -X for metadata.
##  - $(NOCONFIRM):      enable/disable confirmation prompt.              default: `0`. Display confirmation prompt. [0/1]
##  - $(NOGOLANG):       enable/disable release build upon deployment.    default: `0`. Build default Dockerfile.release upon deployment. [0/1]
## Cache files:
##  - .release
##  - .build
##  - .archive.tar.gz

ENVS           ?= qa production testing local staging
ASSETS         ?= app /etc/ssl
RELEASE_I      ?= $(NAME)
SRCS           ?= $(shell find . -name '*.go')
LD_FLAGS       ?= "-d \
			-X github.com/agrarianlabs/service.SvcName=$(NAME) \
			-X github.com/agrarianlabs/service.SvcVersion=$(VERSION) \
			-X github.com/agrarianlabs/service.SCMVersion=$(shell git describe --tags 2> /dev/null || git rev-parse HEAD) \
			-X github.com/agrarianlabs/service.BuildDate=$(shell date -u +%Y-%m-%d-%H:%M:%S)"

### Internal target generation for multiple envs
BUILDS          = $(addprefix .build_,   $(ENVS))
RELEASES        = $(addprefix .release_, $(ENVS))
ARCHIVES        = $(addprefix .archive_, $(ENVS:=.tar.gz))
### !Internal target generation.

# Target ran *inside* docker via the Dockerfile.
localbuild	:
		CGO_ENABLED=0 godep go build -o app -ldflags $(LD_FLAGS)

# Build the dev image with full sources / compiler.
# NOTE: As we build, invalidate cache for any other envs.
$(BUILDS)       : .docker $(SRCS) Dockerfile
		@sh -c 'rm -rf .build_*' > /dev/null 2> /dev/null || true
		@docker build -t $(NAME) .
		@touch $@

# Build the release image from the extracted assets tarball. No sources nor compiler.
# NOTE: As we build, invalidate cache for any other envs.
$(RELEASES)     : .release_%:.archive_%.tar.gz .docker Dockerfile.release
		@sh -c 'rm -rf .release_*' > /dev/null 2> /dev/null || true
		@docker build -t $(RELEASE_I) -f Dockerfile.release .
		@touch $@
# Extract out the assets from the dev image.
# NOTE: As we build, invalidate cache for any other envs.
$(ARCHIVES)     : .archive_%.tar.gz:.build_%
		@sh -c 'rm -rf .archive_*.tar.gz' > /dev/null 2> /dev/null || true
		@docker run --rm $(NAME) tar $(TAR_OPTIONS) -zcf - $(ASSETS) > $@ 2> /dev/null || (rm -f $@; false)
		@cp $@ .archive.tar.gz

$(ENVS)         : %:.release_% confirm
		@docker tag -f $(RELEASE_I):latest $(RELEASE_I):$(@)
		@docker push $(RELEASE_I):$(@)

# Unless we specify NOCONFORM=1, display a confirmation prompt.
ifneq ($(NOCONFIRM),1)
production      : CONFIRM_MESSAGE="Are you sure you want to deploy to Production?"
qa              : CONFIRM_MESSAGE="Are you sure you want to deploy to QA?"
staging         : CONFIRM_MESSAGE="Are you sure you want to deploy to Staging?"
endif

# NOTE: Testing does not use the release image, but the dev one for easier debug.
testing         : RELEASE_I=$(NAME)

svc_start       : .build_local zk_setup dd_sink_start log_sink_start discover_start ec2meta_start
		docker run --name $(NAME)_runtime_c --rm $(DOCKER_OPTS) \
                        -v '$(DISCOVERY_PATH):$(DISCOVERY_PATH)' \
                        -e DISCOVERY_PATH=$(DISCOVERY_PATH) \
                        -e EC2_META_ADDR=http://$(DOCKER_IP):$(shell cat .ec2meta_port) \
                        -e ENV_MODE=$(ENV_MODE) \
                        -e CONFIG_HOST=$(ZK_HOST):$(shell cat .zk_port) \
                        -p $(PORT) \
			$(NAME) ./app $(SVC_OPTS)

clean           : release_clean
release_clean   :
		@sh -c 'rm -rf .archive_*.tar.gz .release_* .build_*'
		@docker rm -f -v $(NAME)_runtime_c > /dev/null 2> /dev/null || true

# Confirmation prompt helper. If the CONFIRM_MESSAGE is empty, skip the confirmation.
CONFIRM_MESSAGE = ""
confirm         :
		@[ $(CONFIRM_MESSAGE) = "" ] && exit 0; echo "$(CONFIRM_MESSAGE) [y/N]"; read REPLY; [ "$$REPLY" = "Y" ] || [ "$$REPLY" = "y" ] || (echo "Cancelled" >&2; exit 2)

.PHONY          : release release_clean build svc_start localbuild confirm $(ENVS)
