#!/bin/bash
# Package CosmoRuby with embedded stdlib
#
# Assembles the Ruby standard library into a ZIP, then embeds it into
# all available APE binaries (fat binaries in releases/ and single-arch
# dev binaries in o//).
#
# Usage: package_ruby.sh [RUBY_BINARY]
#   RUBY_BINARY  Path to Ruby interpreter for gemspec generation
#                 (defaults to <repo>/o/third_party/ruby/ruby)
#
# For finer control, call the sub-scripts directly:
#   assemble_stdlib.sh [RUBY_BINARY]   -- build o/ruby-stdlib.zip
#   embed_stdlib.sh <binary> [zip]     -- embed ZIP into one binary

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."

# Pass through RUBY_BIN argument (assemble_stdlib.sh handles the default)
RUBY_BIN="${1:-}"

# ── Step 1: Assemble stdlib ZIP ──────────────────────────────────────

if [ -n "$RUBY_BIN" ]; then
  "$SCRIPT_DIR/assemble_stdlib.sh" "$RUBY_BIN"
else
  "$SCRIPT_DIR/assemble_stdlib.sh"
fi

# ── Step 2: Embed into fat binaries (releases/) ─────────────────────

for bin in ruby.com irb.com miniruby.com; do
  if [ -f "$REPO_ROOT/releases/$bin" ]; then
    "$SCRIPT_DIR/embed_stdlib.sh" "$REPO_ROOT/releases/$bin"
  fi
done

# ── Step 3: Embed into single-arch dev binaries (o//) ────────────────

for bin in ruby irb miniruby; do
  src="$REPO_ROOT/o/third_party/ruby/$bin"
  if [ -f "$src" ]; then
    dst="${src}.com"
    cp "$src" "$dst"
    "$SCRIPT_DIR/embed_stdlib.sh" "$dst"
  fi
done
