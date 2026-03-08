# Configuration

## Environment Variables

Control Venus OS behavior at container startup via environment variables.

### Service Control

| Variable              | Default | Description                                                                                                              |
|-----------------------|---------|--------------------------------------------------------------------------------------------------------------------------|
| `VENUS_DISABLE_GUI`   | `0`     | Set to `1` to disable the Qt6 GUI service. Useful for headless/server setups. The web GUI (via nginx) remains available. |
| `VENUS_DISABLE_MQTT`  | `0`     | Set to `1` to disable both the MQTT broker (FlashMQ) and the D-Bus-to-MQTT bridge.                                       |
| `VENUS_DISABLE_NGINX` | `0`     | Set to `1` to disable the web server. No web GUI will be available.                                                      |
| `VENUS_DISABLE_SSH`   | `0`     | Set to `1` to disable the SSH server inside the container.                                                               |

### Bluetooth Auto-Detection

Bluetooth is enabled automatically when a Bluetooth HCI adapter is available inside the container. No environment variable is needed.

To pass a Bluetooth adapter into the container, add it to `devices:` in your `docker-compose.yml`:
```yaml
devices:
  - /dev/hci0:/dev/hci0
```

The entrypoint checks for `/sys/class/bluetooth/hci*` at startup and enables Bluetooth services (`start-bluetooth`, `bluetooth`, `vesmart-server`, `dbus-ble-sensors`) if an adapter is present.

### Build Variables

These are used during `make build`:

| Variable         | Default        | Description                                                            |
|------------------|----------------|------------------------------------------------------------------------|
| `MACHINE`        | `raspberrypi5` | Target platform. See `config/machines.json` for supported values.      |
| `FEED`           | `release`      | Venus OS release channel: `release`, `candidate`, `testing`, `develop` |
| `VENUS_VERSION`  | `latest`       | Version string for Docker image tag                                    |
| `IMAGE_REGISTRY` | `ghcr.io`      | Docker registry                                                        |
| `IMAGE_OWNER`    | `rafaelka`     | Registry owner/namespace                                               |
| `IMAGE_NAME`     | `venus-os`     | Docker image name                                                      |

## Volumes

| Mount Point       | Purpose                                              | Required    |
|-------------------|------------------------------------------------------|-------------|
| `./venus-os-data` | Persistent Venus OS data (settings, logs, databases) | Recommended |

Data is bind-mounted from a local directory (`./venus-os-data:/data`), making it easy to back up and inspect.

## Ports

| Port | Service                  | Protocol | Default Host Port |
|------|--------------------------|----------|-------------------|
| 80   | nginx (Web GUI)          | HTTP     | 80                |
| 443  | nginx (Web GUI)          | HTTPS    | 443               |
| 1883 | FlashMQ (MQTT)           | MQTT     | 1883              |
| 9001 | FlashMQ (MQTT WebSocket) | WS       | 9001              |
| 22   | OpenSSH                  | SSH      | 2222              |

Port mappings are configured in `docker-compose.yml`. The `install.sh` wizard helps avoid conflicts with existing services on the host.

## Serial Devices

Victron USB/serial devices are passed through using `devices:` in `docker-compose.yml`. Use stable `/dev/serial/by-id/` paths on the host side, and choose a friendly name for the container side:

```yaml
devices:
  - /dev/serial/by-id/usb-VictronEnergy_MK3-USB_Interface_HQ00000001-if00-port0:/dev/ttyUSBMK3
  - /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A10KXXXX-if00-port0:/dev/ttyUSBVEDirect
```

The `install.sh` wizard lists available devices and helps you choose container names.

## Venus OS Internal Configuration

Once running, Venus OS settings are managed via the web GUI or D-Bus. Settings are persisted in `/data/conf/settings.xml` (via the `localsettings` service).

You can also configure settings via MQTT:
```bash
# Read a setting
mosquitto_sub -h localhost -t 'N/+/settings/0/Settings/System/VenusVersion' -C 1

# Write a setting
mosquitto_pub -h localhost -t 'W/+/settings/0/Settings/SystemSetup/SystemName' -m '{"value": "My Venus"}'
```

Or via D-Bus from inside the container:
```bash
docker exec venus-os dbus-send --print-reply --system \
  --dest=com.victronenergy.settings \
  /Settings/SystemSetup/SystemName \
  com.victronenergy.BusItem.SetValue variant:string:"My Venus"
```
