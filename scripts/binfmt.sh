#!/usr/bin/env bash

set -ex

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
    FILE="qemu_v7.0.0_linux-${1}.tar.gz"
    URL="https://github.com/tonistiigi/binfmt/releases/download/deploy%2Fv7.0.0-28/${FILE}"
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
    
    sha512sum "${FILE}" > "${FILE}.sha512sum"
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
download arm64 x86_64
download amd64 aarch64

echo download successful
ls -lh $DIST_DIR
