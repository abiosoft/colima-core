#!/usr/bin/env bash

set -eux

# disable apt prompts
export DEBIAN_FRONTEND=noninteractive

# external variables that must be set
echo vars: $ARCH $BINFMT_ARCH $UBUNTU_VERSION

# computed variables
SCRIPT_DIR=$(realpath "$(dirname "$(dirname $0)")")

# dependencies in case of cross-arch
docker run --privileged --rm tonistiigi/binfmt --install $BINFMT_ARCH

# build qcow image
docker run --rm --privileged \
    --platform linux/$ARCH \
    --volume $SCRIPT_DIR:/build \
    --env ARCH \
    --env BINFMT_ARCH \
    --env UBUNTU_VERSION \
    ubuntu:${UBUNTU_VERSION} /build/scripts/qcow.sh
