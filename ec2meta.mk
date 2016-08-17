## ec2meta.mk creates an ec2 metadata endpoint mock container.
##
## Targets:
##  - ec2meta_start
##  - ec2meta_clean
## Requirements:
##  - base
## Options:
##  - $(EC2META_PORT):   default: 9090
## Cache files:
##  - .ec2meta_id
##  - .ec2meta_port
## Usage: (until TODO completed)
##   Add `-e EC2_META_ADDR=http://$(DOCKER_IP):$(shell cat .ec222meta_port)` when running the service's container.

# TODO: move the address in Zookeeper instead of environement.

EC2META_C      = $(NAME)_ec2meta_c
EC2META_I      = creack/ec2metamock:latest
EC2META_PORT  ?= 9090

ifeq ($(NOPULL),)
.ec2meta_pull   :
		@echo 'Pulling latest ec2meta mock image..'
		@docker pull $(EC2META_I) > $@
.ec2meta_id     : .ec2meta_pull
endif

.ec2meta_id     : .docker
		@docker run -d -p $(EC2META_PORT) --name $(EC2META_C) $(EC2META_I) -port $(EC2META_PORT) -ip $(DOCKER_IP) > /dev/null  || (echo >&2; echo 'EC2 metadata cache invalidated, please run `make clean`' >&2; exit 1)
		@sleep 0.5
		@docker inspect -f '{{.Id}}' $(EC2META_C) > $@
		@echo "ec2metamock up and running"

.ec2meta_port   : .ec2meta_id
		@docker port $(EC2META_C) $(EC2META_PORT) | sed 's/.*://' > $@

svc_start       : ec2meta_start
svc_test        : ec2meta_start
ec2meta_start   : .ec2meta_port

clean           : ec2meta_clean
ec2meta_clean   :
		@docker rm -f $(EC2META_C) > /dev/null 2> /dev/null || true
		@rm -f .ec2meta_id .ec2meta_port .ec2meta_pull

.PHONY          : ec2meta_start ec2meta_clean

