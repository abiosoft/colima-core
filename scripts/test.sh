#!/usr/bin/env bash

set -eu

IMAGE_FILE=$1
BN_IMAGE=$(basename "$IMAGE_FILE")
DIST=${BN_IMAGE%%-*}
COMPRESSION=${BN_IMAGE##*.}

BN_IMAGE_T=$(basename -s ".$COMPRESSION" "$BN_IMAGE")
IMAGE_TYPE=${BN_IMAGE_T##*.}

BN_IMAGE_T=$(basename -s ".$IMAGE_TYPE" "$BN_IMAGE_T")
RUNTIME=${BN_IMAGE_T##*-}

echo "DIST=$DIST RUNTIME=$RUNTIME IMAGE=$BN_IMAGE TYPE=$IMAGE_TYPE "

export COLIMA_PROFILE="$RUNTIME.$$"

cleanup() {
   echo "==== Delete runtime"
   colima delete -d -v -f ||:
}
trap 'cleanup' EXIT

echo "==== Starting runtime"
# gnu timeout (coreutils) is not available everywhere, this perl does the same thing
perl -e 'alarm 60; exec @ARGV' colima start \
    -r "$RUNTIME" \
    --disk-image "$IMAGE_FILE" \
    --force-disk-image

# check for failed services
echo "==== Test: systemd"
colima exec -- systemctl --failed

echo "==== Test: $RUNTIME"

if [ "$RUNTIME" == "incus" ] ; then
    colima exec -- incus info

    echo "==== Test: launch, exec, stop, delete"
    colima exec -- incus launch images:debian/13 debian13
    colima exec -- incus list
    colima exec -- incus exec debian13 cat /etc/os-release
    colima exec -- incus stop debian13
    colima exec -- incus delete debian13
    colima exec -- incus list
fi

if [ "$RUNTIME" == "docker" ] ; then
    colima exec -- docker system info
fi
