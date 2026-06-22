# image and tool versions
include dependencies.env

# which dist image to build (debian or ubuntu)
DIST ?= ubuntu

# runtime
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
ARCH = $(shell echo "$(ARCH_$(OS_ARCH))")

# binfmt needs the opposite of OS_ARCH
BINFMT_ARCH = aarch64
ifeq ($(strip $(OS_ARCH)),aarch64)
BINFMT_ARCH = x86_64
endif

export ARCH
export BINFMT_ARCH

#
# targets
#

all: image

.PHONY: clean cloud-image
clean:
	rm -rf dist

cloud-image: $(DIST)-cloud-image

ubuntu-cloud-image:
	UBUNTU_VERSION=$(UBUNTU_VERSION) UBUNTU_CODENAME=$(UBUNTU_CODENAME) scripts/cloud-image.sh

binfmt:
	BINFMT_VERSION=$(BINFMT_VERSION) BINFMT_QEMU_VERSION=$(BINFMT_QEMU_VERSION) scripts/binfmt.sh

containerd:
	NERDCTL_VERSION=$(NERDCTL_VERSION) FLANNEL_VERSION=$(FLANNEL_VERSION) FLANNEL_MINI_VERSION=$(FLANNEL_MINI_VERSION) RUNTIME=$(RUNTIME) scripts/containerd.sh

image: $(DIST)-cloud-image binfmt containerd
	UBUNTU_VERSION=$(UBUNTU_VERSION) DOCKER_VERSION=$(DOCKER_VERSION) RUNTIME=$(RUNTIME) scripts/image.docker.sh
