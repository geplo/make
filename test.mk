## test.mk runs code formatting checks and go tests.
##
## Targets:
##  - svc_test:    run the tests. Generates coverprofile and coverage.xml files.
##  - test_format: run the code validation.
## Options:
##  - $(SKIP_FMT):    if defined, skip the format checks.        default: none.
##  - $(TEST_IMAGE):  name of the image to use to run the tests. default: $(NAME).
##  - $(TEST_OPTS):   arguments to pass to go test.              default: '-v -cover -covermode=count -coverprofile=/tmp/c .'
##  - $(SVC_OPTS):    commandline arguments for the service.     default: none.
##  - $(DOCKER_OPTS): commandline arguments for docker.          default: none.
## Requirements:
##  - base
##  - `build` target which builds the $(TEST_IMAGE).
##
## NOTE: TEST_IMAGE needs to have WORKDIR on the target repo and have govet, golint, godep and goimports imstalled.

TEST_IMAGE     ?= $(NAME)
SRCS           ?= $(shell find . -name '*.go')
TEST_OPTS      ?= -v .
TEST_C          = $(NAME)_test_c

# TODO: allow for a SKIP_FMT variable.
test_format     : .build_$(ENV_MODE)
		@echo "checking go vet..."
		@docker run --rm $(TEST_IMAGE) bash -c '[ -z "$$(go vet ./... |& \grep -v old/ | \grep -v Godeps/ | \grep -v db/migrations/ | \grep -v "exit status" | tee /dev/stderr || true)" ]' || (echo "go vet issue" >&2; exit 1)
		@echo "checking golint..."
		@docker run --rm $(TEST_IMAGE) bash -c '[ -z "$$(golint ./... |& \grep -v old/ | \grep -v Godeps/ | \grep -v db/migrations/ | tee /dev/stderr || true)" ]' || (echo "golint issue" >&2; exit 1)
		@echo "checking gofmt -s..."
		@docker run --rm $(TEST_IMAGE) bash -c '[ -z "$$(gofmt -s -l . |& \grep -v old/ | \grep -v Godeps/ | \grep -v db/migrations/ | tee /dev/stderr || true)" ]' || (echo "gofmt -s issue" >&2; exit 1)
		@echo "checking goimports..."
		@docker run --rm $(TEST_IMAGE) bash -c '[ -z "$$(goimports -l . |& \grep -v old/ | \grep -v Godeps/ | \grep -v db/migrations/ | tee /dev/stderr || true)" ]' || (echo "goimports issue" >&2; exit 1)

# If we don't set SKIP_FMT=1, run the test_format before the tests.
ifeq ($(SKIP_FMT),)
svc_test        : test_format
endif

coverage.xml    : svc_test

svc_test        : .build_$(ENV_MODE) zk_setup dd_sink_start log_sink_start discover_start ec2meta_start
		@echo "running the tests..."
		@docker rm -f $(TEST_C) 2> /dev/null > /dev/null || true
		docker run --name $(TEST_C) $(DOCKER_OPTS) \
                        -v '$(DISCOVERY_PATH):$(DISCOVERY_PATH)' \
                        -e DISCOVERY_PATH=$(DISCOVERY_PATH) \
                        -e EC2_META_ADDR=http://$(DOCKER_IP):$(shell cat .ec2meta_port) \
                        -e ENV_MODE=$(ENV_MODE) \
                        -e CONFIG_HOST=$(ZK_HOST):$(shell cat .zk_port) \
                        -p $(PORT) \
                        $(TEST_IMAGE) godep go test -ldflags $(LD_FLAGS) -tags integration -cover -covermode=count -coverprofile=/tmp/c $(TEST_OPTS) $(SVC_OPTS)
		@docker cp $(TEST_C):/tmp/c - | docker run -i --rm $(TEST_IMAGE) bash -c 'tar -xf- && gocov convert c | gocov-xml' > coverage.xml
		@docker cp $(TEST_C):/tmp/c coverprofile
		@docker rm -f $(TEST_C) 2> /dev/null > /dev/null || true

.PHONY          : svc_test test_format
