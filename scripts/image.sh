#!/usr/bin/env bash

set -eux

# disable apt prompts
export DEBIAN_FRONTEND=noninteractive

# external variables that must be set
echo vars: $ARCH $BINFMT_ARCH $UBUNTU_VERSION $DOCKER_VERSION $RUNTIME

FILENAME="ubuntu-${UBUNTU_VERSION}-minimal-cloudimg-${ARCH}"

SCRIPT_DIR=$(realpath "$(dirname "$(dirname $0)")")
IMG_DIR="$SCRIPT_DIR/dist/img"
CHROOT_DIR=/mnt/colima-img

FILE="$IMG_DIR/$FILENAME"

install_dependencies() (
	apt-get -qq update
	apt-get -qq install -y file kpartx libdigest-sha-perl qemu-utils pigz
)

convert_file() (
	qemu-img convert -p -f qcow2 -O raw $FILE.img $FILE.raw
)

mount_partition() {
	LOOP_DEV=$(losetup -Pf --show "$FILE.raw")
	kpartx -avs "$LOOP_DEV"
	LOOP_NAME=$(basename "$LOOP_DEV")
	ROOT_PART="/dev/mapper/${LOOP_NAME}p1"
	ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
	mkdir -p "/dev/disk/by-uuid"
	ln -s "/dev/mapper/${LOOP_NAME}p1" "/dev/disk/by-uuid/$ROOT_UUID"
	mkdir -p $CHROOT_DIR
	mount "$ROOT_PART" "$CHROOT_DIR"
}

cleanup() {
	if [ -n "$CHROOT_DIR" ] && mountpoint -q "$CHROOT_DIR"; then
		umount "$CHROOT_DIR/dev/pts" ||:
		umount "$CHROOT_DIR/proc" ||:
		umount "$CHROOT_DIR"
	fi
	if [ -n "$ROOT_UUID" ] && [ -h "/dev/disk/by-uuid/$ROOT_UUID" ]; then
		rm -f "/dev/disk/by-uuid/$ROOT_UUID"
	fi
	if [ -n "$LOOP_DEV" ]; then
		kpartx -dvs "$LOOP_DEV" 2>/dev/null || true
	fi
	if [ -n "$LOOP_DEV" ] && losetup "$LOOP_DEV" >/dev/null 2>&1; then
		losetup -d "$LOOP_DEV"
	fi
}
trap 'cleanup' EXIT

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

	# prepare packages
	chroot_exec apt-get -qq update

	# packages common to all runtimes, to prevent from final purging
	chroot_exec apt-get -qq install -y iptables socat sshfs cloud-init lsb-release python3-apt gnupg curl wget dnsmasq xfsprogs

	# none
	if [ "$RUNTIME" == "none" ]; then
		(
			chroot_exec apt-get -qq install -y htop inetutils-ping dnsutils net-tools netcat-openbsd telnet vim-tiny nano
			chroot_exec apt-get -qq purge -y dmsetup xz-utils
		)
	fi

	# docker
	if [ "$RUNTIME" == "docker" ]; then
		(
			chroot_exec curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
			chroot_exec sh /tmp/get-docker.sh --version $DOCKER_VERSION
			chroot_exec rm /tmp/get-docker.sh
			chroot_exec apt-mark hold docker-ce docker-ce-cli containerd.io
			chroot_exec apt-get -qq purge -y dmsetup xz-utils
		)
	fi

	# containerd
	if [ "$RUNTIME" == "containerd" ]; then
		(
			cd /tmp
			tar Cxfz ${CHROOT_DIR}/usr/local /build/dist/containerd/containerd-utils-${ARCH}.tar.gz
			chroot_exec mkdir -p /opt/cni
			chroot_exec mv /usr/local/libexec/cni /opt/cni/bin
			chroot_exec apt-get -qq purge -y dmsetup xz-utils
		)
	fi

	# incus
	if [ "$RUNTIME" == "incus" ]; then
		(
			chroot_exec mkdir -p /etc/apt/keyrings/
			chroot_exec curl -fsSL https://pkgs.zabbly.com/key.asc -o /etc/apt/keyrings/zabbly.asc
			chroot_exec sh -c 'cat <<EOF > /etc/apt/sources.list.d/zabbly-incus-stable.sources
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/incus/stable
Suites: $(. /etc/os-release && echo ${VERSION_CODENAME})
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/zabbly.asc

EOF'
			chroot_exec apt-get -qq update
			chroot_exec apt-get -qq install -y htop inetutils-ping dnsutils net-tools netcat-openbsd telnet vim-tiny nano
			chroot_exec apt-get -qq install -y incus incus-base incus-client incus-extra incus-ui-canonical zfsutils-linux btrfs-progs lvm2 thin-provisioning-tools
			chroot_exec apt-mark hold incus incus-base incus-client incus-extra incus-ui-canonical zfsutils-linux btrfs-progs lvm2 thin-provisioning-tools
		)
	fi

	chroot_exec apt-get -qq purge -y apport console-setup-linux dbus-user-session liblocale-gettext-perl lxd-agent-loader lxd-installer parted pciutils pollinate python3-gi snapd ssh-import-id
	chroot_exec apt-get -qq purge -y ubuntu-advantage-tools ubuntu-cloud-minimal ubuntu-drivers-common ubuntu-release-upgrader-core unattended-upgrades systemd-resolved

	chroot_exec apt-get autoremove -y
	chroot_exec apt-get clean -y
	chroot_exec sh -c "rm -rf /var/lib/apt/lists/* /var/cache/apt/*"

	# binfmt
	(
		cd /tmp
		tar xfz /build/dist/binfmt/binfmt-${ARCH}.tar.gz
		chown root:root binfmt qemu-i386 qemu-${BINFMT_ARCH}
		mv binfmt qemu-i386 qemu-${BINFMT_ARCH} ${CHROOT_DIR}/usr/bin
	)

	# enable vsock modules at boot
	cat >${CHROOT_DIR}/etc/modules-load.d/vsock.conf <<EOF
vsock
virtio_vsock
EOF

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
	raw_file="${FILE}-${RUNTIME}.raw"
	mv $FILE.raw $raw_file
	pigz -9 -n -f $raw_file
	dir="$(dirname $raw_file)"
	filename="$(basename $raw_file)"
	(cd $dir && shasum -a 512 "${filename}.gz" >"${filename}.gz.sha512sum")
)

# perform all actions
install_dependencies
convert_file
mount_partition
install_packages
unmount_partition
compress_file
