#!/usr/bin/env bash
# run-all-tests.sh — Run all tests against a running Venus OS Docker container.
#
# Usage: ./run-all-tests.sh [CONTAINER_NAME_OR_ID]
#
# If no container name is given, starts a new container from the default image,
# runs all tests, and stops it.
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# Source common for image naming — but disable errexit since test failures are expected
. "$PROJECT_ROOT/scripts/common.sh" 2>/dev/null || true
set +e

CONTAINER="${1:-}"
STARTED_CONTAINER=0
PASSED=0
FAILED=0
ERRORS=""

# ── Colors ─────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ── Container management ──────────────────────────────────────────────────────

if [[ -z "$CONTAINER" ]]; then
    CONTAINER="venus-os-test-$$"
    IMAGE="${IMAGE_REGISTRY:-ghcr.io}/${IMAGE_OWNER:-rafaelka}/${IMAGE_NAME:-venus-os}:latest-${MACHINE:-raspberrypi5}"

    echo "Starting test container: $CONTAINER (image: $IMAGE)"
    docker run -d --name "$CONTAINER" --privileged "$IMAGE" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}FATAL: Could not start container from image $IMAGE${NC}"
        exit 1
    fi
    STARTED_CONTAINER=1

    # Give Venus OS time to boot
    echo "Waiting for Venus OS to initialize (15s)..."
    sleep 15
fi

# ── Test runner ────────────────────────────────────────────────────────────────

run_test() {
    local test_script="$1"
    local test_name
    test_name="$(basename "$test_script" .sh)"

    printf "  %-40s " "$test_name"

    # Run test in background with a timeout.
    # docker exec can orphan processes that hold pipes open, so we avoid $() capture.
    local tmpfile
    tmpfile=$(mktemp)
    bash "$test_script" "$CONTAINER" > "$tmpfile" 2>&1 &
    local test_pid=$!

    # Wait up to 30 seconds
    local waited=0
    while kill -0 "$test_pid" 2>/dev/null && [[ $waited -lt 30 ]]; do
        sleep 1
        waited=$((waited + 1))
    done

    if kill -0 "$test_pid" 2>/dev/null; then
        # Test timed out — kill it and any children
        kill "$test_pid" 2>/dev/null
        sleep 1
        kill -9 "$test_pid" 2>/dev/null
        wait "$test_pid" 2>/dev/null
        EXIT_CODE=124
        OUTPUT="Test timed out after 30 seconds"
    else
        wait "$test_pid"
        EXIT_CODE=$?
        OUTPUT=$(cat "$tmpfile")
    fi
    rm -f "$tmpfile"

    if [[ $EXIT_CODE -eq 0 ]]; then
        echo -e "${GREEN}PASS${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        FAILED=$((FAILED + 1))
        ERRORS="${ERRORS}\n--- ${test_name} ---\n${OUTPUT}\n"
    fi
}

# ── Run tests ──────────────────────────────────────────────────────────────────

echo ""
echo "Running tests against container: $CONTAINER"
echo "════════════════════════════════════════════════════"

for test_file in "$TESTS_DIR"/test-*.sh; do
    [[ -f "$test_file" ]] || continue
    run_test "$test_file"
done

# ── Summary ────────────────────────────────────────────────────────────────────

TOTAL=$((PASSED + FAILED))
echo "════════════════════════════════════════════════════"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All $TOTAL tests passed.${NC}"
else
    echo -e "${RED}$FAILED of $TOTAL tests failed.${NC}"
    echo -e "\nFailure details:${ERRORS}"
fi

# ── Cleanup ────────────────────────────────────────────────────────────────────

if [[ $STARTED_CONTAINER -eq 1 ]]; then
    echo ""
    echo "Stopping and removing test container..."
    docker stop "$CONTAINER" >/dev/null 2>&1
    docker rm "$CONTAINER" >/dev/null 2>&1
fi

# Exit with failure if any test failed
[[ $FAILED -eq 0 ]]
