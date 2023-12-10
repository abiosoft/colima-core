#!/usr/bin/env bash

set -eux

# external variables that must be set
echo vars: $ARCH $BINFMT_ARCH

SCRIPT_DIR=$(realpath "$(dirname "$(dirname $0)")")
DIST_DIR="${SCRIPT_DIR}/dist/binfmt"
mkdir -p $DIST_DIR

TEMP_DIR=/tmp/binfmt
mkdir -p $TEMP_DIR
cd $TEMP_DIR

download_binfmt() (
    # download archive
    FILE="binfmt_linux-${1}.tar.gz"
    URL="https://github.com/tonistiigi/binfmt/releases/download/${BINFMT_VERSION}/${FILE}"
    curl -LO $URL

    # extract
    tar xvfz $FILE
)

download_qemu() (
    # download archive
    FILE="qemu_v${BINFMT_QEMU_VERSION}_linux-${1}.tar.gz"
    URL="https://github.com/tonistiigi/binfmt/releases/download/${BINFMT_VERSION}/${FILE}"
    curl -LO $URL

    # extract
    tar xvfz $FILE
)

create_archive() (
    # move required components
    FILE="binfmt-${1}.tar.gz"
    tar cfz $FILE \
        binfmt \
        qemu-${2}

    shasum -a 512 "${FILE}" >"${FILE}.sha512sum"
)

copy_to_dist() (
    # copy to dist dir
    cp "binfmt-${1}.tar.gz" $DIST_DIR
    cp "binfmt-${1}.tar.gz.sha512sum" $DIST_DIR

    # cleanup
    rm -rf "$TEMP_DIR/*"
)

download() (
    download_binfmt "${1}"
    download_qemu "${1}"
    create_archive "${1}" "${2}"
    copy_to_dist "${1}"
)

# download
download $ARCH $BINFMT_ARCH

echo download successful
ls -lh $DIST_DIR
