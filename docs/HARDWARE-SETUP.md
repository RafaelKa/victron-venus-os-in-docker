# Hardware Setup

## Overview

Venus OS communicates with Victron hardware via USB and serial interfaces. When running in Docker, these devices must be passed through to the container.

## USB Devices

Most Victron devices connect via USB. The container needs access to `/dev/bus/usb` and any `/dev/ttyUSB*` or `/dev/ttyACM*` devices.

### Using `--privileged` (recommended for simplicity)

```bash
docker run -d --privileged \
  -v /dev/bus/usb:/dev/bus/usb \
  ghcr.io/rafaelka/venus-os:latest-raspberrypi5
```

### Using specific `--device` flags (more secure)

```bash
docker run -d \
  --device /dev/ttyUSB0 \
  --device /dev/ttyACM0 \
  -v /dev/bus/usb:/dev/bus/usb \
  ghcr.io/rafaelka/venus-os:latest-raspberrypi5
```

## Common Victron Devices

| Device                      | Interface         | Typical /dev Path       |
|-----------------------------|-------------------|-------------------------|
| MK3-USB (VE.Bus)            | USB-Serial        | `/dev/ttyUSB0`          |
| VE.Direct USB cable         | USB-Serial (FTDI) | `/dev/ttyUSB0`          |
| BlueSolar MPPT (VE.Direct)  | USB-Serial        | `/dev/ttyUSB0`          |
| SmartSolar MPPT (VE.Direct) | USB-Serial        | `/dev/ttyUSB0`          |
| BMV battery monitor         | USB-Serial        | `/dev/ttyUSB0`          |
| Cerbo GX USB hub            | USB hub           | Multiple `/dev/ttyUSB*` |
| CAN-bus adapters            | SocketCAN         | `/dev/can0`             |

**Note:** Device paths may vary. Use `dmesg` or `ls /dev/ttyUSB*` after plugging in a device to identify the correct path.

## Multiple Devices

If you have multiple Victron devices, pass them all through:

```bash
docker run -d --privileged \
  --device /dev/ttyUSB0 \
  --device /dev/ttyUSB1 \
  --device /dev/ttyUSB2 \
  -v /dev/bus/usb:/dev/bus/usb \
  ghcr.io/rafaelka/venus-os:latest-raspberrypi5
```

Or use `--privileged` which gives access to all devices.

## CAN Bus

For CAN-bus devices (e.g., BMS communication), the host kernel needs CAN support:

```bash
# Load CAN modules on the host
sudo modprobe can
sudo modprobe can-raw
sudo modprobe vcan  # for testing

# Set up a CAN interface
sudo ip link set can0 type can bitrate 250000
sudo ip link set up can0
```

Run the container with `--network host` and `--privileged` to access CAN-interfaces.

## Bluetooth

Venus OS can communicate with some devices via Bluetooth (e.g., VE.Direct Bluetooth Smart dongle). Enable hardware services:

```bash
docker run -d --privileged \
  --network host \
  -e VENUS_ENABLE_HARDWARE=1 \
  -v /dev/bus/usb:/dev/bus/usb \
  ghcr.io/rafaelka/venus-os:latest-raspberrypi5
```

The host's Bluetooth adapter is shared with the container in `--privileged` mode.

## Hotplug

When using `--privileged` with `/dev/bus/usb` mounted, USB hotplug works — you can plug and unplug Victron devices while the container is running. Venus OS detects them automatically via udev.

## Troubleshooting

### Device not detected
1. Check that the device appears on the host: `ls /dev/ttyUSB*`
2. Verify it's passed to the container: `docker exec venus-os ls /dev/ttyUSB*`
3. Check Venus logs: `docker exec venus-os cat /var/log/messages`

### Permission denied
Use `--privileged` or ensure the container user has access to the device group:
```bash
# Check device permissions on host
ls -la /dev/ttyUSB0
```

### Kernel module missing
Some devices need kernel modules loaded on the **host** (not in the container):
```bash
# Check loaded modules
lsmod | grep -E 'ftdi_sio|cp210x|ch341'

# Load if missing
sudo modprobe ftdi_sio
sudo modprobe cp210x
```
