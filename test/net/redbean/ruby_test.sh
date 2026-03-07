#!/bin/bash
# Test Ruby/Rack integration in redbean
# Usage: ./ruby_test.sh
# Prerequisite: make -j1 o//tool/net/redbean

set -euo pipefail

# Resolve repo root (works regardless of where the script lives)
REPO_ROOT="$(git rev-parse --show-toplevel)" || { echo "Error: not inside a git repo"; exit 1; }

REDBEAN="$REPO_ROOT/o/tool/net/redbean"
PORT=8080
TMPDIR=$(mktemp -d)
TESTBEAN="$TMPDIR/test-redbean.com"

cleanup() {
  if [[ -n "${REDBEAN_PID:-}" ]]; then
    kill "$REDBEAN_PID" 2>/dev/null || true
    wait "$REDBEAN_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# --- Step 1: Copy redbean ---
if [[ ! -f "$REDBEAN" ]]; then
  echo "ERROR: $REDBEAN not found. Build it first:"
  echo "  make -j1 o//tool/net/redbean"
  exit 1
fi
cp "$REDBEAN" "$TESTBEAN"
echo "[1/4] Copied redbean to $TESTBEAN"

# --- Step 2: Create Rack app ---
mkdir -p "$TMPDIR/app"
cat > "$TMPDIR/app/hello.rb" <<'RUBY'
lambda do |env|
  [200, {"Content-Type" => "text/plain"}, ["Hello from Ruby in redbean!\n"]]
end
RUBY

cat > "$TMPDIR/app/.init.rb" <<'RUBY'
# This runs at server startup
$stderr.puts "[.init.rb] Ruby initialised in redbean"
RUBY
echo "[2/4] Created test Rack app and .init.rb"

# --- Step 3: Add files to existing ZIP ---
# Use zip -j to add directly into the binary's existing zip filesystem.
# Don't cat+zip -A, as that replaces the central directory and loses
# the embedded SSL root certs and other built-in assets.
(cd "$TMPDIR/app" && zip "$TESTBEAN" .init.rb hello.rb)
echo "[3/4] Added Rack app to redbean ZIP"

# --- Step 4: Run and test ---
echo "[4/4] Starting redbean on port $PORT..."
"$TESTBEAN" -p "$PORT" -v &
REDBEAN_PID=$!
sleep 2

echo ""
echo "--- Requesting /hello.rb ---"
RESPONSE=$(curl -s http://localhost:$PORT/hello.rb)
echo "Response: $RESPONSE"
echo ""

if [[ "$RESPONSE" == *"Hello from Ruby"* ]]; then
  echo "PASS: Ruby Rack integration is working"
else
  echo "FAIL: Unexpected response (might still be useful to inspect)"
fi

echo ""
echo "Shutting down redbean (PID $REDBEAN_PID)..."
