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
build:
		@./up-base.sh
		@docker build --file=$(DOCKER_FNAME) . -t $(IMAGE_NAME)
		@docker tag $(IMAGE_NAME) $(IMAGE_NAME):$$(cat test-Fedora-Modular-27.COMPOSE_ID)
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

tests-setup: build
		@docker build --file=Test-Dockerfile . -t test-$(IMAGE_NAME)
tests: tests-setup
		@docker run --rm -it test-$(IMAGE_NAME) /image-data all | tee tests-hdr
		@touch tests-beg
		@echo "==============================================================="
		@echo -n "Starting Module Install tests: "
		@date --iso=seconds --reference=tests-beg | tr T ' '
		@echo "---------------------------------------------------------------"
		@for i in \
		389-ds \
		X11-base \
		apache-commons \
		autotools \
		bind \
		cloud-init \
		fonts \
		freeipa \
		hardware-support \
		help2man \
		host \
		httpd \
		installer \
		java \
		krb5 \
		mariadb \
		maven \
		mysql \
		networking-base \
		ninja \
		nodejs \
		nodejs:master \
		perl \
		pki \
		platform \
		postgresql \
		python2 \
		python2-ecosystem \
		python3 \
		python3-ecosystem \
		resteasy \
		samba \
		sssd \
		tomcat \
		udisks2 \
		; do \
		docker run --rm -it test-$(IMAGE_NAME) /test-install.sh $$i ; \
		done | tee tests-out
		@touch tests-end
		@echo "---------------------------------------------------------------"
		@echo -n "FINNISHED Module Install tests: "
		@date --iso=seconds --reference=tests-end | tr T ' '
		@echo "---------------------------------------------------------------"

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
