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

tag:
		@docker tag $(IMAGE_NAME) $(IMAGE_NAME):$$(cat latest-Fedora-Modular-27.COMPOSE_ID)
upbase:
		@./up-base.sh
build:
		@docker build --file=$(DOCKER_FNAME) . -t $(IMAGE_NAME)
		@docker tag $(IMAGE_NAME) $(IMAGE_NAME):$$(cat latest-Fedora-Modular-27.COMPOSE_ID)
build-force:
		@./up-base.sh
		@docker build --file=$(DOCKER_FNAME) --no-cache . -t $(IMAGE_NAME)

run:
		@docker run --rm -it $(IMAGE_NAME) bash

push-james:
		@docker push $(IMAGE_NAME)
		@docker push $(IMAGE_NAME):latest

update:
		@docker build --file=$(DOCKER_FNAME) --pull . -t $(IMAGE_NAME)
update-force:
		@docker build --file=$(DOCKER_FNAME) --pull --no-cache . -t $(IMAGE_NAME)

TESTD="test-$$(cat latest-Fedora-Modular-27.COMPOSE_ID)"
tests-setup: build
		@docker build --file=Test-Dockerfile . -t test-$(IMAGE_NAME)
		-@mkdir $(TESTD) 2> /dev/nul

tests-hdr: tests-setup
		@docker run --rm test-$(IMAGE_NAME) /image-data all > $(TESTD)/hdr
		@docker run --rm -v $$(pwd):/mnt  test-$(IMAGE_NAME) /mnt/list-modules-py3.py > $(TESTD)/mods
		@docker run --rm -v $$(pwd):/mnt  test-$(IMAGE_NAME) /mnt/list-rpm.sh > $(TESTD)/rpm
		@docker run --rm -v $$(pwd):/mnt  test-$(IMAGE_NAME) /mnt/list-repos-py3.py > $(TESTD)/repos

tests: tests-hdr
		@cat $(TESTD)/hdr
		@touch $(TESTD)/beg
		@echo "==============================================================="
		@echo -n "Starting Module Install tests: "
		@date --iso=seconds --reference=$(TESTD)/beg | tr T ' '
		@echo "---------------------------------------------------------------"
		@for i in $$(cat $(TESTD)/mods | awk '{ print $$1 }'); do \
		docker run --rm -it test-$(IMAGE_NAME) /test-install.sh $$i ; \
		for j in $$(fgrep $$i $(TESTD)/mods | awk '{ print $$4 }' | tr , " "); do \
		docker run --rm -it test-$(IMAGE_NAME) /test-install.sh $$i/$$j ; \
		done; \
		done | tee $(TESTD)/out
		@touch $(TESTD)/end
		@echo "---------------------------------------------------------------"
		@echo -n "FINNISHED Module Install tests: "
		@date --iso=seconds --reference=$(TESTD)/end | tr T ' '
		@echo "---------------------------------------------------------------"
		@make tests-gather-logs
tests-gather-logs:
		@echo "Gathering logs for failed tests:"
		@for i in $$(fgrep 'FAIL: DNF' $(TESTD)/out | awk '{ print $$1 }'); do \
		j=$$(echo $$i | tr '/' '-'); echo "    $$i"; \
		docker run --rm -it test-$(IMAGE_NAME) dnf module install -y $$i > $(TESTD)/out-$$j-1 2> $(TESTD)/out-$$j-2  || true; \
		done

status:
		@echo -n "Compose Base (remote): "
		@curl https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-27/COMPOSE_ID
		@echo -n " "
		@curl https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-27/STATUS

		@echo -n "Compose Base (local) : "
		@cat latest-Fedora-Modular-27.COMPOSE_ID
		@echo -n " "
		@cat latest-Fedora-Modular-27.STATUS

		@echo -n "Compose Base (prev)  : "
		@cat prev-Fedora-Modular-27.COMPOSE_ID || echo -n "<none>"
		@echo -n " "
		@cat prev-Fedora-Modular-27.STATUS || echo "<none>"

		@echo -n "Compose Bike: "
		@curl https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-Bikeshed/COMPOSE_ID
		@echo -n " "
		@curl https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-Bikeshed/STATUS

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
