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

COLIMA_START_ARGS=()
if [ -n "${2:-}" ]; then
    COLIMA_START_ARGS+=("-a" "$2")
    shift
fi
COLIMA_START_ARGS+=("-r" "$RUNTIME" "--disk-image" "$IMAGE_FILE" "--force-disk-image")

COLIMA_BIN=colima
if [ -n "${2:-}" ]; then
    COLIMA_BIN="$2"
    shift
fi
if ! "${COLIMA_BIN}" version >/dev/null; then
    echo >&2 "ERROR: working colima command required"
    exit 2
fi

echo "DIST=$DIST RUNTIME=$RUNTIME IMAGE=$BN_IMAGE TYPE=$IMAGE_TYPE COLIMA=${COLIMA_BIN}"

export COLIMA_PROFILE="test$DIST$RUNTIME"

cleanup() {
   if read -r -t 5 -n 1 -p "Press 'y' to keep test profile running, any other key to delete (timeout in 5s)..." REPLY; then
       case "$REPLY" in
           [yY]) exit ;;
       esac
   else
       echo -e "\nTimeout reached. Deleting instance..."
   fi
   echo "==== Delete runtime"
   "${COLIMA_BIN}" delete -d -v -f ||:
}
trap 'cleanup' EXIT

echo "==== Starting runtime"
# gnu timeout (coreutils) is not available everywhere, this perl does the same thing
perl -e 'alarm 60; exec @ARGV' "${COLIMA_BIN}" start "${COLIMA_START_ARGS[@]}"

# check for failed services
echo "==== Test: systemd"
"${COLIMA_BIN}" exec -- sudo systemctl is-system-running

echo "==== Test: $RUNTIME"

if [ "$RUNTIME" == "incus" ] ; then
    "${COLIMA_BIN}" exec -- incus info

    echo "==== Test: launch, exec, stop, delete"
    "${COLIMA_BIN}" exec -- incus launch images:debian/13 debian13
    "${COLIMA_BIN}" exec -- incus list
    "${COLIMA_BIN}" exec -- incus exec debian13 cat /etc/os-release
    "${COLIMA_BIN}" exec -- incus stop debian13
    "${COLIMA_BIN}" exec -- incus delete debian13
    "${COLIMA_BIN}" exec -- incus list
fi

if [ "$RUNTIME" == "docker" ] ; then
    "${COLIMA_BIN}" exec -- docker system info
    "${COLIMA_BIN}" exec -- docker run --rm hello-world:latest
fi

if [ "$RUNTIME" == "containerd" ] ; then
    "${COLIMA_BIN}" exec -- sudo nerdctl system info
    "${COLIMA_BIN}" exec -- sudo nerdctl run --rm hello-world
fi
