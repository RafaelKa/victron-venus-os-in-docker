#!/usr/bin/env bash
# test-dbus-running.sh — Verify D-Bus system daemon is running.
# SPDX-License-Identifier: GPL-3.0-or-later

CONTAINER="$1"

# Check D-Bus socket exists (most reliable check — works under QEMU too)
docker exec "$CONTAINER" test -S /var/run/dbus/system_bus_socket
if [[ $? -ne 0 ]]; then
    echo "D-Bus socket does not exist at /var/run/dbus/system_bus_socket"
    exit 1
fi

# Verify D-Bus is functional by querying it
RESULT=$(docker exec "$CONTAINER" dbus-send --print-reply --system \
    --dest=org.freedesktop.DBus \
    / org.freedesktop.DBus.GetId 2>&1)
if [[ $? -ne 0 ]]; then
    echo "D-Bus socket exists but daemon is not responding: $RESULT"
    exit 1
fi

echo "D-Bus is running, socket available and responding."
