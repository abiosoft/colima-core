# core dependency
UBUNTU_VERSION ?= 23.10
UBUNTU_CODENAME ?= mantic
BINFMT_VERSION ?= deploy/v7.0.0-28
BINFMT_QEMU_VERSION ?= 7.0.0 

# containerd dependency
NERDCTL_VERSION ?= 1.7.0
FLANNEL_VERSION ?= 1.2.0

.PHONY: all
all: cloud-images binfmt containerd

.PHONY: clean
clean:
	rm -rf dist

.PHONY: cloud-images
cloud-images:
	UBUNTU_VERSION=$(UBUNTU_VERSION) UBUNTU_CODENAME=$(UBUNTU_CODENAME) scripts/cloud-images.sh

.PHONY: binfmt
binfmt:
	BINFMT_VERSION=$(BINFMT_VERSION) BINFMT_QEMU_VERSION=$(BINFMT_QEMU_VERSION) scripts/binfmt.sh

.PHONY: containerd
containerd:
	NERDCTL_VERSION=$(NERDCTL_VERSION) FLANNEL_VERSION=$(FLANNEL_VERSION) scripts/containerd.sh

