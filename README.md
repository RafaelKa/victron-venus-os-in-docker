# Venus OS in Docker

Run [Victron Energy's Venus OS](https://github.com/victronenergy/venus) inside a Docker container on Raspberry Pi OS or any compatible Linux host.

This lets you run Venus OS **alongside other applications** on the same hardware, instead of dedicating the entire device to Venus OS.

## Features

- Full Venus OS experience: web GUI, MQTT, D-Bus, all Venus services
- Single-layer Docker image built from official Victron images
- **Interactive installer** — wizard for device selection, port mapping, and configuration
- **Bridge networking** — run multiple Venus OS instances on the same host
- **Explicit device passthrough** via stable `/dev/serial/by-id/` paths with friendly container names
- **Bluetooth auto-detection** — no manual flags needed
- Bind-mounted data directory for easy backup
- Automated builds via GitHub Actions
- Pre-built images on GitHub Container Registry

## Quick Start

### Interactive installer (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/RafaelKa/victron-venus-os-in-docker/main/install.sh -o install.sh
bash install.sh
```

The wizard will:
1. Check prerequisites (Docker, Compose v2)
2. Ask for an instance name (e.g., `boat-main`)
3. Detect and list serial devices — you choose which to assign and pick friendly container names
4. Detect Bluetooth adapters
5. Configure port mappings (with conflict warnings)
6. Generate `docker-compose.yml` and start instructions

### Manual setup

```bash
# Copy an example compose file
curl -O https://raw.githubusercontent.com/RafaelKa/victron-venus-os-in-docker/main/examples/docker-compose.yml

# Create data directory
mkdir venus-os-data

# Start
docker compose up -d
```

### Access

- **Web GUI:** http://your-host-ip/
- **MQTT:** `your-host-ip:1883`
- **SSH:** `ssh -p 2222 root@your-host-ip`

## Supported Platforms

| Platform         | Architecture | Status    |
|------------------|--------------|-----------|
| Raspberry Pi 5   | aarch64      | Supported |
| Raspberry Pi 4   | aarch64      | Planned   |
| Raspberry Pi 2   | armv7        | Planned   |
| BeagleBone Black | armv7        | Planned   |

## Configuration

Control Venus services via environment variables:

| Variable              | Default | Description                                        |
|-----------------------|---------|----------------------------------------------------|
| `VENUS_DISABLE_GUI`   | `0`     | Set to `1` to disable the Qt6 GUI (headless mode)  |
| `VENUS_DISABLE_MQTT`  | `0`     | Set to `1` to disable MQTT broker and D-Bus bridge |
| `VENUS_DISABLE_NGINX` | `0`     | Set to `1` to disable the web server               |
| `VENUS_DISABLE_SSH`   | `0`     | Set to `1` to disable SSH server                   |

Bluetooth is auto-detected — if an HCI adapter is passed through, BT services are enabled automatically.

See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for all options.

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
- [Running](docs/RUNNING.md) — Usage guide and installer reference
- [Hardware Setup](docs/HARDWARE-SETUP.md) — Connecting Victron devices via `/dev/serial/by-id/`
- [Configuration](docs/CONFIGURATION.md) — Environment variables and settings
- [Troubleshooting](docs/TROUBLESHOOTING.md) — Common issues

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

Venus OS is developed by [Victron Energy](https://www.victronenergy.com/) and is also licensed under the GPL.
