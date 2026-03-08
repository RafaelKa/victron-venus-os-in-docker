# Hardware Setup

## Overview

Venus OS communicates with Victron hardware via USB/serial interfaces. When running in Docker, these devices must be explicitly passed through to the container.

## Recommended: Use `install.sh`

The easiest way to set up hardware passthrough is the interactive installer:

```bash
bash install.sh
```

It lists available serial devices, highlights Victron/FTDI devices, resolves symlinks, and lets you assign friendly container device names.

## Serial Devices via `/dev/serial/by-id/`

Use stable `/dev/serial/by-id/` paths on the host — these persist across reboots regardless of USB plug order.

### Finding Your Devices

```bash
ls -la /dev/serial/by-id/
```

Example output:
```
usb-VictronEnergy_MK3-USB_Interface_HQ2132XXXXX-if00-port0 -> ../../ttyUSB0
usb-FTDI_FT232R_USB_UART_A10KXXXX-if00-port0 -> ../../ttyUSB1
```

### Docker Compose Configuration

Map each device with the host path on the left and a friendly container name on the right:

```yaml
services:
  venus-os:
    devices:
      - /dev/serial/by-id/usb-VictronEnergy_MK3-USB_Interface_HQ2132XXXXX-if00-port0:/dev/ttyUSBMK3
      - /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A10KXXXX-if00-port0:/dev/ttyUSBVEDirect
```

The host-side symlink is resolved automatically by Docker. The container-side name (`/dev/ttyUSBMK3`) is what Venus OS sees inside the container.

### Naming Conventions

Choose container device names that describe the connected hardware:

| Victron Device      | Suggested Container Name |
|---------------------|--------------------------|
| MK3-USB (VE.Bus)    | `/dev/ttyUSBMK3`         |
| VE.Direct cable     | `/dev/ttyUSBVEDirect`    |
| MPPT controller     | `/dev/ttyUSBMPPT`        |
| BMV / SmartShunt    | `/dev/ttyUSBBMV`         |
| Charger / Inverter  | `/dev/ttyUSBCharger`     |

## Common Victron Devices

| Device                      | Interface         | Typical /dev/serial/by-id/ Pattern       |
|-----------------------------|-------------------|------------------------------------------|
| MK3-USB (VE.Bus)            | USB-Serial        | `usb-VictronEnergy_MK3-USB_Interface_*`  |
| VE.Direct USB cable         | USB-Serial (FTDI) | `usb-FTDI_FT232R_USB_UART_*`             |
| BlueSolar MPPT (VE.Direct)  | USB-Serial        | `usb-FTDI_*` or `usb-VictronEnergy_*`    |
| SmartSolar MPPT (VE.Direct) | USB-Serial        | `usb-FTDI_*` or `usb-VictronEnergy_*`    |
| BMV battery monitor         | USB-Serial        | `usb-VictronEnergy_*` or `usb-FTDI_*`    |
| Cerbo GX USB hub            | USB hub           | Multiple entries                         |
| CAN-bus adapters            | SocketCAN         | Uses `/dev/can0` (see CAN section below) |

## Multiple Devices

Pass each device as a separate entry in `devices:`:

```yaml
devices:
  - /dev/serial/by-id/usb-VictronEnergy_MK3-USB_Interface_HQ00000001-if00-port0:/dev/ttyUSBMK3
  - /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A10KXXXX-if00-port0:/dev/ttyUSBMPPT
  - /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_B20KXXXX-if00-port0:/dev/ttyUSBBMV
```

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

CAN interfaces require `--network host` and `--privileged`:
```yaml
services:
  venus-os:
    privileged: true
    network_mode: host
    # ...
```

## Bluetooth

Bluetooth is auto-detected at container startup. If an HCI adapter is available inside the container, Bluetooth services are enabled automatically.

To pass a Bluetooth adapter:

```yaml
devices:
  - /dev/hci0:/dev/hci0
```

The `install.sh` wizard detects available Bluetooth adapters and configures this for you.

## Troubleshooting

### Device not detected
1. Check that the device appears on the host: `ls -la /dev/serial/by-id/`
2. Verify it's mapped in `docker-compose.yml` under `devices:`
3. Check inside the container: `docker exec venus-os ls -la /dev/ttyUSB*`
4. Check Venus logs: `docker exec venus-os cat /var/log/messages`

### Permission denied
The container runs with `privileged: true`, which should grant full device access. If using a non-privileged setup, ensure the container user has access to the device group.

### Kernel module missing
Some devices need kernel modules loaded on the **host** (not in the container):
```bash
# Check loaded modules
lsmod | grep -E 'ftdi_sio|cp210x|ch341'

# Load if missing
sudo modprobe ftdi_sio
sudo modprobe cp210x
```

### Device path changed after reboot
This is why we use `/dev/serial/by-id/` paths — they are stable across reboots. If you used `/dev/ttyUSB0` paths, switch to by-id paths.
