# Building from Source

## Prerequisites

- **Linux host** (or WSL2) — loopback mount requires Linux
- **Root access** — needed for `losetup` and `mount` during rootfs extraction
- **Docker** — for building and running the image
- **Tools:** `curl`, `gunzip`, `sfdisk`, `losetup`, `mount`, `tar`

On Ubuntu/Debian:
```bash
sudo apt install curl gzip fdisk mount util-linux docker.io
```

## Quick Build

```bash
# Clone the repository
git clone https://github.com/RafaelKa/victron-venus-os-in-docker.git
cd victron-venus-os-in-docker

# Build for Raspberry Pi 5 (default)
sudo make build

# Or specify a different machine/feed
sudo make build MACHINE=raspberrypi4 FEED=candidate
```

## Step-by-Step Build

If you prefer to run each step individually:

### 1. Download the Venus OS image

```bash
bash scripts/download-image.sh --machine raspberrypi5 --feed release
```

Downloads to `build/downloads/venus-image-raspberrypi5.wic.gz`. Subsequent runs skip the download if the file is up to date (HTTP 304).

### 2. Extract the rootfs

```bash
sudo bash scripts/extract-rootfs.sh --machine raspberrypi5
```

Mounts the `.wic` image via loopback, copies the rootfs partition to `build/rootfs-staging/`.

### 3. Modify the rootfs

```bash
sudo bash scripts/modify-rootfs.sh --rootfs build/rootfs-staging --machine raspberrypi5
```

Applies container-compatibility patches in-place:
- Adds `/entrypoint.sh`
- Disables connman and hardware-dependent services
- Creates `/data` mount point
- Patches init scripts to skip in Docker

### 4. Build the Docker image

```bash
# Create tarball
sudo tar -cf build/output/rootfs.tar -C build/rootfs-staging .

# Build image
docker build -f docker/Dockerfile -t venus-os:local --build-arg ROOTFS_TAR=rootfs.tar build/output/
```

### 5. Verify

```bash
make test
```

## Build Variables

| Variable         | Default        | Description                                                  |
|------------------|----------------|--------------------------------------------------------------|
| `MACHINE`        | `raspberrypi5` | Target machine                                               |
| `FEED`           | `release`      | Venus OS feed (`release`, `candidate`, `testing`, `develop`) |
| `VENUS_VERSION`  | `latest`       | Version string for Docker tag                                |
| `IMAGE_REGISTRY` | `ghcr.io`      | Docker registry                                              |
| `IMAGE_OWNER`    | `rafaelka`     | Registry owner                                               |
| `IMAGE_NAME`     | `venus-os`     | Image name                                                   |

## Makefile Targets

| Target           | Description                                          |
|------------------|------------------------------------------------------|
| `make build`     | Full pipeline: download + extract + modify + package |
| `make download`  | Download Venus OS image only                         |
| `make extract`   | Extract rootfs (requires root)                       |
| `make modify`    | Apply container patches                              |
| `make package`   | Create tarball and build Docker image                |
| `make test`      | Run test suite                                       |
| `make run`       | Run the container interactively                      |
| `make clean`     | Remove build artifacts (keep downloads)              |
| `make distclean` | Remove everything including downloads                |

## CI Build

The GitHub Actions workflow builds the image on every push to `main`. See `.github/workflows/build-and-test.yml`. It uses QEMU for ARM64 emulation on x86 runners.
