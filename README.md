# Venus OS in Docker

Run [Victron Energy's Venus OS](https://github.com/victronenergy/venus) inside a Docker container on Raspberry Pi OS or any compatible Linux host.

This lets you run Venus OS **alongside other applications** on the same hardware, instead of dedicating the entire device to Venus OS.

## Features

- Full Venus OS experience: web GUI, MQTT, D-Bus, all Venus services
- Single-layer Docker image built from official Victron images
- Hardware passthrough for Victron USB/serial devices (MPPTs, inverters, battery monitors)
- Automated builds via GitHub Actions
- Pre-built images on GitHub Container Registry

## Quick Start

### Pull and run

```bash
docker run -d \
  --name venus-os \
  --privileged \
  --network host \
  -v venus-data:/data \
  -v /dev/bus/usb:/dev/bus/usb \
  ghcr.io/rafaelka/venus-os:latest-raspberrypi5
```

### With Docker Compose

```bash
# Copy the example compose file
curl -O https://raw.githubusercontent.com/RafaelKa/victron-venus-os-in-docker/main/examples/docker-compose.yml

# Start
docker compose up -d
```

### Access

- **Web GUI:** http://your-pi-ip/
- **MQTT:** `your-pi-ip:1883`
- **SSH:** `ssh root@your-pi-ip` (when using `--network host`)

## Supported Platforms

| Platform         | Architecture | Status    |
|------------------|--------------|-----------|
| Raspberry Pi 5   | aarch64      | Supported |
| Raspberry Pi 4   | aarch64      | Planned   |
| Raspberry Pi 2   | armv7        | Planned   |
| BeagleBone Black | armv7        | Planned   |

## Configuration

Control Venus services via environment variables:

| Variable                | Default | Description                                          |
|-------------------------|---------|------------------------------------------------------|
| `VENUS_DISABLE_GUI`     | `0`     | Set to `1` to disable the Qt6 GUI (headless mode)    |
| `VENUS_DISABLE_MQTT`    | `0`     | Set to `1` to disable MQTT broker and D-Bus bridge   |
| `VENUS_DISABLE_NGINX`   | `0`     | Set to `1` to disable the web server                 |
| `VENUS_DISABLE_SSH`     | `0`     | Set to `1` to disable SSH server                     |
| `VENUS_ENABLE_HARDWARE` | `0`     | Set to `1` to enable Bluetooth and hardware services |

## Building from Source

```bash
# Requires: root privileges, Docker, curl, gunzip, sfdisk, losetup

# Build for Raspberry Pi 5
sudo make build MACHINE=raspberrypi5

# Run tests
make test

# Run the image
make run
```

See [docs/BUILDING.md](docs/BUILDING.md) for detailed instructions.

## How It Works

1. **Download** the official Venus OS image (`.wic.gz`) from Victron's update server
2. **Extract** the rootfs partition from the disk image
3. **Modify** the rootfs in-place for container compatibility (disable connman, patch init scripts, add entrypoint)
4. **Package** as a single-layer Docker image (`FROM scratch` + rootfs tarball)

Venus OS uses **sysvinit + daemontools** for service management. The container entrypoint starts D-Bus, sets up the service directory, and runs `svscan` as PID 1. All Venus services are supervised automatically.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for technical details.

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — Technical design and internals
- [Building](docs/BUILDING.md) — Build instructions
- [Running](docs/RUNNING.md) — Usage guide
- [Hardware Setup](docs/HARDWARE-SETUP.md) — Connecting Victron devices
- [Configuration](docs/CONFIGURATION.md) — Environment variables and settings
- [Troubleshooting](docs/TROUBLESHOOTING.md) — Common issues

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

Venus OS is developed by [Victron Energy](https://www.victronenergy.com/) and is also licensed under the GPL.
