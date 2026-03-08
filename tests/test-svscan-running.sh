#!/usr/bin/env bash
# test-svscan-running.sh — Verify svscan (daemontools supervisor) is running.
# SPDX-License-Identifier: GPL-3.0-or-later

CONTAINER="$1"

# Check /service directory has entries
SERVICE_COUNT=$(docker exec "$CONTAINER" sh -c 'ls -d /service/*/ 2>/dev/null | wc -l')
if [[ "$SERVICE_COUNT" -eq 0 ]]; then
    echo "No services found in /service."
    exit 1
fi

# Verify svscan is functional by checking that svstat works.
# This is more reliable than pidof which fails under QEMU emulation
# (PID 1 shows as "qemu-aarch64 svscan" instead of "svscan").
SVSTAT=$(docker exec "$CONTAINER" svstat /service/localsettings 2>&1)
if ! echo "$SVSTAT" | grep -q "up\|down"; then
    echo "svscan does not appear to be running (svstat failed): $SVSTAT"
    exit 1
fi

echo "svscan is running, supervising $SERVICE_COUNT services."
