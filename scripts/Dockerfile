ARG UBUNTU_VERSION

FROM ubuntu:${UBUNTU_VERSION?} AS os

ENV DEBIAN_FRONTEND=noninteractive
# https://bugs.launchpad.net/ubuntu/+source/openssl/+bug/2141933
ENV OPENSSL_FORCE_FIPS_MODE=0
SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

RUN --mount=type=cache,target=/var/cache/apt,rw --mount=type=cache,target=/var/lib/apt,rw <<EOD
echo 'APT::Install-Recommends "0"; APT::Install-Suggests "0"; Acquire::Retries "5"; Dpkg::Use-Pty "0"; Dpkg::Progress-Fancy="0";' > /etc/apt/apt.conf.d/colima
apt-get -qq update
apt-get -qq upgrade
apt-get -qq install -y file kpartx libdigest-sha-perl qemu-utils pigz
EOD

COPY image.sh /image.sh

VOLUME /build

CMD ["/image.sh"]
