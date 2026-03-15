#!/bin/bash
# Fat APE smoke test.
#
# Checks that a binary is a fat APE (both x86_64 and aarch64),
# uploads it to a GitHub release, triggers CI on 6 runners, and watches
# the workflow run with live output.
#
# Usage: ./fat_smoke_test.sh [binary] [release-tag]
#   Default binary: releases/hello.com
#   Default release tag: fat-smoke-test
#
# Examples:
#   ./fat_smoke_test.sh /path/to/the/binary
#   ./fat_smoke_test.sh /path/to/the/ninary my-tag
#   ./fat_smoke_test.sh

set -e

# Report which command failed and where
trap 'echo "Error: Command failed at line $LINENO"' ERR

BINARY="${1:-releases/hello.com}"
TAG="${2:-fat-smoke-test}"
WORKFLOW="cosmo-ci-fat-smoke-test.yml"

. ./check_ape.sh
. ./trigger_ci.sh

echo "=== Fat APE Smoke Test ==="
echo ""

# ── Check binary exists ──────────────────────────────────────────────

if [ ! -f "$BINARY" ]; then
    echo "Error: $BINARY not found."
    echo ""
    echo "Build a fat binary first, e.g.:"
    echo "  third_party/wrapper/ccc -o /tmp/hello examples/hello.c"
    echo "  or"
    echo "  ./bake o//examples/hello"
    exit 1
fi

# ── Verify APE binary ───────────────────────────────────────────────

check_ape_magic "$BINARY" || exit 1
check_fat_binary "$BINARY"
check_ape_components "$BINARY" || exit 1

# ── Quick local sanity check ────────────────────────────────────────

if ./"$BINARY" >/dev/null 2>&1; then
    echo "Local run:   OK (exit 0)"
else
    echo "Warning: local run exited with code $?"
    echo "Continuing anyway (might work on other platforms)."
fi

echo ""

# ── Upload, trigger, watch ──────────────────────────────────────────

upload_release "$TAG" "$BINARY" \
    "Phase 0 fat smoke test" \
    "APE fat binary for cross-platform testing"

trigger_workflow "$WORKFLOW"
watch_workflow "$WORKFLOW"
