#!/bin/sh
# CosmoRuby Cross-Platform Diagnostic Runner
#
# Tiny shell wrapper -- transfer these three files to any machine/VM:
#   - ruby.com
#   - platform_diagnostic.rb
#   - run_platform_diagnostic.sh
#
# Usage: ./run_platform_diagnostic.sh [path/to/ruby.com] [options]
#
# Options (passed through to platform_diagnostic.rb):
#   --json          Output JSON instead of human-readable
#   --no-network    Skip network tests
#   --verbose       Verbose output on failure
#   --strict        Treat expected failures as actual failures
#   --timeout SECS  Override default timeout
#   --retry N       Override retry count
#   --help          Show this help
#
# Environment:
#   RUBYFLAGS       Additional flags passed to ruby.com
#   TIMEOUT         Default timeout for test sections (default: 30)
#   RUBY_BIN        Override path to ruby.com

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Find ruby.com ────────────────────────────────────────────────────

if [ -n "$RUBY_BIN" ]; then
    RUBY="$RUBY_BIN"
elif [ -n "$1" ] && [ -f "$1" ]; then
    RUBY="$1"
    shift
elif [ -f "$SCRIPT_DIR/ruby.com" ]; then
    RUBY="$SCRIPT_DIR/ruby.com"
elif [ -f "./ruby.com" ]; then
    RUBY="./ruby.com"
elif command -v ruby.com >/dev/null 2>&1; then
    RUBY="$(command -v ruby.com)"
else
    echo "Error: Cannot find ruby.com"
    echo ""
    echo "Usage: $0 [path/to/ruby.com] [options]"
    echo ""
    echo "Provide path as first argument, set RUBY_BIN, or place"
    echo "ruby.com in the same directory as this script."
    exit 1
fi

# ── Find platform_diagnostic.rb ─────────────────────────────────────

DIAG="$SCRIPT_DIR/platform_diagnostic.rb"
if [ ! -f "$DIAG" ]; then
    echo "Error: Cannot find platform_diagnostic.rb"
    echo "Expected at: $DIAG"
    exit 1
fi

# ── Validate ruby.com is executable ─────────────────────────────────

if [ ! -x "$RUBY" ]; then
    # Try making it executable (might be copied without +x)
    chmod +x "$RUBY" 2>/dev/null || true
    if [ ! -x "$RUBY" ]; then
        echo "Error: $RUBY is not executable and chmod failed"
        exit 1
    fi
fi

# ── Show info ────────────────────────────────────────────────────────

echo "CosmoRuby Platform Diagnostic Runner"
echo "Ruby binary: $RUBY"

# Quick sanity check
VERSION=$("$RUBY" --disable-gems -e 'puts RUBY_VERSION' 2>/dev/null) || true
if [ -n "$VERSION" ]; then
    echo "Ruby version: $VERSION"
else
    echo "Warning: could not determine Ruby version"
fi
echo ""

# ── Run diagnostic ───────────────────────────────────────────────────

# shellcheck disable=SC2086
exec "$RUBY" --disable-gems $RUBYFLAGS "$DIAG" "$@"
