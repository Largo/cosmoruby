#!/bin/sh
set -e
set -x

# Normalise to the repository root so relative o// paths work from any caller.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$SCRIPT_DIR")"

(
	cd "$REPO_ROOT"
	ruby.com -e 'puts $LOAD_PATH'
	o//third_party/ruby/ruby.zipless -e 'puts $LOAD_PATH'
	o//third_party/ruby/miniruby -e 'puts $LOAD_PATH'
	o//third_party/ruby/miniruby.zipless -e 'puts $LOAD_PATH'
)
