#!/usr/bin/env bash
# download-image.sh — Download a Venus OS image from Victron's update server.
#
# Usage: ./download-image.sh [--machine raspberrypi5] [--feed release]
#
# Environment variables (override defaults):
#   MACHINE   — Target machine (default: raspberrypi5)
#   FEED      — Release feed: release|candidate|testing|develop (default: release)
#
# SPDX-License-Identifier: GPL-3.0-or-later

. "$(dirname "$0")/common.sh"

# ── Parse arguments ────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --machine) MACHINE="$2"; shift 2 ;;
        --feed)    FEED="$2"; shift 2 ;;
        --output)  DOWNLOAD_DIR="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--machine NAME] [--feed FEED] [--output DIR]"
            echo ""
            echo "Download a Venus OS image from Victron's update server."
            echo ""
            echo "Options:"
            echo "  --machine NAME   Target machine (default: raspberrypi5)"
            echo "  --feed FEED      Release feed: release|candidate|testing|develop (default: release)"
            echo "  --output DIR     Download directory (default: build/downloads/)"
            exit 0
            ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── Validate ───────────────────────────────────────────────────────────────────

ensure_command curl

VALID_FEEDS="release candidate testing develop"
if [[ ! " $VALID_FEEDS " =~ " $FEED " ]]; then
    die "Invalid feed '$FEED'. Must be one of: $VALID_FEEDS"
fi

# ── Download ───────────────────────────────────────────────────────────────────

ensure_dirs

IMAGE_URL="$(get_image_url "$MACHINE" "$FEED")"
IMAGE_FILE="${DOWNLOAD_DIR}/venus-image-${MACHINE}.wic.gz"

log "Downloading Venus OS image..."
log "  Machine: ${MACHINE}"
log "  Feed:    ${FEED}"
log "  URL:     ${IMAGE_URL}"
log "  Output:  ${IMAGE_FILE}"

if [[ -f "$IMAGE_FILE" ]]; then
    log "Image already exists. Checking for updates with If-Modified-Since..."
    HTTP_CODE=$(curl -sS -L -o "$IMAGE_FILE.tmp" -w '%{http_code}' \
        --time-cond "$IMAGE_FILE" \
        "$IMAGE_URL")

    if [[ "$HTTP_CODE" == "304" ]]; then
        log "Image is up to date (HTTP 304). Skipping download."
        rm -f "$IMAGE_FILE.tmp"
    elif [[ "$HTTP_CODE" == "200" ]]; then
        mv "$IMAGE_FILE.tmp" "$IMAGE_FILE"
        log "Updated image downloaded successfully."
    else
        rm -f "$IMAGE_FILE.tmp"
        die "Download failed with HTTP status $HTTP_CODE"
    fi
else
    HTTP_CODE=$(curl -sS -L -o "$IMAGE_FILE.tmp" -w '%{http_code}' \
        --progress-bar \
        "$IMAGE_URL")

    if [[ "$HTTP_CODE" == "200" ]]; then
        mv "$IMAGE_FILE.tmp" "$IMAGE_FILE"
        log "Image downloaded successfully."
    else
        rm -f "$IMAGE_FILE.tmp"
        die "Download failed with HTTP status $HTTP_CODE"
    fi
fi

log "Image file size: $(du -h "$IMAGE_FILE" | cut -f1)"
echo "$IMAGE_FILE"
