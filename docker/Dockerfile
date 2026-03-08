# Venus OS in Docker — Single-layer image from modified rootfs.
#
# This Dockerfile is intentionally minimal. All rootfs modifications
# are applied BEFORE this stage (by scripts/modify-rootfs.sh) to
# keep the image as a single layer.
#
# SPDX-License-Identifier: GPL-3.0-or-later

FROM scratch

ARG ROOTFS_TAR=rootfs.tar

ADD ${ROOTFS_TAR} /

VOLUME /data

EXPOSE 22 80 443 1883 9001

ENTRYPOINT ["/entrypoint.sh"]
