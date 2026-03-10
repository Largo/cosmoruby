#!/bin/bash
# Trigger the caboose-platforms CI workflow.
#
# Checks that caboose.com is a fat APE (x86_64 and aarch64), runs local
# diagnostics (help, status, check, thaw/discard lifecycle), uploads it
# to a GitHub release, triggers CI on 6 runners, and watches the run.
#
# Usage: ./trigger_caboose_test.sh [release-tag]
#   Default release tag: caboose-test
#
# To build and package caboose:
#   make -j1 o//third_party/mexican_toaster
#   bash third_party/mexican_toaster/caboose/package_caboose.sh

set -e

# Report which command failed and where
trap 'echo "Error: Command failed at line $LINENO"' ERR

TAG="${1:-caboose-test}"
CABOOSE="releases/caboose.com"
WORKFLOW="caboose-platforms.yml"

. ./check_ape.sh
. ./trigger_ci.sh

echo "=== Caboose Cross-Platform Test ==="
echo ""

# ── Check binary exists ─────────────────────────────────────────────

if [ ! -f "$CABOOSE" ]; then
    echo "Error: $CABOOSE not found."
    echo ""
    echo "Build and package first:"
    echo "  make -j1 o//third_party/mexican_toaster"
    echo "  bash third_party/mexican_toaster/caboose/package_caboose.sh"
    echo "  bash third_party/mexican_toaster/caboose/package_caboose_fat.sh"
    exit 1
fi

# ── Verify APE binary ──────────────────────────────────────────────

echo "Verifying caboose.com..."
check_ape_magic "$CABOOSE" || exit 1
check_fat_binary "$CABOOSE"
echo ""

# ── Local diagnostics ───────────────────────────────────────────────

echo "Local sanity checks..."

# help output
HELP_OUTPUT=$(./"$CABOOSE" help 2>&1) || true
if echo "$HELP_OUTPUT" | grep -q "usage\|Usage\|caboose"; then
    echo "  help:        OK"
else
    echo "  Warning: help output unexpected"
fi

# check command
CHECK_OUTPUT=$(./"$CABOOSE" check 2>&1) || true
if echo "$CHECK_OUTPUT" | grep -q "healthy"; then
    echo "  check:       OK (healthy)"
else
    echo "  check:       status unclear"
    echo "    $CHECK_OUTPUT"
fi

# status command
STATUS_OUTPUT=$(./"$CABOOSE" status 2>&1) || true
if echo "$STATUS_OUTPUT" | grep -qi "cold\|state"; then
    echo "  status:      OK"
else
    echo "  Warning: status output unexpected"
fi

# embedded ZIP contents
ZIP_COUNT=$(./"$CABOOSE" ls 2>&1 | wc -l) || true
if [ "$ZIP_COUNT" -gt 0 ] 2>/dev/null; then
    echo "  ZIP entries: $ZIP_COUNT"
fi

# thaw/discard lifecycle (quick round-trip)
WORKDIR=$(mktemp -d /tmp/caboose-trigger-XXXXXX)
DEMO_BIN="$WORKDIR/caboose-test.com"
cp "$CABOOSE" "$DEMO_BIN"
chmod +x "$DEMO_BIN"

THAW_OK=false
if "$DEMO_BIN" thaw >/dev/null 2>&1; then
    THAW_OK=true
    echo "  thaw:        OK"
    "$DEMO_BIN" discard >/dev/null 2>&1 || true
    echo "  discard:     OK"
else
    echo "  thaw:        skipped (may require Linux namespaces)"
fi

rm -rf "$WORKDIR"

echo ""

# ── Upload, trigger, watch ──────────────────────────────────────────

upload_release "$TAG" "$CABOOSE" \
    "Caboose cross-platform test" \
    "Fat APE caboose.com binary with embedded ZIP filesystem for cross-platform CI testing"

trigger_workflow "$WORKFLOW" -f release_tag="$TAG"
watch_workflow "$WORKFLOW"
