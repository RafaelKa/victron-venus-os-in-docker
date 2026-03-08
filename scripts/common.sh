#!/usr/bin/env bash
# common.sh — Shared variables and functions for the build pipeline.
# Source this file from other scripts: . "$(dirname "$0")/common.sh"
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────

VENUS_UPDATE_BASE_URL="https://updates.victronenergy.com/feeds/venus"
MACHINE="${MACHINE:-raspberrypi5}"
FEED="${FEED:-release}"
VENUS_VERSION="${VENUS_VERSION:-latest}"
IMAGE_VARIANT="${IMAGE_VARIANT:-standard}"  # standard or large

# Build directories (relative to project root)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
DOWNLOAD_DIR="${BUILD_DIR}/downloads"
STAGING_DIR="${BUILD_DIR}/rootfs-staging"
OUTPUT_DIR="${BUILD_DIR}/output"

# Image naming
IMAGE_REGISTRY="${IMAGE_REGISTRY:-ghcr.io}"
IMAGE_OWNER="${IMAGE_OWNER:-rafaelka}"
IMAGE_NAME="${IMAGE_NAME:-venus-os}"

# ── Functions ──────────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%H:%M:%S')] $*" >&2
}

log_error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2
}

die() {
    log_error "$@"
    exit 1
}

ensure_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (or with sudo). Needed for loopback mount."
    fi
}

ensure_dirs() {
    mkdir -p "$DOWNLOAD_DIR" "$STAGING_DIR" "$OUTPUT_DIR"
}

# Get the image filename prefix (handles standard vs large variant).
# Victron naming: venus-image-{machine}.wic.gz vs venus-image-large-{machine}.wic.gz
# Usage: get_image_filename [machine] [variant]
get_image_filename() {
    local machine="${1:-$MACHINE}"
    local variant="${2:-$IMAGE_VARIANT}"
    if [[ "$variant" == "large" ]]; then
        echo "venus-image-large-${machine}.wic.gz"
    else
        echo "venus-image-${machine}.wic.gz"
    fi
}

# Get the download URL for a Venus OS image.
# Usage: get_image_url [machine] [feed] [variant]
get_image_url() {
    local machine="${1:-$MACHINE}"
    local feed="${2:-$FEED}"
    local variant="${3:-$IMAGE_VARIANT}"
    local filename
    filename="$(get_image_filename "$machine" "$variant")"
    echo "${VENUS_UPDATE_BASE_URL}/${feed}/images/${machine}/${filename}"
}

# Get the full Docker image tag.
# Usage: get_docker_tag [version] [machine] [variant]
get_docker_tag() {
    local version="${1:-$VENUS_VERSION}"
    local machine="${2:-$MACHINE}"
    local variant="${3:-$IMAGE_VARIANT}"
    local variant_suffix=""
    if [[ "$variant" == "large" ]]; then
        variant_suffix="-large"
    fi
    if [[ "$version" == "latest" ]]; then
        echo "${IMAGE_REGISTRY}/${IMAGE_OWNER}/${IMAGE_NAME}:latest-${machine}${variant_suffix}"
    else
        echo "${IMAGE_REGISTRY}/${IMAGE_OWNER}/${IMAGE_NAME}:v${version}-${machine}${variant_suffix}"
    fi
}

# Clean up loopback devices on exit.
# Usage: register in a trap — trap cleanup_loopback EXIT
cleanup_loopback() {
    if [[ -n "${LOOP_DEVICE:-}" ]]; then
        log "Cleaning up loopback device ${LOOP_DEVICE}..."
        umount "${MOUNT_POINT:-}" 2>/dev/null || true
        losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    fi
}
