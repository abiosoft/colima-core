# image and tool versions
include dependencies.env

UNAME_S := $(shell uname -s)

to_upper = $(shell echo '$1' | tr '[:lower:]' '[:upper:]')

ifeq ($(UNAME_S),Darwin)
    # macOS uses BSD stat
    PRINT_STATS_CMD = stat -f "%N%n |- %z bytes%n '- %Sm"
else
    # Linux (and most others) use GNU stat
    PRINT_STATS_CMD = stat -c "%N\n |- %s bytes\n '- %y"
endif

# quiet target commands by default
ifeq ($(filter $(DEBUG),1 true),)
MAKEFLAGS += -s
else
TARV = v
endif

# which dist image to build (debian or ubuntu)
DIST ?= ubuntu

# runtime
RUNTIMES = docker containerd incus none
RUNTIME ?= docker

# architecture defaults to the current system's.
OS_ARCH ?= $(shell uname -m)
ifeq ($(strip $(OS_ARCH)),arm64)
OS_ARCH = aarch64
endif

# OS_ARCH is derived from `uname -m` but the alternate architecture name (e.g. amd64, arm64)
# is required for Docker and asset downloads.
ARCH_x86_64 = amd64
ARCH_aarch64 = arm64
ARCH = $(ARCH_$(OS_ARCH))

# binfmt needs the opposite of OS_ARCH
BINFMT_ARCH = aarch64
ifeq ($(strip $(OS_ARCH)),aarch64)
BINFMT_ARCH = x86_64
endif

export ARCH
export BINFMT_ARCH

# containerd
CONTAINERD_ARCHIVE ?= dist/containerd/containerd-utils-$(ARCH).tar.gz
NERDCTL_FILE ?= dist/containerd/nerdctl-full-$(NERDCTL_VERSION)-linux-$(ARCH).tar.gz
NERDCTL_URL ?= https://github.com/containerd/nerdctl/releases/download/v$(NERDCTL_VERSION)/$(notdir $(NERDCTL_FILE))
FLANNEL_FILE ?= dist/containerd/cni-plugin-flannel-linux-$(ARCH)-v$(FLANNEL_MINI_VERSION).tgz
FLANNEL_URL ?= https://github.com/flannel-io/cni-plugin/releases/download/v$(FLANNEL_VERSION)/$(notdir $(FLANNEL_FILE))

# binfmt
BINFMT_ARCHIVE = dist/binfmt/binfmt-$(ARCH).tar.gz
BINFMT_DOWNLOAD_URL ?= https://github.com/tonistiigi/binfmt/releases/download/$(BINFMT_VERSION)
BINFMT_FILE ?= dist/binfmt/$(BINFMT_VERSION)/binfmt_linux-$(ARCH).tar.gz
BINFMT_URL ?= $(BINFMT_DOWNLOAD_URL)/$(notdir $(BINFMT_FILE))
BINFMT_QEMU_FILE ?= dist/binfmt/$(BINFMT_QEMU_VERSION)/qemu_v$(BINFMT_QEMU_VERSION)_linux-$(ARCH).tar.gz
BINFMT_QEMU_URL ?= $(BINFMT_DOWNLOAD_URL)/$(notdir $(BINFMT_QEMU_FILE))

# ubuntu
UBUNTU_IMAGE_BASE_URL ?= https://cloud-images.ubuntu.com/minimal/releases/$(UBUNTU_CODENAME)/release-$(UBUNTU_BUILD)
UBUNTU_IMAGE_FILE ?= dist/img/ubuntu-$(UBUNTU_VERSION)-minimal-cloudimg-$(ARCH).img
UBUNTU_IMAGE_SHA_FILE ?= $(UBUNTU_IMAGE_FILE).sha256sum

# debian
DEBIAN_IMAGE_BASE_URL ?= https://cloud.debian.org/images/cloud/$(DEBIAN_CODENAME)/$(DEBIAN_BUILD)
DEBIAN_IMAGE_FILE ?= dist/img/debian-$(DEBIAN_VERSION)-genericcloud-$(ARCH)-$(DEBIAN_BUILD).qcow2
DEBIAN_IMAGE_SHA_FILE ?= $(DEBIAN_IMAGE_FILE).sha512sum

# DIST resolved variables
IMAGE_BASE_URL ?= $($(call to_upper,$(DIST))_IMAGE_BASE_URL)
IMAGE_FILE ?= $($(call to_upper,$(DIST))_IMAGE_FILE)
IMAGE_SHA_FILE ?= $($(call to_upper,$(DIST))_IMAGE_SHA_FILE)
IMAGE_SHA_SIZE ?= $(patsubst .sha%sum,%,$(suffix $(IMAGE_SHA_FILE)))

#
# defines
#

define download_and_verify
$(1):
	@echo "target: $$@"
	mkdir -p $$(@D) && \
	curl -o$$@.download -L $(2) && \
	tar $$(TARV)xzOf $$@.download &> /dev/null || { \
		echo >&2 "error downloading"; \
		exit 1; \
	}
	mv -f $$@.download $$@
endef

# image builder container image
DOCKER_BUILD_IMAGE = scripts/.build-image-stamp
DOCKER_BUILD_IMAGE_SOURCES = scripts/Dockerfile scripts/image.sh
DOCKER_BUILD_IMAGE_TAG = colima-core-builder:latest

IMAGE_DEPENDENCIES = $(DOCKER_BUILD_IMAGE) $(CONTAINERD_ARCHIVE).sha512sum $(BINFMT_ARCHIVE).sha512sum
#
# targets
#

.PHONY: clean distclean image $(RUNTIMES)

# deprecated (default) target
image: $(RUNTIME)

all: $(RUNTIMES)

# rm build targets
clean:
	rm -rf $(IMAGE_DEPENDENCIES) dist/img/*.raw.gz*

# rm + cache
distclean: clean
	rm -rf dist

# base image
$(IMAGE_FILE):
	@echo "target: $@"
	mkdir -p $(@D) && curl -o"$@" -L $(IMAGE_BASE_URL)/$(notdir $@)

$(IMAGE_SHA_FILE): $(IMAGE_FILE)
	@echo "target: $@"
	shasum -a $(IMAGE_SHA_SIZE) $< > $@.tmp
	cd dist/img && ( \
	    curl -sL $(IMAGE_BASE_URL)/SHA$(IMAGE_SHA_SIZE)SUMS | \
	    grep $(notdir $<) | \
	    shasum -a $(IMAGE_SHA_SIZE) --check --status \
	  ) || { \
	    echo >&2 "checksum did not match!"; \
	    rm -f $@.tmp; \
	    mv -f $< $<.invalid; \
	    exit 1; \
	  }
	mv $@.tmp $@

# checksum
%.sha512sum: %
	@echo "target: $@"
	shasum -a 512 $< > $@

# binfmt
$(BINFMT_ARCHIVE): $(BINFMT_FILE) $(BINFMT_QEMU_FILE)
	@echo "target: $@"
	rm -f '$@'
	TMP_DIR=$$(mktemp -d); \
	  trap 'rm -rf "$$TMP_DIR"' EXIT; \
	  for f in $^; do tar $(TARX)zxf "$$f" -C "$$TMP_DIR"; done; \
	  cd "$$TMP_DIR" && tar $(TARV)czf '$(CURDIR)/$@' binfmt qemu-i386 qemu-$(BINFMT_ARCH) || { \
	    echo >&2 "failed to create $@" ; \
	    rm -f '$(CURDIR)/$@'; exit 1; \
	  }

$(eval $(call download_and_verify,$(BINFMT_FILE),$(BINFMT_URL)))
$(eval $(call download_and_verify,$(BINFMT_QEMU_FILE),$(BINFMT_QEMU_URL)))

# containerd
$(CONTAINERD_ARCHIVE): $(NERDCTL_FILE) $(FLANNEL_FILE)
	@echo "target: $@"
	rm -f '$@'
	TMP_DIR=$$(mktemp -d); \
	  trap 'rm -rf "$$TMP_DIR"' EXIT; \
	  for f in $^; do tar $(TARV)xzf "$$f" -C "$$TMP_DIR"; done; \
	  cd "$$TMP_DIR" && tar $(TARV)czf '$(CURDIR)/$@' bin lib libexec share || { \
	    echo >&2 "failed to create $@" ; \
	    rm -f '$(CURDIR)/$@'; exit 1; \
	  }

$(eval $(call download_and_verify,$(NERDCTL_FILE),$(NERDCTL_URL)))
$(eval $(call download_and_verify,$(FLANNEL_FILE),$(FLANNEL_URL)))

# builder
$(DOCKER_BUILD_IMAGE): $(DOCKER_BUILD_IMAGE_SOURCES) Makefile
	docker build --build-arg UBUNTU_VERSION=$(UBUNTU_VERSION) -t $(DOCKER_BUILD_IMAGE_TAG) --iidfile $@ $(dir $@)

# images
$(basename $(IMAGE_FILE))-%.raw.gz: $(IMAGE_SHA_FILE) $(IMAGE_DEPENDENCIES) $(DOCKER_BUILD_IMAGE) Makefile
	if [ $(OS_ARCH) != $(ARCH) ] ; then docker run --privileged --rm tonistiigi/binfmt --install $(BINFMT_ARCH); fi
	docker run --rm -i --tty --privileged \
	  --platform linux/$(ARCH) \
	  --volume $(CURDIR):/build \
	  --env DIST=$(DIST) \
	  --env BINFMT_ARCHIVE=$(BINFMT_ARCHIVE) \
	  --env CONTAINERD_ARCHIVE=$(CONTAINERD_ARCHIVE) \
	  --env IMAGE_FILE=$(IMAGE_FILE) \
	  --env DOCKER_VERSION=$(DOCKER_VERSION) \
	  --env RUNTIME=$* \
	  $(DOCKER_BUILD_IMAGE_TAG) || { \
	  echo >&2 "failed to create $@"; \
	  rm -f '$@'* ; exit 1; \
	}
	touch "$@"

$(RUNTIMES): %: $(basename $(IMAGE_FILE))-%.raw.gz
	$(PRINT_STATS_CMD) $<
