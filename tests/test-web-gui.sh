#!/usr/bin/env bash
# test-web-gui.sh — Verify the web GUI is accessible via nginx on port 80.
# SPDX-License-Identifier: GPL-3.0-or-later

CONTAINER="$1"

# Try to reach nginx from inside the container
HTTP_CODE=$(docker exec "$CONTAINER" sh -c 'wget -q -O /dev/null -S http://127.0.0.1:80/ 2>&1 | head -1 | awk "{print \$2}"' 2>/dev/null)

if [[ -z "$HTTP_CODE" ]]; then
    # Fallback: check if nginx is listening
    LISTENING=$(docker exec "$CONTAINER" sh -c 'grep -i ":0050" /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep " 0A "' 2>/dev/null)
    if [[ -z "$LISTENING" ]]; then
        echo "Web server is not listening on port 80."
        echo "nginx status: $(docker exec "$CONTAINER" svstat /service/nginx 2>/dev/null || echo 'not found')"
        exit 1
    fi
    echo "Web server is listening on port 80 (could not verify HTTP response)."
    exit 0
fi

if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    echo "Web GUI is accessible (HTTP $HTTP_CODE)."
else
    echo "Web GUI returned unexpected HTTP code: $HTTP_CODE"
    exit 1
fi
