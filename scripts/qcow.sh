#!/usr/bin/env bash

set -eux

# disable apt prompts
export DEBIAN_FRONTEND=noninteractive

# external variables that must be set
echo vars: $ARCH $BINFMT_ARCH $UBUNTU_VERSION

FILENAME="ubuntu-${UBUNTU_VERSION}-minimal-cloudimg-${ARCH}"

SCRIPT_DIR=$(realpath "$(dirname "$(dirname $0)")")
IMG_DIR="$SCRIPT_DIR/dist/img"
CHROOT_DIR=/mnt/colima-img

FILE="$IMG_DIR/$FILENAME"

install_dependencies() (
    apt update
    apt install -y file fdisk libdigest-sha-perl qemu-utils
)

convert_file() (
    qemu-img convert -p -f qcow2 -O raw $FILE.img $FILE.raw
)

extract_partition_offset() (
    fdisk -l $FILE.raw | grep "$FILE.raw1 " | awk -F' ' '{print $2}'
)

mount_partition() (
    mkdir -p $CHROOT_DIR
    mount -o loop,offset=$(($1 * 512)) $FILE.raw $CHROOT_DIR
)

unmount_partition() (
    umount $CHROOT_DIR
)

chroot_exec() (
    chroot $CHROOT_DIR "$@"
)

install_packages() (
    # necessary
    chroot_exec mount -t proc proc /proc
    chroot_exec mount -t devpts devpts /dev/pts

    # internet
    chroot_exec mv /etc/resolv.conf /etc/resolv.conf.bak
    echo 'nameserver 1.1.1.1' >$CHROOT_DIR/etc/resolv.conf

    # packages
    chroot_exec apt update
    chroot_exec apt install -y "$@"
    (
        chroot_exec curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        chroot_exec sh /tmp/get-docker.sh
        chroot_exec rm /tmp/get-docker.sh
    )
    # mark packages as dependencies so that autoremove does not uninstall them
    chroot_exec apt install -y cloud-init lsb-release python3-apt gnupg curl wget

    chroot_exec apt purge -y apport console-setup-linux dbus-user-session dmsetup liblocale-gettext-perl lxd-agent-loader lxd-installer parted pciutils pollinate python3-gi snapd ssh-import-id
    chroot_exec apt purge -y ubuntu-advantage-tools ubuntu-cloud-minimal ubuntu-drivers-common ubuntu-release-upgrader-core unattended-upgrades xz-utils

    chroot_exec apt autoremove -y
    chroot_exec apt-mark hold linux-image-virtual
    chroot_exec apt upgrade -y
    chroot_exec apt clean -y
    chroot_exec sh -c "rm -rf /var/lib/apt/lists/* /var/cache/apt/*"

    # binfmt
    (
        cd /tmp
        tar xfz /build/dist/binfmt/binfmt-${ARCH}.tar.gz
        chown root:root binfmt qemu-${BINFMT_ARCH}
        mv binfmt qemu-${BINFMT_ARCH} ${CHROOT_DIR}/usr/bin
    )

    # containerd
    (
        cd /tmp
        tar Cxfz ${CHROOT_DIR}/usr/local /build/dist/containerd/containerd-utils-${ARCH}.tar.gz
        chroot_exec mkdir -p /opt/cni
        chroot_exec mv /usr/local/libexec/cni /opt/cni/bin
    )

    # clean traces
    chroot_exec rm /etc/resolv.conf
    chroot_exec mv /etc/resolv.conf.bak /etc/resolv.conf
    chroot_exec umount /dev/pts
    chroot_exec umount /proc

    # fill partition with zeros, to recover space during compression
    chroot_exec dd if=/dev/zero of=/root/zero || echo done
    chroot_exec rm -f /root/zero
)

compress_file() (
    qemu-img convert -p -f raw -O qcow2 -c $FILE.raw $FILE.qcow2
    dir="$(dirname $FILE)"
    filename="$(basename $FILE)"
    (cd $dir && shasum -a 512 "${filename}.qcow2" >"${filename}.qcow2.sha512sum")
    rm $FILE.raw
)

# perform all actions
install_dependencies
convert_file
mount_partition "$(extract_partition_offset)"
install_packages iptables socat sshfs
unmount_partition
compress_file
