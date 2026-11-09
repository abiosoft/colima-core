#!/usr/bin/env bash

set -eux

# external variables that must be set
echo vars: $DOCKER_VERSION $RUNTIME

BUILD_DIR="/build"
CHROOT_DIR=/mnt/colima-img

IMAGE_FILE="${BUILD_DIR}/${IMAGE_FILE}"
RAW_FILE="${IMAGE_FILE%.*}-${RUNTIME}.raw"

convert_file() (
	qemu-img convert -p -f qcow2 -O raw "${IMAGE_FILE}" "${RAW_FILE}"
)

mount_partitions() {
	mkdir -p "$CHROOT_DIR"

	LOOP_DEV=$(losetup -Pf --show "${RAW_FILE}")
	LOOP_NAME="${LOOP_DEV##*/}"
	FOUND_ROOT="0:0"

	# generate partition device nodes
	for part_sys_path in "/sys/class/block/${LOOP_NAME}/${LOOP_NAME}p"*; do
		PART_PART_ENTRY_UUID=""
		if [ -e "$part_sys_path" ]; then
			PART_NAME="${part_sys_path##*/}"
			read -r PART_MAJ_MIN < "$part_sys_path/dev"
			if [ ! -e "/dev/$PART_NAME" ]; then
				mknod "/dev/$PART_NAME" b "${PART_MAJ_MIN%:*}" "${PART_MAJ_MIN#*:}"
			fi
			# create part uuid dev entries so mounting is easy later
			eval "$(blkid -p -o export /dev/"${PART_NAME}" | sed 's/^/PART_/')"
			# Ubuntu uses labels, make fstab consistent with Debian, which uses partuuid
			if [[ -n "${PART_PART_ENTRY_UUID:-}" ]] ; then
				mkdir -p /dev/disk/by-partuuid
				ln -s ../../"${PART_NAME}" /dev/disk/by-partuuid/"${PART_PART_ENTRY_UUID}"
				# stage fstab updates so Ubuntu fstab (labels) is like Debian (partuuids)
				if [[ -n "${PART_LABEL:-}" ]] ; then
					echo "sed -i 's/LABEL=${PART_LABEL}/PARTUUID=${PART_PART_ENTRY_UUID}/' ${CHROOT_DIR}/etc/fstab" >> /tmp/fstab_update
				fi
			fi
			# guess which is the root dev (usually it's 1), but the largest ext4 partition makes more sense
			if [[ "${PART_TYPE}" == "ext4" ]] && [[ "${FOUND_ROOT##*:}" -lt "${PART_FSSIZE}" ]] ; then
				FOUND_ROOT="/dev/${PART_NAME}:${PART_FSSIZE}"
			fi
		fi
	done

	# mount root so we can mount everything else
	mount "${FOUND_ROOT%%:*}" "${CHROOT_DIR}"

	# update fstab with partuuids
	if [ -f /tmp/fstab_update ]; then
		source /tmp/fstab_update
	fi

	mount --bind /proc "$CHROOT_DIR/proc"
	mount --bind /dev "$CHROOT_DIR/dev"
	mount --bind /sys "$CHROOT_DIR/sys"

	chroot_exec mount -t devpts devpts /dev/pts
	chroot_exec mount -a
}

cleanup() {
	rm -f "${RAW_FILE}"
	if [ -n "$CHROOT_DIR" ] && mountpoint -q "$CHROOT_DIR"; then
		unmount_partitions ||:
	fi
	rm -rf /dev/disk
	if [ -n "$LOOP_DEV" ] && losetup "$LOOP_DEV" >/dev/null 2>&1; then
		losetup -d "$LOOP_DEV"
	fi
}
trap 'cleanup' EXIT

unmount_partitions() (
	chroot_exec umount -a -t nocgroup,nodevtmpfs,noproc,nosysfs
	umount $CHROOT_DIR/sys
	umount $CHROOT_DIR/proc
	umount $CHROOT_DIR
)

chroot_exec() (
	chroot $CHROOT_DIR env DEBIAN_FRONTEND=noninteractive "$@"
)


apt_update_source() {
	chroot_exec apt-get -q update -y -o Dir::Etc::sourcelist="sources.list.d/${1}" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
}

apt_keyring_zabbly() {
	test -f "$CHROOT_DIR/etc/apt/keyrings/zabbly.asc" || {
		chroot_exec install -m 0755 -d /etc/apt/keyrings
		chroot_exec curl -fsSLo zabbly.asc https://pkgs.zabbly.com/key.asc
		chroot_exec install -m 0644 zabbly.asc /etc/apt/keyrings/zabbly.asc
		chroot_exec rm -f zabbly.asc
	}
}

apt_source_zabbly_incus() {
	apt_keyring_zabbly
	chroot_exec sh -c 'cat <<EOF > /etc/apt/sources.list.d/zabbly-incus-stable.sources
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/incus/stable
Suites: $(. /etc/os-release && echo ${VERSION_CODENAME})
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/zabbly.asc
EOF'
	apt_update_source zabbly-incus-stable.sources
}

apt_source_zabbly_kernel() {
	apt_keyring_zabbly
	chroot_exec sh -c 'cat <<EOF > /etc/apt/sources.list.d/zabbly-kernel-stable.sources
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/kernel/stable
Suites: $(. /etc/os-release && echo ${VERSION_CODENAME})
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/zabbly.asc
EOF'
	apt_update_source zabbly-kernel-stable.sources
}

install_packages() (
	echo 'Dpkg::Use-Pty "0"; Dpkg::Progress-Fancy="0";' > $CHROOT_DIR/etc/apt/apt.conf.d/colima
	DPKG_ARCH=$(chroot_exec dpkg --print-architecture)

	# internet
	chroot_exec mv /etc/resolv.conf /etc/resolv.conf.bak
	echo 'nameserver 1.1.1.1' >$CHROOT_DIR/etc/resolv.conf

	# minimal
	echo 'Binary::apt::APT::Keep-Downloaded-Packages "0";' > $CHROOT_DIR/etc/apt/apt.conf.d/01_nocache
	echo 'APT::Install-Recommends "0"; APT::Install-Suggests "0"; Acquire::Retries "5"; Acquire::Retries::Delay::Maximum "30";' >> $CHROOT_DIR/etc/apt/apt.conf.d/colima
	if [ "${DIST}" == "debian" ] ; then
		chroot_exec sed -i 's/Components: main$/Components: main contrib non-free-firmware/' /etc/apt/sources.list.d/debian.sources
		chroot_exec apt-get -q purge -y groff-base man-db manpages
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
	chroot_exec apt-get -q update

	# packages common to all runtimes, to prevent from final purging
	chroot_exec apt-get -q install -y \
		iptables socat sshfs cloud-init lsb-release python3-apt gnupg curl wget dnsmasq rsync xfsprogs \
		htop inetutils-ping dnsutils net-tools netcat-openbsd telnet vim-tiny nano

	# none
	if [ "$RUNTIME" == "none" ]; then
		(
			chroot_exec apt-get -q purge -y xz-utils
		)
	fi

	# docker
	if [ "$RUNTIME" == "docker" ]; then
		(
			chroot_exec curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
			chroot_exec sh /tmp/get-docker.sh --version $DOCKER_VERSION
			chroot_exec rm /tmp/get-docker.sh
			chroot_exec apt-mark hold docker-ce docker-ce-cli containerd.io
			chroot_exec apt-get -q purge -y xz-utils
		)
	fi

	# containerd
	if [ "$RUNTIME" == "containerd" ]; then
		(
			cd /tmp
			tar Cxfz ${CHROOT_DIR}/usr/local "${BUILD_DIR}/${CONTAINERD_ARCHIVE}"
			chroot_exec mkdir -p /opt/cni
			chroot_exec mv /usr/local/libexec/cni /opt/cni/bin
			chroot_exec apt-get -q purge -y xz-utils
		)
	fi

	# incus
	if [ "$RUNTIME" == "incus" ]; then
		(
			apt_source_zabbly_incus

			if [ "${DIST}" == "debian" ] ; then
				chroot_exec apt-get -q install -y dpkg-dev "linux-headers-cloud-${DPKG_ARCH}"
				chroot_exec apt-get -q install -y zfs-dkms
			fi

			chroot_exec apt-get -q install -y incus incus-base incus-client incus-extra incus-ui-canonical zfsutils-linux btrfs-progs lvm2 thin-provisioning-tools nftables
			chroot_exec apt-mark hold incus incus-base incus-client incus-extra incus-ui-canonical zfsutils-linux btrfs-progs lvm2 thin-provisioning-tools nftables
		)
	fi

	chroot_exec apt-get -q purge -y apport console-setup-linux dbus-user-session liblocale-gettext-perl parted pciutils pollinate python3-gi snapd ssh-import-id
	chroot_exec apt-get -q purge -y unattended-upgrades systemd-resolved
	chroot_exec apt-get -q purge -y apt-listchanges apt-utils reportbug screen whiptail xml-core
	chroot_exec apt-get -q purge -y bash-completion

	if [ "$DIST" == "ubuntu" ] ; then
		chroot_exec apt-get -q purge -y lxd-agent-loader lxd-installer ubuntu-advantage-tools ubuntu-cloud-minimal ubuntu-drivers-common ubuntu-release-upgrader-core
	fi

	# cleanup any old kernel versions that may be been upgraded
	KERNEL_VERSIONS=$(chroot_exec dpkg-query -W -f='${Package}\n' | grep -E '^linux-image-[0-9]' | sed 's/^linux-image-//' | sort -V)
	LATEST_VERSION=$(echo "$KERNEL_VERSIONS" | tail -n 1)
	for V in $KERNEL_VERSIONS; do
		if [ "$V" != "$LATEST_VERSION" ]; then
			chroot_exec apt-get -q purge -y "linux-image-$V"
			chroot_exec apt-get -q purge -y "linux-headers-$V" ||:
			chroot_exec apt-get -q purge -y "linux-modules-$V" ||:
			chroot_exec apt-get -q purge -y "linux-modules-extra-$V" ||:
		fi
	done

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

	# console messages to lima serial log
	# https://github.com/lima-vm/lima/issues/1659
	mkdir -p $CHROOT_DIR/etc/default/grub.d
	if [[ "$DIST" == "ubuntu" ]]; then
	cat >"$CHROOT_DIR"/etc/default/grub.d/99-lima-console.cfg <<"EOF"
GRUB_CMDLINE_LINUX_DEFAULT="console=hvc0 earlycon"
EOF
	elif [[ "$DIST" == "debian" ]]; then
	cat >"$CHROOT_DIR"/etc/default/grub.d/99-lima-console.cfg <<"EOF"
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX console=hvc0 earlycon"
EOF
	fi

	chroot_exec update-grub

	# enable vsock modules at boot
	cat >${CHROOT_DIR}/etc/modules-load.d/vsock.conf <<EOF
vsock
virtio_vsock
EOF

	# logging to console
	sed -i -e 's/#\(Storage\)=.*/\1=volatile/' \
	    -e 's/#\(RuntimeMaxUse\)=.*/\1=100M/' \
	    -e 's/#\(ForwardToConsole\)=.*/\1=yes/' $CHROOT_DIR/etc/systemd/journald.conf

	# clean traces
	chroot_exec find /tmp -mindepth 1 -delete
	chroot_exec mv -f /etc/resolv.conf.bak /etc/resolv.conf
	truncate -s 0 $CHROOT_DIR/etc/machine-id

	# fill partition with zeros, to recover space during compression
	chroot_exec dd if=/dev/zero of=/root/zero ||:
	chroot_exec rm -f /root/zero
	chroot_exec fstrim -av
)

compress_file() (
	pigz -n -f "${RAW_FILE}"
	shasum -a 512 "${RAW_FILE}.gz" >"${RAW_FILE}.gz.sha512sum"
)

# perform all actions
convert_file
mount_partitions
install_packages
unmount_partitions
compress_file
