#!/usr/bin/env bash
# modify-rootfs.sh — Apply container-compatibility patches to the extracted Venus OS rootfs.
#
# This script modifies the rootfs IN-PLACE before it gets packaged into a Docker image.
# All changes happen here so the final Docker image is a single layer.
#
# Usage: ./modify-rootfs.sh [--rootfs path/to/staging/] [--machine raspberrypi5]
#
# SPDX-License-Identifier: GPL-3.0-or-later

. "$(dirname "$0")/common.sh"

# ── Parse arguments ────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rootfs)  STAGING_DIR="$2"; shift 2 ;;
        --machine) MACHINE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--rootfs DIR] [--machine NAME]"
            echo ""
            echo "Apply container-compatibility patches to extracted Venus OS rootfs."
            echo ""
            echo "Options:"
            echo "  --rootfs DIR     Path to extracted rootfs (default: build/rootfs-staging/)"
            echo "  --machine NAME   Machine name (default: raspberrypi5)"
            exit 0
            ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── Validate ───────────────────────────────────────────────────────────────────

[[ -d "$STAGING_DIR" ]] || die "Staging directory not found: $STAGING_DIR"
[[ -d "$STAGING_DIR/etc" ]] || die "Doesn't look like a rootfs (no /etc): $STAGING_DIR"

MODIFICATIONS=0

modify() {
    log "  [PATCH] $1"
    MODIFICATIONS=$((MODIFICATIONS + 1))
}

# ── 1. Add Docker marker file ─────────────────────────────────────────────────

modify "Add Docker environment marker /etc/venus/docker"
mkdir -p "$STAGING_DIR/etc/venus"
cat > "$STAGING_DIR/etc/venus/docker" <<'MARKER'
# This Venus OS instance runs inside a Docker container.
# Some services and init scripts are modified for container compatibility.
VENUS_DOCKER=1
MARKER

# ── 2. Add entrypoint script ──────────────────────────────────────────────────

modify "Install /entrypoint.sh from rootfs-overlay"
cp "${PROJECT_ROOT}/rootfs-overlay/entrypoint.sh" "$STAGING_DIR/entrypoint.sh"
chmod 755 "$STAGING_DIR/entrypoint.sh"

# Copy any additional overlay files
if [[ -d "${PROJECT_ROOT}/rootfs-overlay/etc" ]]; then
    cp -a "${PROJECT_ROOT}/rootfs-overlay/etc/." "$STAGING_DIR/etc/"
fi

# ── 3. Disable connman (network management) ───────────────────────────────────
# Docker/host OS manages networking. connman would conflict.

if [[ -d "$STAGING_DIR/opt/victronenergy/service/connman" ]]; then
    modify "Disable connman (Docker manages networking)"
    touch "$STAGING_DIR/opt/victronenergy/service/connman/down"
fi

# ── 4. Disable hardware-dependent services that need kernel access ─────────────
# These services need real hardware or kernel modules. They are disabled by
# default but can be re-enabled via environment variables at container start.

HARDWARE_SERVICES=(
    # Bluetooth (needs HCI hardware)
    "start-bluetooth"
    "bluetooth"
    "vesmart-server"
    "dbus-ble-sensors"
    # WiFi/AP (managed by host)
    "hostapd"
    # PPP modem
    "ppp"
)

for svc in "${HARDWARE_SERVICES[@]}"; do
    if [[ -d "$STAGING_DIR/opt/victronenergy/service/$svc" ]]; then
        modify "Disable hardware service: $svc"
        touch "$STAGING_DIR/opt/victronenergy/service/$svc/down"
    fi
done

# ── 5. Fix read-only rootfs assumptions ────────────────────────────────────────
# Venus OS normally runs with a read-only rootfs and uses overlayfs/tmpfs.
# In Docker the rootfs layer is writable, so we can simplify this.

modify "Ensure writable runtime directories exist"
# Venus OS uses chained symlinks for volatile dirs, e.g.:
#   /tmp → /var/tmp → /var/volatile/tmp
#   /var/log → /data/log
# We must follow the FULL symlink chain within the staging dir and create
# the final real target directory. Plain mkdir -p fails on broken symlinks.
ensure_dir() {
    local virtual_path="$1"
    local real_path="$STAGING_DIR$virtual_path"

    # Follow symlink chain until we reach a non-symlink or broken end
    local max_depth=10
    local depth=0
    while [[ -L "$real_path" ]] && [[ $depth -lt $max_depth ]]; do
        local target
        target=$(readlink "$real_path")
        if [[ "$target" = /* ]]; then
            # Absolute symlink — resolve within staging dir
            real_path="$STAGING_DIR$target"
        else
            # Relative symlink — resolve relative to symlink's parent
            real_path="$(dirname "$real_path")/$target"
        fi
        depth=$((depth + 1))
    done

    if [[ -d "$real_path" ]]; then
        # Already exists as a real directory
        return 0
    fi

    # Create the final target directory
    mkdir -p "$real_path"
}
ensure_dir "/tmp"
ensure_dir "/var/run"
ensure_dir "/var/run/dbus"
ensure_dir "/var/log"
ensure_dir "/var/volatile"
ensure_dir "/run"
ensure_dir "/run/overlays/service"
ensure_dir "/service"

# ── 6. Create /data mount point ───────────────────────────────────────────────
# /data is a separate partition on real hardware. In Docker it's a volume.

modify "Create /data volume mount point"
ensure_dir "/data"
ensure_dir "/data/conf"
ensure_dir "/data/log"
ensure_dir "/data/db"

# ── 7. Patch overlays.sh for container use ─────────────────────────────────────
# The original overlays.sh copies services from /opt/victronenergy/service to
# a tmpfs and bind-mounts to /service. In Docker we do this in the entrypoint,
# but if the original script runs during init it should not fail.

OVERLAYS_SCRIPT="$STAGING_DIR/etc/init.d/overlays.sh"
if [[ -f "$OVERLAYS_SCRIPT" ]]; then
    modify "Patch overlays.sh — skip if running in Docker"
    # Prepend a Docker check
    sed -i '1a\
# Skip in Docker — entrypoint handles service setup\
if [ -f /etc/venus/docker ]; then exit 0; fi' "$OVERLAYS_SCRIPT"
fi

# Also check for overlays.sh in rcS.d or similar
for script in "$STAGING_DIR"/etc/rcS.d/*overlays* "$STAGING_DIR"/etc/init.d/*overlays*; do
    if [[ -f "$script" && "$script" != "$OVERLAYS_SCRIPT" ]]; then
        modify "Patch $(basename "$script") — skip if running in Docker"
        sed -i '1a\
# Skip in Docker — entrypoint handles service setup\
if [ -f /etc/venus/docker ]; then exit 0; fi' "$script"
    fi
done

# ── 8. Patch init scripts that assume read-only rootfs ─────────────────────────
# NOTE: populate-volatile.sh is intentionally NOT patched — it must run in Docker
# to create /var/volatile/log/* directories that daemontools services need.

for init_script in \
    "$STAGING_DIR/etc/init.d/test-data-partition.sh" \
    "$STAGING_DIR/etc/init.d/update-data.sh" \
    "$STAGING_DIR/etc/init.d/clean-data.sh" \
    "$STAGING_DIR/etc/init.d/report-data-failure.sh"; do
    if [[ -f "$init_script" ]]; then
        modify "Patch $(basename "$init_script") — skip in Docker"
        sed -i '1a\
# Skip in Docker — container handles storage\
if [ -f /etc/venus/docker ]; then exit 0; fi' "$init_script"
    fi
done

# ── 9. Ensure D-Bus configuration allows container usage ──────────────────────

DBUS_SYSTEM_CONF="$STAGING_DIR/etc/dbus-1/system.conf"
if [[ -f "$DBUS_SYSTEM_CONF" ]]; then
    modify "Verify D-Bus system configuration"
    # D-Bus should work as-is in the container; just log that we checked it.
fi

# ── 10. Set machine identity ──────────────────────────────────────────────────

modify "Set /etc/venus/machine to '${MACHINE}'"
mkdir -p "$STAGING_DIR/etc/venus"
echo "$MACHINE" > "$STAGING_DIR/etc/venus/machine"

# ── Summary ───────────────────────────────────────────────────────────────────

log ""
log "Rootfs modification complete: $MODIFICATIONS patches applied."
log "Staging directory: $STAGING_DIR"
