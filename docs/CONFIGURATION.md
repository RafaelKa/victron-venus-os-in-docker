# Configuration

## Environment Variables

Control Venus OS behavior at container startup via environment variables.

### Service Control

| Variable                | Default | Description                                                                                                                 |
|-------------------------|---------|-----------------------------------------------------------------------------------------------------------------------------|
| `VENUS_DISABLE_GUI`     | `0`     | Set to `1` to disable the Qt6 GUI service. Useful for headless/server setups. The web GUI (via nginx) remains available.    |
| `VENUS_DISABLE_MQTT`    | `0`     | Set to `1` to disable both the MQTT broker (FlashMQ) and the D-Bus-to-MQTT bridge.                                          |
| `VENUS_DISABLE_NGINX`   | `0`     | Set to `1` to disable the web server. No web GUI will be available.                                                         |
| `VENUS_DISABLE_SSH`     | `0`     | Set to `1` to disable the SSH server inside the container.                                                                  |
| `VENUS_ENABLE_HARDWARE` | `0`     | Set to `1` to enable hardware-dependent services (Bluetooth, connman). Enable this when real Victron hardware is connected. |

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

| Mount Point    | Purpose                                              | Required            |
|----------------|------------------------------------------------------|---------------------|
| `/data`        | Persistent Venus OS data (settings, logs, databases) | Recommended         |
| `/dev/bus/usb` | USB device passthrough                               | For hardware access |

## Ports

| Port | Service                  | Protocol |
|------|--------------------------|----------|
| 80   | nginx (Web GUI)          | HTTP     |
| 443  | nginx (Web GUI)          | HTTPS    |
| 1883 | FlashMQ (MQTT)           | MQTT     |
| 9001 | FlashMQ (MQTT WebSocket) | WS       |
| 22   | OpenSSH                  | SSH      |

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
