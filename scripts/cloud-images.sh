#!/usr/bin/env bash

set -ex

# switch to dist dir
SCRIPT_DIR=$(realpath "$(dirname "$(dirname $0)")")
DIST_DIR="${SCRIPT_DIR}/dist/img"
mkdir -p $DIST_DIR


cd $DIST_DIR

download() (
    FILE="ubuntu-${UBUNTU_VERSION}-minimal-cloudimg-${1}.img"
    URL="https://cloud-images.ubuntu.com/minimal/releases/${UBUNTU_CODENAME}/release/${FILE}"
    curl -LO $URL

    shasum -a 512 "${FILE}" > "${FILE}.sha512sum"
)


# download
download arm64
download amd64

# validate
(
    curl -sL https://cloud-images.ubuntu.com/minimal/releases/${UBUNTU_CODENAME}/release/SHA256SUMS | grep "64\.img$" | shasum -a 256 --check --status
)

echo download successful
ls -lh .
