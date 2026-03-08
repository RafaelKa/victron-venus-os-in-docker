# Architecture

## Overview

This project takes official Victron Venus OS disk images and transforms them into Docker images. All modifications are applied to the rootfs **before** Docker import, resulting in a single-layer image.

## Build Pipeline

```
Download .wic.gz → Extract rootfs → Modify in-place → tar → FROM scratch + ADD → single-layer image
```

### Why single-layer?

Each Dockerfile instruction (`RUN`, `COPY`, etc.) creates a new layer. By performing all modifications on the extracted rootfs before `docker build`, the entire filesystem becomes one layer. This minimizes image size and avoids layer overhead.

## Venus OS Internals

### Init System: sysvinit + daemontools

Venus OS does **not** use systemd. It uses a two-tier init:

1. **sysvinit** handles boot (`/etc/inittab` → `/etc/init.d/rcS`)
2. **daemontools (`svscan`)** supervises long-running services

Services live in `/opt/victronenergy/service/`. At boot, `overlays.sh` copies them to `/run/overlays/service/` (a tmpfs) and bind-mounts to `/service`. `svscan` continuously scans `/service` and starts a `supervise` process for each subdirectory.

In the Docker container, the entrypoint replicates this setup and then `exec`s `svscan` as PID 1.

### D-Bus: The Nervous System

All Victron services communicate via the **D-Bus system bus**. Every data point (battery voltage, solar production, inverter state) is published as a D-Bus object.

- D-Bus must be running before any service starts
- The entrypoint starts `dbus-daemon --system` before `svscan`
- The `dbus-mqtt` service bridges D-Bus to MQTT for external access

### Service Lifecycle

```
svscan /service
  ├── supervise localsettings      → localsettings.py (settings store)
  ├── supervise dbus-systemcalc-py → system calculations
  ├── supervise dbus-mqtt          → D-Bus ↔ MQTT bridge
  ├── supervise flashmq            → MQTT broker
  ├── supervise nginx              → Web GUI server
  ├── supervise ...                → (many more services)
  └── supervise start-gui          → Qt6 GUI (optional)
```

If a service crashes, `supervise` restarts it automatically. Services with a `down` file in their directory are not started.

### Filesystem Layout

```
/                           Container rootfs (writable)
├── /data/                  Docker volume — persistent settings, logs, databases
├── /opt/victronenergy/     Venus OS software
│   └── /service/           Service definitions (read-only originals)
├── /service/               Active services (bind-mount from /run/overlays/service)
├── /run/overlays/service/  Writable copy of service definitions
├── /etc/venus/
│   ├── machine             Platform identifier (e.g., "raspberrypi5")
│   └── docker              Docker environment marker
└── /entrypoint.sh          Container entrypoint
```

## Container Adaptations

### What's changed from native Venus OS

| Aspect        | Native Venus OS                 | Docker Container                     |
|---------------|---------------------------------|--------------------------------------|
| Init          | sysvinit PID 1                  | `svscan` PID 1 (via entrypoint)      |
| Rootfs        | Read-only ext4 + tmpfs overlays | Writable container layer             |
| Networking    | connman                         | Docker networking (connman disabled) |
| Storage       | Dedicated /data partition       | Docker volume                        |
| D-Bus         | Started by init.d script        | Started by entrypoint                |
| Hardware      | Direct kernel access            | Passthrough via `--privileged`       |
| Service setup | `overlays.sh` in init           | Entrypoint replicates logic          |

### What's NOT changed

- All Venus services are unmodified
- D-Bus configuration is stock
- The opkg package manager works
- MQTT, web GUI, and all user-facing features work as expected

## Image Tagging

```
ghcr.io/rafaelka/venus-os:v{version}-{machine}    # Versioned
ghcr.io/rafaelka/venus-os:latest-{machine}         # Latest
```
