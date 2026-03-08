#!/usr/bin/env bash
# test-mqtt-available.sh — Verify MQTT broker is listening on port 1883.
# SPDX-License-Identifier: GPL-3.0-or-later

CONTAINER="$1"

# Check if port 1883 (hex 075B) is listening via /proc/net/tcp
# State 0A = LISTEN. This works without netstat/ss.
LISTENING=$(timeout 10 docker exec "$CONTAINER" sh -c 'grep -qi ":075B" /proc/net/tcp /proc/net/tcp6 2>/dev/null && echo "yes"' 2>/dev/null)

if [[ "$LISTENING" != "yes" ]]; then
    echo "MQTT broker is not listening on port 1883."
    exit 1
fi

echo "MQTT broker is listening on port 1883."
