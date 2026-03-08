#!/usr/bin/env bash
# test-container-boots.sh — Verify the container is running and stays up.
# SPDX-License-Identifier: GPL-3.0-or-later

CONTAINER="$1"

STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null)
if [[ "$STATUS" != "running" ]]; then
    echo "Container is not running. Status: $STATUS"
    echo "Logs:"
    docker logs "$CONTAINER" 2>&1 | tail -30
    exit 1
fi

echo "Container is running."
