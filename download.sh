#!/usr/bin/env bash

set -ex

download() (
    mkdir -p img
    cd img

    FILE="ubuntu-${VERSION}-minimal-cloudimg-${1}.img"
    URL="https://cloud-images.ubuntu.com/minimal/releases/${CODENAME}/release/${FILE}"
    curl -LO $URL

    sha512sum "${FILE}" > "${FILE}.sha512sum"
)


# download
download arm64
download amd64

# validate
(
    cd img
    curl -LO https://cloud-images.ubuntu.com/minimal/releases/${CODENAME}/release/SHA256SUMS
    cat SHA256SUMS | grep "64\.img" | sha256sum --check --status
)

echo download successful
ls -lh img
