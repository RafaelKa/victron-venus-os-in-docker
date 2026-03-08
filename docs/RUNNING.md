# Running Venus OS in Docker

## Prerequisites

- Docker installed on your host
- For Victron hardware: USB/serial device connected to the host

## Option 1: Docker Run

### Basic (with hardware access)

```bash
docker run -d \
  --name venus-os \
  --privileged \
  --network host \
  -v venus-data:/data \
  -v /dev/bus/usb:/dev/bus/usb \
  ghcr.io/rafaelka/venus-os:latest-raspberrypi5
```

### Headless (no Qt GUI, web only)

```bash
docker run -d \
  --name venus-os \
  --privileged \
  -p 80:80 -p 1883:1883 \
  -v venus-data:/data \
  -v /dev/bus/usb:/dev/bus/usb \
  -e VENUS_DISABLE_GUI=1 \
  -e VENUS_ENABLE_HARDWARE=1 \
  ghcr.io/rafaelka/venus-os:latest-raspberrypi5
```

## Option 2: Docker Compose

Example files are in the `examples/` directory:

```bash
# Standard setup (network=host, hardware passthrough)
docker compose -f examples/docker-compose.yml up -d

# Headless (mapped ports, no GUI)
docker compose -f examples/docker-compose.headless.yml up -d
```

## Accessing Venus OS

### Web Interface
Open `http://<your-host-ip>/` in a browser. The Venus OS web GUI provides full system monitoring and configuration.

### MQTT
Connect an MQTT client to `<your-host-ip>:1883`. All Venus data is available via MQTT topics under `N/` (notifications) and `R/` (read), `W/` (write).

Example with `mosquitto_sub`:
```bash
mosquitto_sub -h <your-host-ip> -t 'N/#' -v
```

### SSH
If SSH is enabled (default), connect to the container:
```bash
# With --network host:
ssh root@<your-host-ip>

# With port mapping (-p 2222:22):
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

The `/data` volume stores:
- Venus OS settings (`/data/conf/`)
- Logs (`/data/log/`)
- Databases (`/data/db/`)

This persists across container restarts and updates. To reset to defaults:
```bash
docker volume rm venus-data
```

## Updating

```bash
# Pull the latest image
docker pull ghcr.io/rafaelka/venus-os:latest-raspberrypi5

# Restart the container
docker compose down && docker compose up -d
```

Your `/data` volume is preserved across updates.

## Stopping

```bash
docker stop venus-os
docker rm venus-os

# Or with compose:
docker compose down
```
