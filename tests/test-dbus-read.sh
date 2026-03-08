#!/usr/bin/env bash
# test-dbus-read.sh — Verify we can read values from D-Bus.
# SPDX-License-Identifier: GPL-3.0-or-later

CONTAINER="$1"

# Try to read a D-Bus value — localsettings should expose settings
RESULT=$(docker exec "$CONTAINER" dbus-send --print-reply --system \
    --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus \
    org.freedesktop.DBus.ListNames 2>&1)

if [[ $? -ne 0 ]]; then
    echo "Failed to query D-Bus: $RESULT"
    exit 1
fi

# Check that Victron services are registered on D-Bus
if echo "$RESULT" | grep -q "com.victronenergy"; then
    VICTRON_SERVICES=$(echo "$RESULT" | grep -c "com.victronenergy")
    echo "D-Bus is readable. Found $VICTRON_SERVICES Victron service(s) on the bus."
else
    echo "D-Bus is readable but no Victron services registered yet."
    echo "This may be normal during early startup."
    echo "Registered names: $(echo "$RESULT" | grep -c 'string "')"
    # Don't fail — services may still be starting
fi
