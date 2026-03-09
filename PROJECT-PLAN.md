# Venus OS in Docker — Project Plan

## Vision

Run the full Victron Venus OS experience inside a Docker container on Raspberry Pi OS (or any Linux host), enabling Venus OS to coexist with other applications on the same hardware.

## How Venus OS Works (Key Findings from Source Analysis)

### Init & Service Management
- **sysvinit** as PID 1 (NOT systemd) — container-friendly
- **daemontools (svscan)** supervises all Venus services
- Services live in `/opt/victronenergy/service/`, copied to `/run/overlays/service/` at boot, then bind-mounted to `/service`
- `svscan /service` starts and supervises everything
- Individual control: `svc -u/-d/-t /service/<name>`

### Inter-Process Communication
- **D-Bus (system bus)** is the central nervous system — ALL Victron services communicate via D-Bus
- D-Bus socket at `/var/run/dbus/system_bus_socket`
- Venus also bridges D-Bus to **MQTT** (via `dbus-mqtt` service)

### Image Structure (Raspberry Pi)
- 2 partitions: **boot** (vfat, ~20MB) + **rootfs** (ext4)
- **Read-only rootfs** with tmpfs overlays for runtime state
- Persistent data on `/data` partition (separate on real hardware)
- Package manager: **opkg** (OpenWrt-style)

### Image Download URLs
```
Base: https://updates.victronenergy.com/feeds/venus/{feed}/images/{machine}/
Feeds: develop | testing | candidate | release
Machines: raspberrypi5, raspberrypi4, raspberrypi2, beaglebone, ccgx, einstein, ekrano, nanopi, sunxi
Files: venus-image-{machine}.wic.gz (full image), venus-swu-{machine}.swu (update)
```

### Key Services (all daemontools-supervised)
| Service                | Purpose                                                  |
|------------------------|----------------------------------------------------------|
| `dbus`                 | System message bus (started via init.d, not daemontools) |
| `localsettings`        | Persistent settings store                                |
| `dbus-systemcalc-py`   | System calculations (battery state, etc.)                |
| `dbus-mqtt`            | D-Bus ↔ MQTT bridge                                      |
| `flashmq`              | MQTT broker                                              |
| `nginx`                | Web server for HTML5 GUI                                 |
| `gui-v2` / `start-gui` | Qt6 GUI (local display)                                  |
| `gui-v2-webassembly`   | Web-based GUI (via nginx)                                |
| `venus-html5-logger`   | Data logging                                             |
| `venus-access`         | Remote access management                                 |
| `venus-platform`       | Platform detection                                       |
| `node-red-venus`       | Node-RED integration (large image)                       |
| `signalk-server`       | Signal K server (large image)                            |
| `dbus-generator`       | Generator control                                        |
| `dbus-modbus-client`   | Modbus device communication                              |
| `dbus-shelly`          | Shelly device integration                                |
| `avahi`                | mDNS/DNS-SD discovery                                    |
| `connman`              | Network management                                       |
| `openssh`              | SSH server                                               |
| `cronie`               | Cron scheduler                                           |
| Various `dbus-*`       | Device-specific drivers                                  |

### Supported Platforms (Machines)
| Machine        | Architecture                 | Priority    |
|----------------|------------------------------|-------------|
| `raspberrypi5` | aarch64 (armv8-2a/cortexa76) | **Phase 1** |
| `raspberrypi4` | aarch64 (armv8a/cortexa72)   | Phase 2     |
| `raspberrypi2` | armv7 (cortexa7)             | Phase 2     |
| `beaglebone`   | armv7 (cortexa8)             | Phase 3     |
| `einstein`     | armv7 (sunxi)                | Phase 3     |
| `ekrano`       | TBD                          | Phase 3     |
| `nanopi`       | TBD                          | Phase 3     |
| `ccgx`         | armv7                        | Phase 3     |

---

## Architecture

### Build Pipeline: Single-Layer Docker Image

All modifications happen **before** importing into Docker. This produces a single-layer image with minimal size — no Dockerfile patch layers.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌───────────────┐
│   Download   │────▶│   Extract    │────▶│   Modify     │────▶│   Package    │────▶│    Import     │
│  .wic.gz     │     │   rootfs     │     │   rootfs     │     │  rootfs.tar  │     │  FROM scratch │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └───────────────┘
                                                                                            │
                                                                       ┌────────────┐       │
                                                                       │  Push to   │◀──────┘
                                                                       │  ghcr.io   │
                                                                       └────────────┘
```

### Step-by-Step Build Process

#### 1. Download (`scripts/download-image.sh`)
- Fetch `venus-image-{machine}.wic.gz` from Victron update server
- Verify integrity (checksum if available)
- Support specifying: machine, feed (release/candidate/develop), version

#### 2. Extract rootfs (`scripts/extract-rootfs.sh`)
- Decompress `.wic.gz` → `.wic` (raw disk image)
- Parse partition table to find rootfs offset and size (`sfdisk --dump`)
- Mount rootfs partition via loopback with offset
- Copy rootfs to staging directory
- Unmount and clean up

#### 3. Modify rootfs in-place (`scripts/modify-rootfs.sh`)
All patches applied directly to the extracted rootfs **before** packaging:

- **Add `/entrypoint.sh`** — container entrypoint that:
  - Initializes `/data` volume if empty
  - Starts D-Bus daemon
  - Sets up `/service` directory (replicates `overlays.sh` logic: copy `/opt/victronenergy/service/*` → `/run/overlays/service/`, bind-mount to `/service`)
  - Optionally disables unwanted services based on env vars
  - Starts `svscan /service` as main process (PID 1 via exec)
- **Disable connman** — Docker/host manages networking
- **Disable read-only rootfs handling** — not needed in container
- **Disable kernel-dependent udev rules** — no kernel access in container
- **Ensure writable directories** — `/tmp`, `/var/run`, `/var/log`, `/var/volatile`, etc.
- **Create `/data` mount point** — will be a Docker volume
- **Adjust `/etc/venus/machine`** — correct platform identification

#### 4. Package rootfs (`scripts/build-docker-image.sh`)
- Create tarball: `tar -C staging/ -czf rootfs.tar.gz .`
- Minimal Dockerfile:
  ```dockerfile
  FROM scratch
  ADD rootfs.tar.gz /
  VOLUME /data
  EXPOSE 80 443 1883 9001
  ENTRYPOINT ["/entrypoint.sh"]
  ```
- Single layer. No additional layers. Minimal image.

#### 5. Test & Push
- Start container, run test suite
- Push to `ghcr.io` with version tags

### Container Runtime Configuration

```yaml
# docker-compose.yml
services:
  venus-os:
    image: ghcr.io/rafaelka/venus-os:latest-raspberrypi5
    privileged: true                    # For USB/serial device access
    network_mode: host                  # For mDNS, device discovery
    volumes:
      - venus-data:/data               # Persistent Venus settings & data
      - /dev/bus/usb:/dev/bus/usb      # USB devices (Victron hardware)
    devices:
      - /dev/ttyUSB0:/dev/ttyUSB0      # Serial Victron devices (adjust as needed)
    environment:
      - VENUS_DISABLE_GUI=0            # 1 = disable Qt6 GUI (headless mode)
      - VENUS_DISABLE_HARDWARE=0       # 1 = skip hardware-dependent services
    restart: unless-stopped

volumes:
  venus-data:
```

---

## Repository Structure

```
venus-os-docker/
├── .github/
│   ├── workflows/
│   │   ├── build-and-test.yml          # CI: build + test on PR and push to main
│   │   ├── release.yml                 # Build + push to ghcr.io on git tag
│   │   └── check-new-version.yml       # Scheduled: detect new Venus OS releases
│   └── ISSUE_TEMPLATE/
│       ├── bug_report.md
│       └── feature_request.md
│
├── scripts/
│   ├── common.sh                       # Shared variables, functions, error handling
│   ├── download-image.sh               # Download Venus OS .wic.gz from Victron
│   ├── extract-rootfs.sh               # Extract rootfs partition from .wic image
│   ├── modify-rootfs.sh                # Apply all container-compatibility patches
│   ├── build-docker-image.sh           # Full pipeline: download → extract → modify → build
│   └── check-latest-version.sh         # Query Victron server for latest version
│
├── rootfs-overlay/
│   ├── entrypoint.sh                   # Container entrypoint (added to rootfs /)
│   └── etc/
│       └── venus/
│           └── docker                  # Marker file: "this is a Docker container"
│
├── tests/
│   ├── run-all-tests.sh               # Test runner with summary
│   ├── test-container-boots.sh         # Container starts and stays running (>30s)
│   ├── test-dbus-running.sh            # dbus-daemon process exists, socket available
│   ├── test-svscan-running.sh          # svscan process exists, /service populated
│   ├── test-services-up.sh             # Key services (localsettings, systemcalc) supervised
│   ├── test-mqtt-available.sh          # MQTT broker accepts connections on port 1883
│   ├── test-web-gui.sh                 # HTTP 200 on port 80 (nginx + web GUI)
│   └── test-dbus-read.sh              # Can read D-Bus values (e.g., Venus version)
│
├── examples/
│   ├── docker-compose.yml              # Standard setup with hardware passthrough
│   ├── docker-compose.headless.yml     # No GUI, data collection only
│   └── docker-compose.development.yml  # With debug ports, extra volumes
│
├── config/
│   └── machines.json                   # Machine configs: name, arch, download URL pattern
│
├── docs/
│   ├── ARCHITECTURE.md                 # Technical deep dive
│   ├── BUILDING.md                     # How to build locally
│   ├── RUNNING.md                      # How to run the container
│   ├── HARDWARE-SETUP.md              # Connecting Victron USB/serial devices
│   ├── CONFIGURATION.md               # Environment variables reference
│   ├── TROUBLESHOOTING.md             # Common issues & solutions
│   └── SUPPORTED-PLATFORMS.md         # Which machines are supported
│
├── Makefile                            # Build shortcuts (make build, make test, etc.)
├── README.md                           # Quick start, badges, overview
├── LICENSE
├── CHANGELOG.md
└── CONTRIBUTING.md
```

---

## Implementation Phases

### Phase 1: Raspberry Pi 5 — MVP

**Goal:** Working Docker image for RPi5, built and tested via GitHub Actions, pushed to `ghcr.io`.

#### 1.1 Build Scripts
- `scripts/common.sh` — shared config (download URLs, machine list, error handling)
- `scripts/download-image.sh` — download `venus-image-raspberrypi5.wic.gz`
- `scripts/extract-rootfs.sh` — mount and extract rootfs from WIC image
- `scripts/modify-rootfs.sh` — apply all patches to rootfs directory
- `scripts/build-docker-image.sh` — orchestrate full pipeline

#### 1.2 Container Entrypoint
- `rootfs-overlay/entrypoint.sh`:
  1. Initialize `/data` if empty (first run)
  2. Start `dbus-daemon --system`
  3. Replicate `overlays.sh`: copy `/opt/victronenergy/service/*` → tmpfs → bind-mount `/service`
  4. Disable services based on `VENUS_DISABLE_*` env vars
  5. `exec svscan /service` (becomes PID 1)

#### 1.3 Rootfs Modifications
- Disable connman (remove from `/service` or add `down` file)
- Disable udev hardware rules that won't work in container
- Fix read-only rootfs assumptions in init scripts
- Create proper `/data` directory structure
- Add Docker marker file (`/etc/venus/docker`)
- Copy `rootfs-overlay/` contents into rootfs

#### 1.4 Tests
- All tests in `tests/` — run inside or against the container
- Test runner with pass/fail summary and exit code for CI

#### 1.5 GitHub Actions
- `build-and-test.yml`:
  - Trigger: push to main, pull requests
  - Setup QEMU + BuildX (ARM64 emulation on x86 runner)
  - Run full build pipeline
  - Start container, run tests
  - Upload artifacts (logs, test results)
- `release.yml`:
  - Trigger: git tag `v*`
  - Full build + test
  - Push to `ghcr.io` with version tags

#### 1.6 Documentation
- README.md — quick start, what this is, how to use it
- docs/BUILDING.md — build from source
- docs/RUNNING.md — run on your Pi
- docs/ARCHITECTURE.md — technical decisions

### Phase 2: Multi-Platform

**Goal:** RPi4, RPi2 support. Matrix builds.

- Parameterize all scripts with `MACHINE` variable
- GitHub Actions matrix strategy: `[raspberrypi5, raspberrypi4, raspberrypi2]`
- Multi-arch manifest so `docker pull` auto-selects architecture
- `config/machines.json` for machine-specific settings
- `check-new-version.yml`: weekly cron to detect new Venus releases

### Phase 3: All Platforms + Advanced

**Goal:** Full SBC coverage. Production-ready documentation.

- BeagleBone, NanoPi, Sunxi, Einstein support
- Hardware setup guides with photos/diagrams
- Integration examples (Home Assistant, Grafana, Node-RED on host)
- Health check endpoint
- Log forwarding configuration

---

## GitHub Actions Strategy

### Build Environment
- **Runner:** `ubuntu-latest` (x86_64)
- **ARM emulation:** QEMU via `docker/setup-qemu-action`
- **BuildX:** `docker/setup-buildx-action` for multi-platform builds
- **Registry:** GitHub Container Registry (`ghcr.io`)

### Workflow: `build-and-test.yml`
```yaml
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3

      - name: Cache Venus OS image
        uses: actions/cache@v4
        with:
          path: build/downloads/
          key: venus-image-${{ env.VENUS_VERSION }}-${{ env.MACHINE }}

      - name: Build Docker image
        run: make build MACHINE=raspberrypi5

      - name: Run tests
        run: make test

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: build/test-results/
```

### Workflow: `release.yml`
```yaml
on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      # ... setup steps ...
      - name: Login to ghcr.io
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        run: make release MACHINE=raspberrypi5

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
```

### Caching Strategy
- **Venus OS images** (~100-300MB): cached by version+machine key
- **Docker layers**: BuildX cache (GitHub Actions cache backend)

---

## Technical Challenges & Solutions

| Challenge              | Solution                                                                                                 |
|------------------------|----------------------------------------------------------------------------------------------------------|
| **Read-only rootfs**   | Not an issue — Docker container layer is writable. Remove r/o handling from init.                        |
| **No hardware in CI**  | Test software-level only (D-Bus, MQTT, web GUI). Services without hardware fail gracefully under svscan. |
| **ARM on x86 CI**      | QEMU user-mode emulation. Slower but works. Self-hosted ARM runners later.                               |
| **Kernel modules**     | Host kernel must provide them. Document required modules. `--privileged` gives access.                   |
| **D-Bus isolation**    | Own D-Bus by default. Document host D-Bus sharing if needed (mount socket).                              |
| **Network management** | Disable connman. Docker/host handles networking. `--net=host` for device discovery.                      |
| **Image size**         | Single-layer build keeps it minimal. Standard and large variants like original Venus OS available.       |
| **Extracting rootfs**  | Needs `losetup`/`mount` with root privileges. In CI: runs as root. Locally: `sudo` or `fakeroot`.        |

---

## Naming & Tagging Convention

### Docker Image Tags
```
ghcr.io/rafaelka/venus-os:v{venus-version}-{machine}     # Versioned
ghcr.io/rafaelka/venus-os:latest-{machine}               # Latest for machine
ghcr.io/rafaelka/venus-os:v3.50-raspberrypi5             # Example
ghcr.io/rafaelka/venus-os:latest-raspberrypi5            # Example
```

### Git Tags
```
v{venus-version}-{build}    # e.g., v3.50-1, v3.50-2
```

---

## Open Questions (To Decide During Implementation)

1. ~~**License**~~ → **GPL v3**. Venus OS is GPL, and we modify+redistribute the rootfs. All modifications must remain public.
2. ~~**GitHub org/user**: What GitHub account hosts the repository?~~ → **RafaelKa** — repo: `github.com/RafaelKa/victron-venus-os-in-docker`, images: `ghcr.io/rafaelka/venus-os`
3. ~~**Image variants**: Standard and large images like original Venus OS.~~
4. Add bashunit tests for critical parts, which must be run inside of container/chroot. See: https://bashunit.typeddevs.com/quickstart 
5. **Venus version pinning**: Track latest release feed? Or pin specific versions?
6. **Qt6 GUI**: Include in container by default? Needs display access (X11/Wayland socket passthrough). Maybe web-only by default, Qt GUI opt-in.
