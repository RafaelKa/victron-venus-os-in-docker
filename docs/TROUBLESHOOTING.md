# Troubleshooting

## Container won't start

### "exec format error"
The image architecture doesn't match your host. Ensure you're using the correct image for your platform:
- Raspberry Pi 5/4: `latest-raspberrypi5` or `latest-raspberrypi4` (arm64)
- Raspberry Pi 2: `latest-raspberrypi2` (armv7)

### Container exits immediately
Check the logs:
```bash
docker logs venus-os
```

Common causes:
- D-Bus failed to start: check that `/var/run/dbus` is writable
- Missing `/opt/victronenergy/service/`: rootfs was not extracted correctly

## Services not starting

### Check service status
```bash
docker exec venus-os sh -c 'svstat /service/*'
```

Services showing "down" with a `down` file are intentionally disabled. Remove the file to enable:
```bash
docker exec venus-os rm /service/<service-name>/down
docker exec venus-os svc -u /service/<service-name>
```

### Service keeps restarting
Check the service log:
```bash
docker exec venus-os cat /service/<service-name>/log/main/current
```

Or check syslog:
```bash
docker exec venus-os cat /var/log/messages
```

## Web GUI not accessible

1. Check nginx is running:
   ```bash
   docker exec venus-os svstat /service/nginx
   ```

2. Check the port is exposed:
   ```bash
   docker port venus-os
   ```

3. With `--network host`, access via the host's IP directly on port 80.

## MQTT not working

1. Check FlashMQ is running:
   ```bash
   docker exec venus-os svstat /service/flashmq
   ```

2. Check it's listening:
   ```bash
   docker exec venus-os ss -tlnp | grep 1883
   ```

3. Test from inside the container:
   ```bash
   docker exec venus-os mosquitto_sub -h 127.0.0.1 -t '#' -C 1 -W 5
   ```

## Hardware not detected

See [HARDWARE-SETUP.md](HARDWARE-SETUP.md) for detailed hardware troubleshooting.

Quick checklist:
1. Is `--privileged` set?
2. Is `/dev/bus/usb` mounted?
3. Does the device appear on the host? (`ls /dev/ttyUSB*`)
4. Are kernel modules loaded on the host? (`lsmod | grep ftdi_sio`)
5. Is `VENUS_ENABLE_HARDWARE=1` set?

## Build failures

### "must be run as root"
The rootfs extraction step requires root for loopback mounting:
```bash
sudo make build
```

### "Image file not found"
The download may have failed. Check:
```bash
ls -la build/downloads/
```

Re-download:
```bash
make download
```

### "Could not identify rootfs partition"
The Venus OS image format may have changed. Check the partition table:
```bash
sfdisk --dump build/downloads/venus-image-*.wic
```

## Performance

### Container is slow
If running on x86 with QEMU emulation (development), performance will be limited. For production, run on actual ARM hardware (Raspberry Pi).

### High CPU usage
Check which services are consuming resources:
```bash
docker exec venus-os top -b -n 1
```

Consider disabling unused services via environment variables.
