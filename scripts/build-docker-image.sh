#!/usr/bin/env bash
# build-docker-image.sh — Full pipeline: download → extract → modify → build Docker image.
#
# Usage: ./build-docker-image.sh [--machine raspberrypi5] [--feed release] [--variant standard] [--tag TAG]
#
# Requires root privileges (for rootfs extraction via loopback mount).
#
# SPDX-License-Identifier: GPL-3.0-or-later

. "$(dirname "$0")/common.sh"

CUSTOM_TAG=""
SKIP_DOWNLOAD=0
SKIP_EXTRACT=0

# ── Parse arguments ────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --machine)       MACHINE="$2"; shift 2 ;;
        --feed)          FEED="$2"; shift 2 ;;
        --variant)       IMAGE_VARIANT="$2"; shift 2 ;;
        --tag)           CUSTOM_TAG="$2"; shift 2 ;;
        --skip-download) SKIP_DOWNLOAD=1; shift ;;
        --skip-extract)  SKIP_EXTRACT=1; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Full build pipeline: download → extract → modify → build Docker image."
            echo "Requires root privileges."
            echo ""
            echo "Options:"
            echo "  --machine NAME     Target machine (default: raspberrypi5)"
            echo "  --feed FEED        Release feed (default: release)"
            echo "  --variant TYPE     Image variant: standard|large (default: standard)"
            echo "  --tag TAG          Custom Docker image tag"
            echo "  --skip-download    Skip download step (use existing image)"
            echo "  --skip-extract     Skip extract step (use existing rootfs staging)"
            exit 0
            ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── Validate ───────────────────────────────────────────────────────────────────

ensure_root
ensure_command docker

ensure_dirs

SCRIPTS_DIR="$(dirname "$0")"

# ── Step 1: Download ──────────────────────────────────────────────────────────

if [[ $SKIP_DOWNLOAD -eq 0 ]]; then
    log "═══ Step 1/4: Downloading Venus OS image ═══"
    bash "$SCRIPTS_DIR/download-image.sh" --machine "$MACHINE" --feed "$FEED" --variant "$IMAGE_VARIANT"
else
    log "═══ Step 1/4: Skipping download (--skip-download) ═══"
fi

# ── Step 2: Extract rootfs ────────────────────────────────────────────────────

if [[ $SKIP_EXTRACT -eq 0 ]]; then
    log "═══ Step 2/4: Extracting rootfs ═══"
    bash "$SCRIPTS_DIR/extract-rootfs.sh" --machine "$MACHINE" --variant "$IMAGE_VARIANT"
else
    log "═══ Step 2/4: Skipping extraction (--skip-extract) ═══"
fi

# ── Step 3: Modify rootfs ────────────────────────────────────────────────────

log "═══ Step 3/4: Modifying rootfs for container use ═══"
bash "$SCRIPTS_DIR/modify-rootfs.sh" --rootfs "$STAGING_DIR" --machine "$MACHINE"

# ── Step 4: Build Docker image ────────────────────────────────────────────────

log "═══ Step 4/4: Building Docker image ═══"

# Create rootfs tarball
ROOTFS_TAR="${OUTPUT_DIR}/rootfs.tar"
log "Creating rootfs tarball: $ROOTFS_TAR"
tar -cf "$ROOTFS_TAR" -C "$STAGING_DIR" .
TARBALL_SIZE=$(du -sh "$ROOTFS_TAR" | cut -f1)
log "Rootfs tarball size: $TARBALL_SIZE"

# Determine the Docker image tag
if [[ -n "$CUSTOM_TAG" ]]; then
    DOCKER_TAG="$CUSTOM_TAG"
else
    DOCKER_TAG="$(get_docker_tag "$VENUS_VERSION" "$MACHINE" "$IMAGE_VARIANT")"
fi

# Build Docker image using the Dockerfile
log "Building Docker image: $DOCKER_TAG"
docker build \
    -f "${PROJECT_ROOT}/docker/Dockerfile" \
    -t "$DOCKER_TAG" \
    --build-arg ROOTFS_TAR="rootfs.tar" \
    "$OUTPUT_DIR"

# Also tag as latest for this machine+variant
LATEST_TAG="$(get_docker_tag "latest" "$MACHINE" "$IMAGE_VARIANT")"
if [[ "$DOCKER_TAG" != "$LATEST_TAG" ]]; then
    docker tag "$DOCKER_TAG" "$LATEST_TAG"
    log "Also tagged as: $LATEST_TAG"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

IMAGE_SIZE=$(docker image inspect "$DOCKER_TAG" --format='{{.Size}}' | numfmt --to=iec 2>/dev/null || echo "unknown")

log ""
log "════════════════════════════════════════════════════"
log "  Build complete!"
log "  Image:    $DOCKER_TAG"
log "  Machine:  $MACHINE"
log "  Variant:  $IMAGE_VARIANT"
log "  Feed:     $FEED"
log "  Size:     $IMAGE_SIZE"
log "════════════════════════════════════════════════════"
