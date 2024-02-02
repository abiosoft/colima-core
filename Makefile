# core dependency
UBUNTU_VERSION ?= 23.10
UBUNTU_CODENAME ?= mantic
BINFMT_VERSION ?= deploy/v7.0.0-28
BINFMT_QEMU_VERSION ?= 7.0.0 

# docker
DOCKER_VERSION=24.0.9

# containerd dependency
NERDCTL_VERSION ?= 1.7.3
FLANNEL_VERSION ?= 1.2.0

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

#
# targets
#

all: qcow

.PHONY: clean
clean:
	rm -rf dist

cloud-image:
	ARCH=$(ARCH) UBUNTU_VERSION=$(UBUNTU_VERSION) UBUNTU_CODENAME=$(UBUNTU_CODENAME) scripts/cloud-image.sh

binfmt:
	ARCH=$(ARCH) BINFMT_ARCH=$(BINFMT_ARCH) BINFMT_VERSION=$(BINFMT_VERSION) BINFMT_QEMU_VERSION=$(BINFMT_QEMU_VERSION) scripts/binfmt.sh

containerd:
	ARCH=$(ARCH) NERDCTL_VERSION=$(NERDCTL_VERSION) FLANNEL_VERSION=$(FLANNEL_VERSION) scripts/containerd.sh

qcow: cloud-image binfmt containerd
	ARCH=$(ARCH) BINFMT_ARCH=$(BINFMT_ARCH) UBUNTU_VERSION=$(UBUNTU_VERSION) DOCKER_VERSION=$(DOCKER_VERSION) scripts/qcow.docker.sh
