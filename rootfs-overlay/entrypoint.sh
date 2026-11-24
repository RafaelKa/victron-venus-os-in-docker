#!/bin/sh
# entrypoint.sh — Venus OS Docker container entrypoint.
#
# Initializes the container environment and starts Venus OS services
# under daemontools (svscan) supervision.
#
# Environment variables:
#   VENUS_DISABLE_GUI=1       — Disable the Qt6 GUI service
#   VENUS_DISABLE_MQTT=1      — Disable MQTT broker and bridge
#   VENUS_DISABLE_NGINX=1     — Disable the web server
#   VENUS_DISABLE_SSH=1       — Disable SSH server
#   VENUS_DEVICES=...         — Comma-separated serial device mappings
#
# Example:
#   VENUS_DEVICES=/dev/ttyUSB0:mkx,/dev/ttyUSB1:vedirect
#
# Supported device services:
#   mkx                MK3-USB interface
#   vedirect           Victron VE.Direct USB cable
#   vedirect:default   Generic FT232EX VE.Direct interface
#
# Bluetooth is auto-detected: if an HCI adapter is available inside the
# container (passed via devices: in docker-compose.yml), Bluetooth services
# are enabled automatically. No environment variable needed.
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -e

echo "┌────────────────────────────────────────────────────────┐"
echo "│  Venus OS in Docker                                    │"
echo "│  github.com/RafaelKa/victron-venus-os-in-docker        │"
echo "└────────────────────────────────────────────────────────┘"

# ── Initialize /data volume ────────────────────────────────────────────────────
# /data is a Docker volume. On first run, set up the expected directory structure.

if [ ! -f /data/.initialized ]; then
    echo "[entrypoint] Initializing /data volume (first run)..."
    mkdir -p /data/conf
    mkdir -p /data/log
    mkdir -p /data/db
    mkdir -p /data/var/lib
    mkdir -p /data/venus
    touch /data/.initialized
    echo "[entrypoint] /data volume initialized."
fi

# ── Generate VRM unique identifier ─────────────────────────────────────────────
# FlashMQ's D-Bus auth plugin requires /data/venus/unique-id to start.
# On real hardware, venus-platform creates this. In Docker, we generate it
# from the container's MAC address (same approach as venus-platform).
#
# We regenerate on every boot (not just first run) because the MAC-based ID
# must match what Venus OS reports as system Serial. A stale fallback value
# causes portal ID mismatches in the GUI v2.

mkdir -p /data/venus
UNIQUE_ID=$(ip link show 2>/dev/null | grep -A1 -E "^[0-9]+:" | grep "link/ether" | head -n 1 | awk '{print $2}' | tr -d ':')
if [ -n "$UNIQUE_ID" ]; then
    echo "$UNIQUE_ID" > /data/venus/unique-id
    echo "[entrypoint] VRM unique ID: $UNIQUE_ID"
else
    # MAC not available — keep existing file or write fallback
    if [ ! -f /data/venus/unique-id ]; then
        read -r machine_id < /etc/machine-id && echo "${machine_id:0:12}" > /data/venus/unique-id 2>/dev/null || echo "dockervenus0" > /data/venus/unique-id
        echo "[entrypoint] VRM unique ID: fallback (no MAC detected)"
    else
        echo "[entrypoint] VRM unique ID: $(cat /data/venus/unique-id) (kept existing, no MAC detected)"
    fi
fi

# ── Populate volatile directories ──────────────────────────────────────────────
# Venus OS normally runs populate-volatile.sh at boot to create directories
# under /var/volatile/ (log dirs, tmp dirs, etc.). These are needed by
# daemontools-supervised services for their multilog instances.

if [ -x /etc/init.d/populate-volatile.sh ]; then
    echo "[entrypoint] Populating volatile directories..."
    /etc/init.d/populate-volatile.sh start 2>/dev/null || true
fi

# ── Start D-Bus ────────────────────────────────────────────────────────────────
# D-Bus is the central message bus for all Venus services.
# It is NOT managed by daemontools — it must be running before svscan starts.

echo "[entrypoint] Starting D-Bus system bus..."
mkdir -p /var/run/dbus
mkdir -p /var/lib/dbus

# Generate machine-id if missing
if [ ! -f /var/lib/dbus/machine-id ] && [ ! -f /etc/machine-id ]; then
    dbus-uuidgen > /var/lib/dbus/machine-id
    cp /var/lib/dbus/machine-id /etc/machine-id
fi

# Remove stale PID file
rm -f /var/run/messagebus.pid

# Start dbus-daemon
dbus-daemon --system --nopidfile &
DBUS_PID=$!

# Wait for the socket to appear
DBUS_TIMEOUT=10
DBUS_WAITED=0
while [ ! -S /var/run/dbus/system_bus_socket ] && [ "$DBUS_WAITED" -lt "$DBUS_TIMEOUT" ]; do
    sleep 0.2
    DBUS_WAITED=$((DBUS_WAITED + 1))
done

if [ ! -S /var/run/dbus/system_bus_socket ]; then
    echo "[entrypoint] ERROR: D-Bus socket did not appear within ${DBUS_TIMEOUT}s"
    exit 1
fi
echo "[entrypoint] D-Bus is running (PID: $DBUS_PID)."

# ── Start PHP-FPM ─────────────────────────────────────────────────────────────
# PHP-FPM is needed by nginx for the web GUI authentication and routing.
# It is managed by init.d, not daemontools.

if [ -x /etc/init.d/php-fpm ]; then
    echo "[entrypoint] Starting PHP-FPM..."
    /etc/init.d/php-fpm start 2>/dev/null || true
fi

# ── Set up /service directory ──────────────────────────────────────────────────
# Replicate the logic from Venus OS overlays.sh:
# Copy service definitions from /opt/victronenergy/service to a writable location,
# then bind-mount to /service for svscan.

echo "[entrypoint] Setting up service directory..."
mkdir -p /run/overlays/service

if [ -d /opt/victronenergy/service ]; then
    cp -a /opt/victronenergy/service/* /run/overlays/service/ 2>/dev/null || true
fi

# Mount to /service (where svscan expects them)
mount --bind /run/overlays/service /service 2>/dev/null || {
    # If mount fails (e.g., no mount privileges), use symlink fallback
    rm -rf /service
    ln -sf /run/overlays/service /service
}

# ── Disable/enable services based on environment ──────────────────────────────

disable_service() {
    if [ -d "/service/$1" ]; then
        touch "/service/$1/down"
        echo "[entrypoint]   Disabled: $1"
    fi
}

enable_service() {
    if [ -d "/service/$1" ]; then
        rm -f "/service/$1/down"
        echo "[entrypoint]   Enabled: $1"
    fi
}

# GUI services
if [ "${VENUS_DISABLE_GUI:-0}" = "1" ]; then
    echo "[entrypoint] Disabling GUI services..."
    disable_service "start-gui"
    disable_service "start-gui-v2"
    disable_service "gui-v2"
fi

# MQTT
if [ "${VENUS_DISABLE_MQTT:-0}" = "1" ]; then
    echo "[entrypoint] Disabling MQTT services..."
    disable_service "flashmq"
    disable_service "dbus-mqtt"
fi

# Web server
if [ "${VENUS_DISABLE_NGINX:-0}" = "1" ]; then
    echo "[entrypoint] Disabling nginx..."
    disable_service "nginx"
fi

# SSH
if [ "${VENUS_DISABLE_SSH:-0}" = "1" ]; then
    echo "[entrypoint] Disabling SSH..."
    disable_service "openssh"
    disable_service "sshd"
fi

# Connman — always disabled (Docker manages networking)

# ── Bluetooth auto-detection ─────────────────────────────────────────────────
# If a Bluetooth HCI adapter is available inside the container, enable
# Bluetooth services automatically. No environment variable needed.

BT_DETECTED=false
for hci in /sys/class/bluetooth/hci*; do
    if [ -e "$hci" ]; then
        BT_DETECTED=true
        break
    fi
done

if [ "$BT_DETECTED" = true ]; then
    echo "[entrypoint] Bluetooth adapter detected — enabling BT services..."
    enable_service "start-bluetooth"
    enable_service "bluetooth"
    enable_service "vesmart-server"
    enable_service "dbus-ble-sensors"
else
    echo "[entrypoint] No Bluetooth adapter detected — BT services stay disabled."
fi

# ── Set up Venus serial devices ──────────────────────────────────────────────
#
# Venus OS normally relies on udev rules to:
#
#   1. Add ID_BUS, ID_MODEL and VE_SERVICE properties.
#   2. Create /dev/serial-starter/<device> symlinks.
#
# udevd is not running inside the container, so reproduce those two effects
# from the VENUS_DEVICES environment variable.
#
# Example:
#
#   VENUS_DEVICES=/dev/ttyUSB0:mkx,/dev/ttyUSB1:vedirect
#

setup_venus_device() {
    dev=$1
    requested_service=$2

    # Remove whitespace around values.
    dev=$(printf '%s' "$dev" | tr -d '[:space:]')
    requested_service=$(printf '%s' "$requested_service" | tr -d '[:space:]')

    if [ -z "$dev" ] || [ -z "$requested_service" ]; then
        echo "[entrypoint] WARNING: Invalid VENUS_DEVICES entry"
        return 0
    fi

    if [ ! -c "$dev" ]; then
        echo "[entrypoint] WARNING: $dev does not exist or is not a character device"
        return 0
    fi

    case "$requested_service" in
        mkx)
            id_model="MK3-USB_Interface"
            ve_service="mkx"
            ;;

        vedirect)
            id_model="VE_Direct_cable"
            ve_service="vedirect"
            ;;

        vedirect:default)
            id_model="FT232EX"
            ve_service="vedirect:default"
            ;;

        *)
            echo "[entrypoint] WARNING: Unsupported Venus service '$requested_service' for $dev"
            return 0
            ;;
    esac

    device_name=$(basename "$dev")

    # GNU stat returns decimal major and minor device numbers with these
    # format specifiers. For ttyUSB0 this normally produces 188 and 0.
    major=$(udevadm info -q property -n "$dev" | sed -n 's/^MAJOR=//p')
    minor=$(udevadm info -q property -n "$dev" | sed -n 's/^MINOR=//p')

    if [ -z "$major" ] || [ -z "$minor" ]; then
        echo "[entrypoint] WARNING: Cannot determine major/minor numbers for $dev"
        return 0
    fi

    udev_database="/run/udev/data/c${major}:${minor}"
    serial_link="/dev/serial-starter/$device_name"

    mkdir -p /run/udev/data
    mkdir -p /dev/serial-starter

    # Populate the properties used by serial-starter.
    #
    # DEVNAME, DEVPATH, MAJOR, MINOR and SUBSYSTEM are obtained directly
    # from sysfs by udevadm and do not need to be added here.
    cat > "$udev_database" <<EOF
E:ID_BUS=usb
E:ID_MODEL=$id_model
E:VE_SERVICE=$ve_service
EOF

    # Reproduce:
    #
    #   SYMLINK+="serial-starter/%k"
    #
    # Use a relative target, matching normal /dev symlink conventions.
    ln -sfn "../$device_name" "$serial_link"

    echo "[entrypoint] Venus serial device configured:"
    echo "[entrypoint]   Device:  $dev"
    echo "[entrypoint]   Link:    $serial_link -> ../$device_name"
    echo "[entrypoint]   Model:   $id_model"
    echo "[entrypoint]   Service: $ve_service"
    echo "[entrypoint]   udev DB: $udev_database"
}

setup_venus_devices() {
    if [ -z "${VENUS_DEVICES:-}" ]; then
        echo "[entrypoint] No Venus serial devices configured."
        return 0
    fi

    venus_devices=$VENUS_DEVICES

    # Be tolerant of values accidentally configured with literal quotes:
    #
    #   VENUS_DEVICES="/dev/ttyUSB0:vedirect"
    #
    # The Compose configuration should ideally omit those literal quotes.
    venus_devices=$(printf '%s' "$venus_devices" | sed 's/^"//;s/"$//')

    echo "[entrypoint] Setting up Venus serial devices..."

    old_ifs=$IFS
    IFS=','

    for mapping in $venus_devices; do
        dev=${mapping%%:*}
        requested_service=${mapping#*:}

        if [ "$dev" = "$mapping" ]; then
            echo "[entrypoint] WARNING: Invalid VENUS_DEVICES entry '$mapping'"
            continue
        fi

        setup_venus_device "$dev" "$requested_service"
    done

    IFS=$old_ifs
}

setup_venus_devices

# ── Show service summary ──────────────────────────────────────────────────────

TOTAL_SERVICES=$(find /service -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
DISABLED_SERVICES=$(find /service -maxdepth 2 -name "down" 2>/dev/null | wc -l)
ENABLED_SERVICES=$((TOTAL_SERVICES - DISABLED_SERVICES))

echo "[entrypoint] Services: $ENABLED_SERVICES enabled, $DISABLED_SERVICES disabled (${TOTAL_SERVICES} total)"

# ── Start svscan ──────────────────────────────────────────────────────────────
# svscan is the daemontools service supervisor. It scans /service for
# subdirectories and starts/supervises a process for each one.
# exec replaces this shell — svscan becomes PID 1.

echo "[entrypoint] Starting svscan (daemontools supervisor)..."
echo "[entrypoint] Venus OS is starting up. This may take a moment."
exec svscan /service
