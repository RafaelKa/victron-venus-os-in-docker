#!/usr/bin/env bash
# install.sh — Interactive installer wizard for Venus OS in Docker.
#
# Creates a ready-to-run deployment directory with:
#   - docker-compose.yml (bridge network, explicit devices, bind-mounted data)
#   - .env (persisted config for re-running the wizard)
#   - venus-os-data/ (persistent Venus OS data directory)
#
# Idempotent: re-running in an existing directory pre-fills from .env.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/RafaelKa/victron-venus-os-in-docker/main/install.sh | bash
#   # or
#   bash install.sh
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────

readonly DEFAULT_IMAGE="ghcr.io/rafaelka/venus-os:latest-raspberrypi5"
readonly DEFAULT_PORT_HTTP=80
readonly DEFAULT_PORT_HTTPS=443
readonly DEFAULT_PORT_MQTT=1883
readonly DEFAULT_PORT_MQTT_WS=9001
readonly DEFAULT_PORT_SSH=2222

# Known Victron-related USB vendor IDs
readonly VID_FTDI="0403"
readonly VID_VICTRON="1546"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' RESET=''
fi

info()  { printf "${GREEN}[✓]${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${RESET} %s\n" "$*"; }
error() { printf "${RED}[✗]${RESET} %s\n" "$*" >&2; }
die()   { error "$@"; exit 1; }
header() { printf "\n${BOLD}${CYAN}── %s ──${RESET}\n\n" "$*"; }

ask() {
    local prompt="$1" default="${2:-}"
    if [ -n "$default" ]; then
        printf "${BOLD}%s${RESET} [${DIM}%s${RESET}]: " "$prompt" "$default"
    else
        printf "${BOLD}%s${RESET}: " "$prompt"
    fi
    read -r REPLY
    REPLY="${REPLY:-$default}"
}

ask_yn() {
    local prompt="$1" default="${2:-y}"
    local hint
    if [ "$default" = "y" ]; then hint="Y/n"; else hint="y/N"; fi
    printf "${BOLD}%s${RESET} [%s]: " "$prompt" "$hint"
    read -r REPLY
    REPLY="${REPLY:-$default}"
    case "$REPLY" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Prerequisites ────────────────────────────────────────────────────────────

check_prerequisites() {
    header "Prerequisites"

    local ok=true

    # Docker
    if command -v docker &>/dev/null; then
        local docker_version
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        info "Docker $docker_version"
    else
        error "Docker is not installed. See https://docs.docker.com/engine/install/"
        ok=false
    fi

    # Docker Compose v2
    if docker compose version &>/dev/null; then
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        info "Docker Compose $compose_version"
    else
        error "Docker Compose v2 is not available. Install the docker-compose-plugin."
        ok=false
    fi

    if [ "$ok" = false ]; then
        die "Missing prerequisites. Install them and re-run the installer."
    fi
}

# ── Load existing .env ───────────────────────────────────────────────────────

load_existing_env() {
    local env_file="$1"
    if [ -f "$env_file" ]; then
        warn "Found existing configuration at $env_file — pre-filling values."
        # Source the env file safely (only known variables)
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
            # Strip quotes from value
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            case "$key" in
                VENUS_INSTANCE_NAME)  ENV_INSTANCE_NAME="$value" ;;
                VENUS_IMAGE)          ENV_IMAGE="$value" ;;
                VENUS_PORT_HTTP)      ENV_PORT_HTTP="$value" ;;
                VENUS_PORT_HTTPS)     ENV_PORT_HTTPS="$value" ;;
                VENUS_PORT_MQTT)      ENV_PORT_MQTT="$value" ;;
                VENUS_PORT_MQTT_WS)   ENV_PORT_MQTT_WS="$value" ;;
                VENUS_PORT_SSH)       ENV_PORT_SSH="$value" ;;
                VENUS_BLUETOOTH)      ENV_BLUETOOTH="$value" ;;
                VENUS_BT_DEVICE)      ENV_BT_DEVICE="$value" ;;
                VENUS_DEVICES)        ENV_DEVICES="$value" ;;
                VENUS_EXPOSE_HTTP)    ENV_EXPOSE_HTTP="$value" ;;
            esac
        done < "$env_file"
        return 0
    fi
    return 1
}

# ── Instance name ────────────────────────────────────────────────────────────

configure_instance_name() {
    header "Instance Name"

    echo "Choose a name for this Venus OS instance."
    echo "This is used as the container name and directory name."
    echo "Use lowercase letters, numbers, and hyphens (e.g., boat-main, shore-monitor)."
    echo ""

    local default="${ENV_INSTANCE_NAME:-venus-os}"
    while true; do
        ask "Instance name" "$default"
        INSTANCE_NAME="$REPLY"
        if [[ "$INSTANCE_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] || [[ "$INSTANCE_NAME" =~ ^[a-z0-9]$ ]]; then
            break
        fi
        warn "Invalid name. Use lowercase letters, numbers, and hyphens (must start/end with alphanumeric)."
    done

    info "Instance name: $INSTANCE_NAME"
}

# ── Install directory ────────────────────────────────────────────────────────

configure_install_dir() {
    header "Install Directory"

    INSTALL_DIR="$(pwd)/$INSTANCE_NAME"

    echo "The installer will create (or update) the directory:"
    printf "  ${BOLD}%s${RESET}\n" "$INSTALL_DIR"
    echo ""

    if [ -d "$INSTALL_DIR" ]; then
        if [ -f "$INSTALL_DIR/.env" ]; then
            info "Existing installation detected — will reconfigure."
            load_existing_env "$INSTALL_DIR/.env" || true
        else
            warn "Directory exists but has no .env — will initialize."
        fi
    fi

    if ! ask_yn "Continue with this directory?" "y"; then
        ask "Enter a different path" "$INSTALL_DIR"
        INSTALL_DIR="$REPLY"
    fi

    mkdir -p "$INSTALL_DIR"
    info "Install directory: $INSTALL_DIR"
}

# ── Docker image ─────────────────────────────────────────────────────────────

configure_image() {
    header "Docker Image"

    local default="${ENV_IMAGE:-$DEFAULT_IMAGE}"
    ask "Docker image" "$default"
    DOCKER_IMAGE="$REPLY"

    if ask_yn "Pull the image now?" "y"; then
        echo ""
        if docker pull "$DOCKER_IMAGE"; then
            info "Image pulled successfully."
        else
            warn "Pull failed. You can pull it later with: docker pull $DOCKER_IMAGE"
        fi
    fi

    info "Image: $DOCKER_IMAGE"
}

# ── Serial device helpers ────────────────────────────────────────────────────

# Get the USB vendor ID for a /dev/serial/by-id/ symlink
get_vendor_id() {
    local dev_link="$1"
    local real_dev
    real_dev=$(readlink -f "$dev_link")
    local dev_name
    dev_name=$(basename "$real_dev")

    # Walk sysfs to find idVendor
    local sysfs_path="/sys/class/tty/$dev_name/device"
    if [ -d "$sysfs_path" ]; then
        # Go up to the USB device level
        local usb_dev="$sysfs_path"
        while [ -n "$usb_dev" ] && [ "$usb_dev" != "/" ]; do
            if [ -f "$usb_dev/idVendor" ]; then
                cat "$usb_dev/idVendor"
                return
            fi
            usb_dev=$(dirname "$usb_dev")
        done
    fi
    echo "unknown"
}

# Suggest a friendly container device name based on the serial-by-id name
suggest_device_name() {
    local by_id_name="$1"

    # Extract useful parts from the by-id name
    # Typical format: usb-Victron_Energy_BV_MK3-USB_Interface_HQ2132XXXXX-if00-port0
    #            or:  usb-FTDI_FT232R_USB_UART_A10KXXXX-if00-port0

    local name="$by_id_name"

    # Remove "usb-" prefix
    name="${name#usb-}"

    # Try to extract the device type for Victron devices
    if [[ "$name" =~ MK3-USB ]]; then
        echo "/dev/ttyUSBMK3"
        return
    elif [[ "$name" =~ VE_Direct ]]; then
        echo "/dev/ttyUSBVEDirect"
        return
    elif [[ "$name" =~ (MPPT|SmartSolar|BlueSolar) ]]; then
        echo "/dev/ttyUSBMPPT"
        return
    elif [[ "$name" =~ (BMV|SmartShunt) ]]; then
        echo "/dev/ttyUSBBMV"
        return
    elif [[ "$name" =~ (Skylla|Phoenix|MultiPlus|Quattro|EasySolar) ]]; then
        echo "/dev/ttyUSBCharger"
        return
    fi

    # Fallback: use a shortened version
    # Take first two meaningful parts
    local short
    short=$(echo "$name" | cut -d'_' -f1-2 | tr -cd '[:alnum:]')
    echo "/dev/ttyUSB${short}"
}

# ── Serial device selection ──────────────────────────────────────────────────

configure_devices() {
    header "Serial Devices"

    SELECTED_DEVICES=()

    if [ ! -d /dev/serial/by-id ] || [ -z "$(ls -A /dev/serial/by-id/ 2>/dev/null)" ]; then
        warn "No serial devices found in /dev/serial/by-id/"
        echo "You can add devices later by editing docker-compose.yml."
        echo ""

        # Check for pre-existing devices from .env
        if [ -n "${ENV_DEVICES:-}" ]; then
            warn "Previous configuration had devices: $ENV_DEVICES"
            if ask_yn "Keep previous device configuration?" "y"; then
                IFS=',' read -ra SELECTED_DEVICES <<< "$ENV_DEVICES"
            fi
        fi
        return
    fi

    echo "The following serial devices were found on this host:"
    echo ""

    local devices=()
    local i=0
    for dev_link in /dev/serial/by-id/*; do
        [ -e "$dev_link" ] || continue
        devices+=("$dev_link")

        local by_id_name
        by_id_name=$(basename "$dev_link")
        local real_dev
        real_dev=$(readlink -f "$dev_link")
        local vid
        vid=$(get_vendor_id "$dev_link")

        local marker=""
        if [ "$vid" = "$VID_VICTRON" ] || [ "$vid" = "$VID_FTDI" ]; then
            marker="${GREEN} ← Victron/FTDI${RESET}"
        fi

        i=$((i + 1))
        printf "  ${BOLD}%d)${RESET} %s\n" "$i" "$by_id_name"
        printf "     → %s (vendor: %s)%b\n" "$real_dev" "$vid" "$marker"
    done

    echo ""
    echo "Enter device numbers to include, separated by spaces (e.g., 1 3)."
    echo "Press Enter to skip (no devices)."
    ask "Devices" ""

    if [ -z "$REPLY" ]; then
        info "No devices selected."
        return
    fi

    local selected_nums
    read -ra selected_nums <<< "$REPLY"

    for num in "${selected_nums[@]}"; do
        if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#devices[@]}" ]; then
            warn "Skipping invalid selection: $num"
            continue
        fi

        local dev_link="${devices[$((num - 1))]}"
        local by_id_name
        by_id_name=$(basename "$dev_link")
        local real_dev
        real_dev=$(readlink -f "$dev_link")
        local suggested
        suggested=$(suggest_device_name "$by_id_name")

        echo ""
        printf "  Device: ${BOLD}%s${RESET}\n" "$by_id_name"
        printf "  Resolves to: %s\n" "$real_dev"
        echo ""
        echo "  Choose a container device name. This is how Venus OS will see the device."
        echo "  Use a descriptive name like /dev/ttyUSBMK3, /dev/ttyUSBMPPT, etc."
        ask "  Container name" "$suggested"
        local container_name="$REPLY"

        # Ensure it starts with /dev/
        if [[ ! "$container_name" =~ ^/dev/ ]]; then
            container_name="/dev/$container_name"
        fi

        # Store as: host_by_id_path:container_name
        SELECTED_DEVICES+=("${dev_link}:${container_name}")
        info "Mapped: $by_id_name → $container_name (host: $real_dev)"
    done
}

# ── Bluetooth ────────────────────────────────────────────────────────────────

configure_bluetooth() {
    header "Bluetooth"

    BLUETOOTH_ENABLED="false"
    BT_DEVICE=""

    local bt_adapters=()
    if [ -d /sys/class/bluetooth ]; then
        for adapter in /sys/class/bluetooth/hci*; do
            [ -e "$adapter" ] || continue
            bt_adapters+=("$(basename "$adapter")")
        done
    fi

    if [ ${#bt_adapters[@]} -eq 0 ]; then
        info "No Bluetooth adapters detected."
        echo "Bluetooth will be auto-detected at container startup if an adapter"
        echo "is passed through later."
        return
    fi

    echo "Bluetooth adapter(s) detected:"
    for adapter in "${bt_adapters[@]}"; do
        local addr=""
        if [ -f "/sys/class/bluetooth/$adapter/address" ]; then
            addr=$(cat "/sys/class/bluetooth/$adapter/address")
        fi
        printf "  ${BOLD}%s${RESET}" "$adapter"
        [ -n "$addr" ] && printf " (%s)" "$addr"
        echo ""
    done
    echo ""

    local default_bt="${ENV_BLUETOOTH:-y}"
    if ask_yn "Enable Bluetooth in the container?" "$default_bt"; then
        BLUETOOTH_ENABLED="true"
        BT_DEVICE="${ENV_BT_DEVICE:-/dev/${bt_adapters[0]}}"

        if [ ${#bt_adapters[@]} -gt 1 ]; then
            ask "Which adapter to pass through?" "${bt_adapters[0]}"
            BT_DEVICE="/dev/$REPLY"
        fi

        info "Bluetooth enabled: $BT_DEVICE"
    else
        info "Bluetooth disabled."
    fi
}

# ── Port configuration ───────────────────────────────────────────────────────

check_port() {
    local port="$1"
    if command -v ss &>/dev/null; then
        if ss -tlnH "sport = :$port" 2>/dev/null | grep -q .; then
            return 1  # in use
        fi
    elif [ -f /proc/net/tcp ]; then
        local hex_port
        hex_port=$(printf '%04X' "$port")
        if grep -qi ":${hex_port} " /proc/net/tcp 2>/dev/null; then
            return 1  # in use
        fi
    fi
    return 0  # available
}

configure_ports() {
    header "Port Mapping"

    echo "Configure the host ports that map to Venus OS services."
    echo "The wizard will warn about ports already in use."
    echo ""

    # Ask whether to expose HTTP/HTTPS
    echo "If Venus OS runs behind a reverse proxy, you may not need to expose"
    echo "HTTP/HTTPS ports directly to the host."
    echo ""

    local default_expose_http="${ENV_EXPOSE_HTTP:-y}"
    if ask_yn "Expose HTTP/HTTPS ports to the host?" "$default_expose_http"; then
        EXPOSE_HTTP="true"
    else
        EXPOSE_HTTP="false"
        info "HTTP/HTTPS ports will not be exposed. Access the web GUI via your reverse proxy."
    fi

    PORT_HTTP="" PORT_HTTPS=""

    local ports=()
    if [ "$EXPOSE_HTTP" = "true" ]; then
        ports+=("HTTP:80:${ENV_PORT_HTTP:-$DEFAULT_PORT_HTTP}")
        ports+=("HTTPS:443:${ENV_PORT_HTTPS:-$DEFAULT_PORT_HTTPS}")
    fi
    ports+=("MQTT:1883:${ENV_PORT_MQTT:-$DEFAULT_PORT_MQTT}")
    ports+=("MQTT_WS:9001:${ENV_PORT_MQTT_WS:-$DEFAULT_PORT_MQTT_WS}")
    ports+=("SSH:22:${ENV_PORT_SSH:-$DEFAULT_PORT_SSH}")

    echo ""
    for entry in "${ports[@]}"; do
        IFS=':' read -r label container_port default_host_port <<< "$entry"

        local conflict_msg=""
        if ! check_port "$default_host_port"; then
            conflict_msg="${YELLOW} (port $default_host_port is in use!)${RESET}"
        fi

        printf "  %s (container :%s)%b\n" "$label" "$container_port" "$conflict_msg"
        ask "  Host port" "$default_host_port"
        local chosen="$REPLY"

        # Warn if chosen port is also in use
        if [ "$chosen" != "$default_host_port" ] && ! check_port "$chosen"; then
            warn "Port $chosen is also in use. Continuing anyway."
        fi

        case "$label" in
            HTTP)    PORT_HTTP="$chosen" ;;
            HTTPS)   PORT_HTTPS="$chosen" ;;
            MQTT)    PORT_MQTT="$chosen" ;;
            MQTT_WS) PORT_MQTT_WS="$chosen" ;;
            SSH)     PORT_SSH="$chosen" ;;
        esac
    done

    echo ""
    local port_summary="MQTT=$PORT_MQTT, MQTT_WS=$PORT_MQTT_WS, SSH=$PORT_SSH"
    if [ "$EXPOSE_HTTP" = "true" ]; then
        port_summary="HTTP=$PORT_HTTP, HTTPS=$PORT_HTTPS, $port_summary"
    fi
    info "Ports configured: $port_summary"
}

# ── Summary ──────────────────────────────────────────────────────────────────

show_summary() {
    header "Configuration Summary"

    printf "  ${BOLD}Instance name:${RESET}  %s\n" "$INSTANCE_NAME"
    printf "  ${BOLD}Install dir:${RESET}    %s\n" "$INSTALL_DIR"
    printf "  ${BOLD}Docker image:${RESET}   %s\n" "$DOCKER_IMAGE"
    echo ""

    printf "  ${BOLD}Ports:${RESET}\n"
    if [ "$EXPOSE_HTTP" = "true" ]; then
        printf "    HTTP:     %s → 80\n" "$PORT_HTTP"
        printf "    HTTPS:    %s → 443\n" "$PORT_HTTPS"
    else
        printf "    HTTP:     ${DIM}not exposed (reverse proxy)${RESET}\n"
        printf "    HTTPS:    ${DIM}not exposed (reverse proxy)${RESET}\n"
    fi
    printf "    MQTT:     %s → 1883\n" "$PORT_MQTT"
    printf "    MQTT WS:  %s → 9001\n" "$PORT_MQTT_WS"
    printf "    SSH:      %s → 22\n" "$PORT_SSH"
    echo ""

    printf "  ${BOLD}Devices:${RESET}\n"
    if [ ${#SELECTED_DEVICES[@]} -eq 0 ]; then
        printf "    (none)\n"
    else
        for mapping in "${SELECTED_DEVICES[@]}"; do
            local host_path="${mapping%%:*}"
            local container_path="${mapping#*:}"
            local host_name
            host_name=$(basename "$host_path")
            printf "    %s → %s\n" "$host_name" "$container_path"
        done
    fi
    echo ""

    printf "  ${BOLD}Bluetooth:${RESET}      %s\n" "$BLUETOOTH_ENABLED"
    if [ "$BLUETOOTH_ENABLED" = "true" ]; then
        printf "    Adapter:    %s\n" "$BT_DEVICE"
    fi
    echo ""

    printf "  ${BOLD}Data volume:${RESET}    %s/venus-os-data/\n" "$INSTALL_DIR"
    echo ""
}

# ── Generate docker-compose.yml ──────────────────────────────────────────────

generate_compose() {
    local compose_file="$INSTALL_DIR/docker-compose.yml"

    # Build devices section
    local devices_yaml=""
    if [ ${#SELECTED_DEVICES[@]} -gt 0 ] || [ "$BLUETOOTH_ENABLED" = "true" ]; then
        devices_yaml="    devices:"
        for mapping in "${SELECTED_DEVICES[@]}"; do
            local host_path="${mapping%%:*}"
            local container_path="${mapping#*:}"
            devices_yaml="$devices_yaml
      - ${host_path}:${container_path}"
        done
        if [ "$BLUETOOTH_ENABLED" = "true" ]; then
            devices_yaml="$devices_yaml
      - ${BT_DEVICE}:${BT_DEVICE}"
        fi
    fi

    # Generate a stable MAC address derived from instance name.
    # This ensures the container always gets the same MAC across down/up cycles,
    # which keeps the VRM unique-id (derived from MAC) stable.
    local mac_hash
    mac_hash=$(printf '%s' "$INSTANCE_NAME" | md5sum | cut -c1-10)
    # Use locally administered, unicast MAC (second nibble even + bit 1 set = x2)
    STABLE_MAC=$(printf '02:%s:%s:%s:%s:%s' \
        "${mac_hash:0:2}" "${mac_hash:2:2}" "${mac_hash:4:2}" "${mac_hash:6:2}" "${mac_hash:8:2}")

    # Build ports section
    local ports_yaml="    ports:"
    if [ "$EXPOSE_HTTP" = "true" ]; then
        ports_yaml="$ports_yaml
      - \"${PORT_HTTP}:80\"       # Web GUI (HTTP)
      - \"${PORT_HTTPS}:443\"     # Web GUI (HTTPS)"
    fi
    ports_yaml="$ports_yaml
      - \"${PORT_MQTT}:1883\"     # MQTT
      - \"${PORT_MQTT_WS}:9001\"  # MQTT WebSocket
      - \"${PORT_SSH}:22\"        # SSH"

    cat > "$compose_file" << YAML
# Venus OS in Docker — Generated by install.sh
#
# Instance: ${INSTANCE_NAME}
# Generated: $(date -Iseconds)
#
# Re-run install.sh to reconfigure. Data in venus-os-data/ is preserved.
#
# SPDX-License-Identifier: GPL-3.0-or-later

services:
  venus-os:
    image: ${DOCKER_IMAGE}
    container_name: ${INSTANCE_NAME}
    mac_address: "${STABLE_MAC}"
    privileged: true
    restart: unless-stopped
${ports_yaml}
    volumes:
      - ./venus-os-data:/data
${devices_yaml:+$devices_yaml
}    networks:
      - venus-net

networks:
  venus-net:
    name: ${INSTANCE_NAME}-net
YAML

    info "Generated $compose_file"
}

# ── Generate .env ────────────────────────────────────────────────────────────

generate_env() {
    local env_file="$INSTALL_DIR/.env"

    # Serialize device mappings as comma-separated
    local devices_csv=""
    if [ ${#SELECTED_DEVICES[@]} -gt 0 ]; then
        devices_csv=$(IFS=','; echo "${SELECTED_DEVICES[*]}")
    fi

    cat > "$env_file" << ENV
# Venus OS Docker — Instance configuration
# Generated by install.sh on $(date -Iseconds)
# Re-run install.sh to reconfigure.

VENUS_INSTANCE_NAME="${INSTANCE_NAME}"
VENUS_IMAGE="${DOCKER_IMAGE}"
VENUS_PORT_HTTP="${PORT_HTTP}"
VENUS_PORT_HTTPS="${PORT_HTTPS}"
VENUS_PORT_MQTT="${PORT_MQTT}"
VENUS_PORT_MQTT_WS="${PORT_MQTT_WS}"
VENUS_PORT_SSH="${PORT_SSH}"
VENUS_EXPOSE_HTTP="${EXPOSE_HTTP}"
VENUS_BLUETOOTH="${BLUETOOTH_ENABLED}"
VENUS_BT_DEVICE="${BT_DEVICE}"
VENUS_DEVICES="${devices_csv}"
ENV

    info "Generated $env_file"
}

# ── Create data directory ────────────────────────────────────────────────────

create_data_dir() {
    local data_dir="$INSTALL_DIR/venus-os-data"
    if [ ! -d "$data_dir" ]; then
        mkdir -p "$data_dir"
        info "Created $data_dir/"
    else
        info "Data directory exists: $data_dir/ (preserved)"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    echo ""
    printf "${BOLD}┌────────────────────────────────────────────────────────┐${RESET}\n"
    printf "${BOLD}│  Venus OS in Docker — Installer Wizard                 │${RESET}\n"
    printf "${BOLD}│  github.com/RafaelKa/victron-venus-os-in-docker        │${RESET}\n"
    printf "${BOLD}└────────────────────────────────────────────────────────┘${RESET}\n"

    # Initialize env defaults
    ENV_INSTANCE_NAME="" ENV_IMAGE="" ENV_PORT_HTTP="" ENV_PORT_HTTPS=""
    ENV_PORT_MQTT="" ENV_PORT_MQTT_WS="" ENV_PORT_SSH="" ENV_BLUETOOTH=""
    ENV_BT_DEVICE="" ENV_DEVICES="" ENV_EXPOSE_HTTP=""

    # Try loading .env from current directory (re-run case)
    if [ -f ".env" ] && grep -q "VENUS_INSTANCE_NAME" ".env" 2>/dev/null; then
        load_existing_env ".env" || true
    fi

    check_prerequisites
    configure_instance_name
    configure_install_dir
    configure_image
    configure_devices
    configure_bluetooth
    configure_ports
    show_summary

    if ! ask_yn "Generate configuration and proceed?" "y"; then
        echo ""
        warn "Aborted. No files were written."
        exit 0
    fi

    echo ""
    header "Generating Files"

    create_data_dir
    generate_compose
    generate_env

    echo ""
    header "Done"

    echo "Your Venus OS instance is ready. To start it:"
    echo ""
    printf "  ${BOLD}cd %s${RESET}\n" "$INSTALL_DIR"
    printf "  ${BOLD}docker compose up -d${RESET}\n"
    echo ""
    echo "Access:"
    if [ "$EXPOSE_HTTP" = "true" ]; then
        printf "  Web GUI:  http://<your-ip>:%s/\n" "$PORT_HTTP"
    else
        echo "  Web GUI:  via your reverse proxy (HTTP/HTTPS not exposed to host)"
    fi
    printf "  MQTT:     <your-ip>:%s\n" "$PORT_MQTT"
    printf "  SSH:      ssh -p %s root@<your-ip>\n" "$PORT_SSH"
    echo ""
    echo "To reconfigure, run install.sh again from $(dirname "$INSTALL_DIR")."
    echo ""
}

main "$@"
