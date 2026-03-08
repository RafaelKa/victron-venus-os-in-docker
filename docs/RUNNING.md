# Running Venus OS in Docker

## Prerequisites

- Docker installed on your host
- Docker Compose v2 (docker-compose-plugin)
- For Victron hardware: USB/serial device connected to the host

## Option 1: Interactive Installer (Recommended)

The installer wizard guides you through setup, detects serial devices, configures ports, and generates a ready-to-use `docker-compose.yml`:

```bash
bash install.sh
```

It creates an instance directory with everything needed:
```
my-instance/
├── docker-compose.yml    # Generated configuration
├── .env                  # Saved settings (for re-running installer)
└── venus-os-data/        # Persistent Venus OS data
```

Start:
```bash
cd my-instance/
docker compose up -d
```

Re-run `install.sh` to reconfigure — data in `venus-os-data/` is preserved.

## Option 2: Docker Compose Examples

Example files are in the `examples/` directory:

```bash
# Standard setup (bridge network, port mapping)
docker compose -f examples/docker-compose.yml up -d

# Headless (no GUI, web interface only)
docker compose -f examples/docker-compose.headless.yml up -d

# Development (no auto-restart)
docker compose -f examples/docker-compose.development.yml up -d
```

## Option 3: Docker Run

### Basic (bridge network)

```bash
docker run -d \
  --name venus-os \
  --privileged \
  -p 80:80 -p 443:443 -p 1883:1883 -p 9001:9001 -p 2222:22 \
  -v ./venus-os-data:/data \
  ghcr.io/rafaelka/venus-os:latest-raspberrypi5
```

### With serial device

```bash
docker run -d \
  --name venus-os \
  --privileged \
  -p 80:80 -p 1883:1883 -p 2222:22 \
  -v ./venus-os-data:/data \
  --device /dev/serial/by-id/usb-VictronEnergy_MK3-USB_Interface_HQ00000001-if00-port0:/dev/ttyUSBMK3 \
  -e VENUS_DISABLE_GUI=1 \
  ghcr.io/rafaelka/venus-os:latest-raspberrypi5
```

## Accessing Venus OS

### Web Interface
Open `http://<your-host-ip>/` in a browser (or the configured HTTP port). The Venus OS web GUI provides full system monitoring and configuration.

### MQTT
Connect an MQTT client to `<your-host-ip>:1883`. All Venus data is available via MQTT topics under `N/` (notifications) and `R/` (read), `W/` (write).

Example with `mosquitto_sub`:
```bash
mosquitto_sub -h <your-host-ip> -t 'N/#' -v
```

### SSH
```bash
# Default port mapping (2222 → 22):
ssh -p 2222 root@<your-host-ip>
```

### D-Bus (from inside the container)
```bash
docker exec -it venus-os dbus-send --print-reply --system \
  --dest=com.victronenergy.settings \
  /Settings/System/VenusVersion \
  com.victronenergy.BusItem.GetValue
```

## Managing Services

From inside the container, use daemontools commands:

```bash
# List all services and their status
docker exec venus-os sh -c 'svstat /service/*'

# Stop a service
docker exec venus-os svc -d /service/nginx

# Start a service
docker exec venus-os svc -u /service/nginx

# Restart a service
docker exec venus-os svc -t /service/nginx
```

## Persistent Data

The `./venus-os-data/` directory stores:
- Venus OS settings (`conf/`)
- Logs (`log/`)
- Databases (`db/`)

This persists across container restarts and updates. To reset to defaults:
```bash
rm -rf ./venus-os-data/
```

## Updating

```bash
# Pull the latest image
docker pull ghcr.io/rafaelka/venus-os:latest-raspberrypi5

# Restart the container
docker compose down && docker compose up -d
```

Your `venus-os-data/` directory is preserved across updates.

## Multiple Instances

Bridge networking allows running multiple Venus OS instances on the same host. Use different instance names and port mappings:

```bash
# Instance 1: boat main system
bash install.sh  # name: boat-main, HTTP: 8080

# Instance 2: shore power monitor
bash install.sh  # name: shore-monitor, HTTP: 8081
```

## Stopping

```bash
docker compose down

# Or with docker run:
docker stop venus-os
docker rm venus-os
```
