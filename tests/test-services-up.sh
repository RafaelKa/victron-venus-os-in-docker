#!/usr/bin/env bash
# test-services-up.sh — Verify key Venus services are supervised and running.
# SPDX-License-Identifier: GPL-3.0-or-later

CONTAINER="$1"

FAILED=0

check_service() {
    local svc="$1"
    local required="${2:-true}"

    STATUS=$(docker exec "$CONTAINER" svstat "/service/$svc" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        if [[ "$required" == "true" ]]; then
            echo "  FAIL: $svc — not found in /service"
            FAILED=$((FAILED + 1))
        fi
        return
    fi

    if echo "$STATUS" | grep -q "^/service/$svc: up"; then
        echo "  OK:   $svc — $(echo "$STATUS" | sed 's|/service/[^ ]* ||')"
    elif echo "$STATUS" | grep -q "down"; then
        echo "  DOWN: $svc (intentionally disabled)"
    else
        if [[ "$required" == "true" ]]; then
            echo "  FAIL: $svc — $STATUS"
            FAILED=$((FAILED + 1))
        else
            echo "  WARN: $svc — $STATUS"
        fi
    fi
}

echo "Checking key services..."

# Core services that must be running
check_service "localsettings" true
check_service "dbus-systemcalc-py" true

# Important but may take time to start
check_service "dbus-mqtt" false
check_service "flashmq" false
check_service "nginx" false
check_service "venus-access" false

if [[ $FAILED -gt 0 ]]; then
    echo "$FAILED required services failed."
    exit 1
fi

echo "All required services are supervised."
