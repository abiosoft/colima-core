#!/usr/bin/env bash

set -eux

# disable apt prompts
export DEBIAN_FRONTEND=noninteractive

# external variables that must be set
echo vars: $DOCKER_VERSION $RUNTIME

BUILD_DIR="/build"
CHROOT_DIR=/mnt/colima-img

IMAGE_FILE="${BUILD_DIR}/${IMAGE_FILE}"
RAW_FILE="${IMAGE_FILE%.*}-${RUNTIME}.raw"

convert_file() (
	qemu-img convert -p -f qcow2 -O raw "${IMAGE_FILE}" "${RAW_FILE}"
)

mount_partition() {
	LOOP_DEV=$(losetup -Pf --show "${RAW_FILE}")
	kpartx -avs "$LOOP_DEV"
	LOOP_NAME=$(basename "$LOOP_DEV")
	ROOT_PART="/dev/mapper/${LOOP_NAME}p1"
	ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
	mkdir -p "/dev/disk/by-uuid"
	ln -s "/dev/mapper/${LOOP_NAME}p1" "/dev/disk/by-uuid/$ROOT_UUID"
	mkdir -p $CHROOT_DIR

	mount "$ROOT_PART" "$CHROOT_DIR"
	mount --bind /proc "$CHROOT_DIR/proc"
	mount --bind /dev "$CHROOT_DIR/dev"
	mount --bind /sys "$CHROOT_DIR/sys"
	chroot_exec mount -t devpts devpts /dev/pts
}

cleanup() {
	rm -f "${RAW_FILE}"
	if [ -n "$CHROOT_DIR" ] && mountpoint -q "$CHROOT_DIR"; then
		unmount_partition ||:
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
	umount $CHROOT_DIR/sys
	umount $CHROOT_DIR/dev/pts
	umount $CHROOT_DIR/dev
	umount $CHROOT_DIR/proc
	umount $CHROOT_DIR
)

chroot_exec() (
	chroot $CHROOT_DIR "$@"
)

install_packages() (
	echo 'Dpkg::Use-Pty "0"; Dpkg::Progress-Fancy="0";' > $CHROOT_DIR/etc/apt/apt.conf.d/colima

	# internet
	chroot_exec mv /etc/resolv.conf /etc/resolv.conf.bak
	echo 'nameserver 1.1.1.1' >$CHROOT_DIR/etc/resolv.conf

	# minimal
	echo 'Binary::apt::APT::Keep-Downloaded-Packages "0";' > $CHROOT_DIR/etc/apt/apt.conf.d/01_nocache
	echo 'APT::Install-Recommends "0"; APT::Install-Suggests "0"; Acquire::Retries "5";' >> $CHROOT_DIR/etc/apt/apt.conf.d/colima
	if [ "${DIST}" == "debian" ] ; then
		chroot_exec apt-get -qq purge -y groff-base man-db manpages
	fi
	cat >$CHROOT_DIR/etc/dpkg/dpkg.cfg.d/01_nodoc <<"EOF"
path-exclude=/usr/share/locale/*;
path-exclude=/usr/share/man/*;
path-exclude=/usr/share/doc/*;
path-include=/usr/share/doc/*/copyright;
EOF
	pushd $CHROOT_DIR
	find usr/share/doc/ usr/share/man usr/share/locale/ -mindepth 1 -delete
	popd

	# prepare packages
	chroot_exec apt-get -qq update

	# packages common to all runtimes, to prevent from final purging
	chroot_exec apt-get -qq install -y iptables socat sshfs cloud-init lsb-release python3-apt gnupg curl wget dnsmasq xfsprogs \
		htop inetutils-ping dnsutils net-tools netcat-openbsd telnet

	# none
	if [ "$RUNTIME" == "none" ]; then
		(
			chroot_exec apt-get -qq purge -y xz-utils
		)
	fi

	# docker
	if [ "$RUNTIME" == "docker" ]; then
		(
			chroot_exec curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
			chroot_exec sh /tmp/get-docker.sh --version $DOCKER_VERSION
			chroot_exec rm /tmp/get-docker.sh
			chroot_exec apt-mark hold docker-ce docker-ce-cli containerd.io
			chroot_exec apt-get -qq purge -y xz-utils
		)
	fi

	# containerd
	if [ "$RUNTIME" == "containerd" ]; then
		(
			cd /tmp
			tar Cxfz ${CHROOT_DIR}/usr/local "${BUILD_DIR}/${CONTAINERD_ARCHIVE}"
			chroot_exec mkdir -p /opt/cni
			chroot_exec mv /usr/local/libexec/cni /opt/cni/bin
			chroot_exec apt-get -qq purge -y xz-utils
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
			chroot_exec apt-get -qq install -y incus incus-base incus-client incus-extra incus-ui-canonical zfsutils-linux btrfs-progs lvm2 thin-provisioning-tools nftables
			chroot_exec apt-mark hold incus incus-base incus-client incus-extra incus-ui-canonical zfsutils-linux btrfs-progs lvm2 thin-provisioning-tools nftables
		)
	fi

	chroot_exec apt-get -qq purge -y apport console-setup-linux dbus-user-session liblocale-gettext-perl parted pciutils pollinate python3-gi snapd ssh-import-id
	chroot_exec apt-get -qq purge -y unattended-upgrades systemd-resolved
	chroot_exec apt-get -qq purge -y apt-listchanges apt-utils reportbug screen whiptail xml-core
	chroot_exec apt-get -qq purge -y bash-completion

	if [ "$DIST" == "ubuntu" ] ; then
		chroot_exec apt-get -qq purge -y lxd-agent-loader lxd-installer ubuntu-advantage-tools ubuntu-cloud-minimal ubuntu-drivers-common ubuntu-release-upgrader-core
	fi

	chroot_exec apt-get autoremove -y
	chroot_exec apt-get clean -y
	chroot_exec sh -c "rm -rf /var/lib/apt/lists/* /var/cache/apt/*"

	# binfmt
	(
		cd /tmp
		tar xfz "${BUILD_DIR}/${BINFMT_ARCHIVE}"
		chown root:root binfmt qemu-*
		mv binfmt qemu-* ${CHROOT_DIR}/usr/bin
	)

	# enable vsock modules at boot
	cat >${CHROOT_DIR}/etc/modules-load.d/vsock.conf <<EOF
vsock
virtio_vsock
EOF

	# clean traces
	chroot_exec find /tmp -mindepth 1 -delete
	chroot_exec rm /etc/resolv.conf
	chroot_exec mv /etc/resolv.conf.bak /etc/resolv.conf

	# fill partition with zeros, to recover space during compression
	chroot_exec dd if=/dev/zero of=/root/zero || echo done
	chroot_exec rm -f /root/zero
	chroot_exec fstrim -av
)

compress_file() (
	pigz -9 -n -f "${RAW_FILE}"
	shasum -a 512 "${RAW_FILE}.gz" >"${RAW_FILE}.gz.sha512sum"
)

# perform all actions
convert_file
mount_partition
install_packages
unmount_partition
compress_file
