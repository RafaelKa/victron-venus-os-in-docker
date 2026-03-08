#!/usr/bin/env bash
# extract-rootfs.sh — Extract the rootfs partition from a Venus OS .wic image.
#
# Usage: ./extract-rootfs.sh [--image path/to/venus.wic.gz] [--output path/to/staging/]
#
# Requires root privileges for loopback mount.
#
# SPDX-License-Identifier: GPL-3.0-or-later

. "$(dirname "$0")/common.sh"

IMAGE_FILE=""
OUTPUT_DIR_OVERRIDE=""

# ── Parse arguments ────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --image)   IMAGE_FILE="$2"; shift 2 ;;
        --output)  OUTPUT_DIR_OVERRIDE="$2"; shift 2 ;;
        --machine) MACHINE="$2"; shift 2 ;;
        --variant) IMAGE_VARIANT="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--image FILE] [--output DIR] [--machine NAME] [--variant TYPE]"
            echo ""
            echo "Extract the rootfs partition from a Venus OS .wic(.gz) image."
            echo "Requires root privileges for loopback mount."
            echo ""
            echo "Options:"
            echo "  --image FILE      Path to .wic or .wic.gz file (auto-detected from machine+variant)"
            echo "  --output DIR      Output staging directory (default: build/rootfs-staging/)"
            echo "  --machine NAME    Machine name (default: raspberrypi5)"
            echo "  --variant TYPE    Image variant: standard|large (default: standard)"
            exit 0
            ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── Validate ───────────────────────────────────────────────────────────────────

ensure_root
ensure_command sfdisk
ensure_command losetup

ensure_dirs

if [[ -z "$IMAGE_FILE" ]]; then
    IMAGE_FILE="${DOWNLOAD_DIR}/$(get_image_filename "$MACHINE" "$IMAGE_VARIANT")"
fi

if [[ -n "$OUTPUT_DIR_OVERRIDE" ]]; then
    STAGING_DIR="$OUTPUT_DIR_OVERRIDE"
fi

[[ -f "$IMAGE_FILE" ]] || die "Image file not found: $IMAGE_FILE"

# ── Decompress if needed ──────────────────────────────────────────────────────

WIC_FILE="${IMAGE_FILE%.gz}"

if [[ "$IMAGE_FILE" == *.gz ]]; then
    if [[ -f "$WIC_FILE" ]]; then
        log "Decompressed image already exists: $WIC_FILE"
    else
        log "Decompressing ${IMAGE_FILE}..."
        gunzip -k "$IMAGE_FILE"
        log "Decompressed to: $WIC_FILE"
    fi
else
    WIC_FILE="$IMAGE_FILE"
fi

# ── Find rootfs partition ─────────────────────────────────────────────────────

log "Analyzing partition table..."
PARTITIONS=$(sfdisk --dump "$WIC_FILE")
echo "$PARTITIONS" >&2

# Find the Linux partition (type 83 = Linux).
# The WIC layout for RPi is: partition 1 = boot (vfat), partition 2 = rootfs (ext4)
# We look for the second partition or the one with type 83/Linux.
ROOTFS_LINE=$(echo "$PARTITIONS" | grep -E '(type=83|type=L\b)' | head -1)

if [[ -z "$ROOTFS_LINE" ]]; then
    # Fallback: take the second partition (typical Venus layout: boot + rootfs)
    ROOTFS_LINE=$(echo "$PARTITIONS" | grep "^${WIC_FILE}" | sed -n '2p')
fi

if [[ -z "$ROOTFS_LINE" ]]; then
    die "Could not identify rootfs partition in image"
fi

# Parse start sector and size from sfdisk output.
# Format: "file.wic2 : start= 45056, size= 2048, type=83"
SECTOR_SIZE=512
START_SECTORS=$(echo "$ROOTFS_LINE" | sed -n 's/.*start=\s*\([0-9]*\).*/\1/p')
SIZE_SECTORS=$(echo "$ROOTFS_LINE" | sed -n 's/.*size=\s*\([0-9]*\).*/\1/p')

if [[ -z "$START_SECTORS" || -z "$SIZE_SECTORS" ]]; then
    die "Could not parse partition offset/size from: $ROOTFS_LINE"
fi

OFFSET=$((START_SECTORS * SECTOR_SIZE))
SIZE=$((SIZE_SECTORS * SECTOR_SIZE))

log "Rootfs partition found:"
log "  Start sector: $START_SECTORS (offset: $OFFSET bytes)"
log "  Size sectors: $SIZE_SECTORS (size: $SIZE bytes / $((SIZE / 1024 / 1024)) MB)"

# ── Mount and extract ─────────────────────────────────────────────────────────

MOUNT_POINT=$(mktemp -d "${BUILD_DIR}/mnt.XXXXXX")
trap cleanup_loopback EXIT

log "Setting up loopback device..."
LOOP_DEVICE=$(losetup --find --show --offset "$OFFSET" --sizelimit "$SIZE" "$WIC_FILE")
log "Loopback device: $LOOP_DEVICE"

log "Mounting rootfs..."
mount -o ro "$LOOP_DEVICE" "$MOUNT_POINT"

log "Copying rootfs to staging directory: $STAGING_DIR"
# Clean staging dir for fresh extraction
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy preserving permissions, ownership, and special files
cp -a "$MOUNT_POINT"/. "$STAGING_DIR"/

log "Cleaning up mount..."
umount "$MOUNT_POINT"
losetup -d "$LOOP_DEVICE"
unset LOOP_DEVICE
rmdir "$MOUNT_POINT"

# Show what we extracted
FILE_COUNT=$(find "$STAGING_DIR" -type f | wc -l)
DIR_SIZE=$(du -sh "$STAGING_DIR" | cut -f1)
log "Extraction complete: $FILE_COUNT files, $DIR_SIZE total"

echo "$STAGING_DIR"
