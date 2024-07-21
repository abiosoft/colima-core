#!/usr/bin/env bash

set -ex

SCRIPT_DIR=$(realpath "$(dirname "$(dirname $0)")")
DIST_DIR="${SCRIPT_DIR}/dist/containerd"
mkdir -p $DIST_DIR

TEMP_DIR=/tmp/containerd
mkdir -p $TEMP_DIR
cd $TEMP_DIR

download_containerd() (
    # download archive
    FILE="nerdctl-full-${NERDCTL_VERSION}-linux-${1}.tar.gz"
    URL="https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/${FILE}"
    curl -LO $URL

    # validate
    curl -sL "https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/SHA256SUMS" | grep "${FILE}" | shasum -a 256 --check --status

    # extract
    tar xvfz $FILE
)

download_flannel() (
    # download archive
    FILE="cni-plugin-flannel-linux-${1}-v${FLANNEL_VERSION}.tgz"
    URL="https://github.com/flannel-io/cni-plugin/releases/download/v${FLANNEL_VERSION}/${FILE}"
    curl -LO $URL

    # validate
    curl -sL "${URL}.sha512" | shasum -a 512 --check --status

    # extract
    tar xvfz "$FILE"
    mv "flannel-${1}" libexec/cni/flannel
)

create_archive() (
    # move required components
    FILE="containerd-utils-${1}.tar.gz"
    tar cfz $FILE \
        bin \
        lib \
        libexec \
        share

    shasum -a 512 "${FILE}" >"${FILE}.sha512sum"
)

copy_to_dist() (
    # copy to dist dir
    cp "containerd-utils-${1}.tar.gz" $DIST_DIR
    cp "containerd-utils-${1}.tar.gz.sha512sum" $DIST_DIR

    # cleanup
    rm -rf "$TEMP_DIR/*"
)

download() (
    download_containerd "${1}"
    download_flannel "${1}"
    create_archive "${1}"
    copy_to_dist "${1}"
)

# download
download $ARCH

echo download successful
ls -lh $DIST_DIR
