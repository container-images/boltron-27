IMAGE_NAME := jamesantill/boltron-27
SYSTEMD_CONTAINER_NAME := boltron
DOCKER_FNAME := Dockerfile
# DOCKER_FNAME := Dockerfile-with-local-dnf

help:
		@echo "make build - Build a new docker image."
		@echo "make update - Build a new docker image, updating baseruntime."
		@echo "make update-force - Build a new docker image, from scratch."
		@echo "make run - Run the new image with bash."
		@echo "make push-james - Push the new build to $(IMAGE_NAME)."
		@echo "make run-systemd - Enables systemd in the container, relies on atomic-cli." \
			"You may need 'setsebool -P container_manage_cgroup 1' in order to make systemd work"
		@echo "make old-run-systemd - Enables systemd in the container." \
			"You may need 'setsebool -P container_manage_cgroup 1' in order to make systemd work"

build:
		@./up-base.sh
		@docker build --file=$(DOCKER_FNAME) . -t $(IMAGE_NAME)
build-force:
		@./up-base.sh
		@docker build --file=$(DOCKER_FNAME) --no-cache . -t $(IMAGE_NAME)

run:
		@docker run --rm -it $(IMAGE_NAME) bash

push-james:
		@docker push $(IMAGE_NAME)

update:
		@docker build --file=$(DOCKER_FNAME) --pull . -t $(IMAGE_NAME)
update-force:
		@docker build --file=$(DOCKER_FNAME) --pull --no-cache . -t $(IMAGE_NAME)

run-systemd:
	docker start $(SYSTEMD_CONTAINER_NAME) || \
	atomic run -n $(SYSTEMD_CONTAINER_NAME) $(IMAGE_NAME)
	@echo -e "\nContainer '$(SYSTEMD_CONTAINER_NAME)' with systemd is running.\n"
	docker exec -ti $(SYSTEMD_CONTAINER_NAME) bash

old-run-systemd:
	docker start $(SYSTEMD_CONTAINER_NAME) || \
	docker run -e container=docker -d \
		-v $(CURDIR)/machine-id:/etc/machine-id:Z \
		--stop-signal="SIGRTMIN+3" \
		--tmpfs /tmp --tmpfs /run \
		--security-opt=seccomp:unconfined \
		-v /sys/fs/cgroup/systemd:/sys/fs/cgroup/systemd \
		--name $(SYSTEMD_CONTAINER_NAME) \
		$(IMAGE_NAME) /sbin/init
	@echo -e "\nContainer '$(SYSTEMD_CONTAINER_NAME)' with systemd is running.\n"
	docker exec -ti $(SYSTEMD_CONTAINER_NAME) bash
