#!/bin/bash
# demo_persist_word.sh - Interactive Mexican Toaster demo
#
# Demonstrates: thaw -> web server -> user types a word -> persist -> word is baked in
#
# Usage:
#   bash demo_persist_word.sh          # Run the full demo
#   bash demo_persist_word.sh what BIN # Print the baked-in word
#
set -e

REPO_ROOT="$(git rev-parse --show-toplevel)" || { echo "Error: not inside a git repo"; exit 1; }
BUILD="$REPO_ROOT/o"
CABOOSE_COM="$BUILD/third_party/mexican_toaster/caboose.com"
BAKED_BIN="/tmp/wordapp-baked.com"
PORT="${PORT:-8888}"

run() { echo "  \$ $*"; "$@" 2>&1 | sed 's/^/    /'; }

die() { echo "ERROR: $*" >&2; exit 1; }

# ---------- "what" mode: print the baked-in word ----------
if [ "${1:-}" = "what" ]; then
  TARGET="${2:-$BAKED_BIN}"
  [ -f "$TARGET" ] || die "Binary not found: $TARGET"
  WORD=$("$TARGET" cat app/secret.txt 2>/dev/null) || die "No secret word baked in. Run the demo first!"
  echo "$WORD"
  exit 0
fi

# ---------- Prerequisites ----------
[ -f "$CABOOSE_COM" ] || die "Build first: bin/build_caboose.sh --clean"
command -v ruby.com >/dev/null 2>&1 || die "ruby.com not on PATH"

echo ""
echo "=== Mexican Toaster: Persist a Word ==="
echo ""
echo "  This demo starts a web server with a text box."
echo "  You type a secret word, submit it, and the word gets"
echo "  baked into the binary via persist. Then you can retrieve"
echo "  the word any time from the persisted binary."
echo ""

# ---------- Setup ----------
WORKDIR=$(mktemp -d /tmp/toaster-word-XXXXXX)
DEMO_BIN="$WORKDIR/wordapp.com"
cp "$CABOOSE_COM" "$DEMO_BIN"
chmod +x "$DEMO_BIN"

SERVER_PID=""
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  # Clean up overlay state (discard may fail from persisted state — that's fine)
  "$DEMO_BIN" discard 2>/dev/null || true
  # Remove the state file
  SF=$("$DEMO_BIN" status 2>&1 | grep "State file:" | sed 's/.*State file: *//' || true)
  [ -n "$SF" ] && rm -f "$SF" 2>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# ---------- Phase 1: Thaw ----------
echo ">>> 1. Thaw (make /zip writable)"
run "$DEMO_BIN" thaw

# Get overlay upper path from status
STATUS_OUTPUT=$("$DEMO_BIN" status 2>&1)
UPPER=$(echo "$STATUS_OUTPUT" | grep "Upper layer:" | sed 's/.*Upper layer: *//')
[ -d "$UPPER" ] || die "Upper layer not found: $UPPER"
echo ""

# ---------- Phase 2: Write the web app ----------
echo ">>> 2. Writing web app to overlay"
mkdir -p "$UPPER/app"

cat > "$UPPER/app/server.rb" <<'RUBYEOF'
require 'webrick'
require 'uri'

port = (ARGV[0] || 8888).to_i
secret_path = ARGV[1] or abort "Usage: server.rb PORT SECRET_PATH"

server = WEBrick::HTTPServer.new(
  Port: port,
  Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN),
  AccessLog: []
)

server.mount_proc '/' do |req, res|
  if req.request_method == 'POST'
    params = URI.decode_www_form(req.body || '').to_h
    word = (params['word'] || '').strip
    if word.empty?
      res.status = 302
      res['Location'] = '/'
    else
      File.write(secret_path, word)
      res.content_type = 'text/html'
      res.body = <<~HTML
        <!DOCTYPE html>
        <html>
        <head><title>Baked!</title>
        <style>
          body { font-family: monospace; max-width: 500px; margin: 80px auto; text-align: center; }
          .word { font-size: 2em; color: #d63384; margin: 20px 0; }
        </style></head>
        <body>
          <h1>Word baked in!</h1>
          <div class="word">#{word}</div>
          <p>Server shutting down... return to your terminal.</p>
        </body></html>
      HTML
      Thread.new { sleep 1; server.shutdown }
    end
  else
    res.content_type = 'text/html'
    res.body = <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Mexican Toaster</title>
      <style>
        body { font-family: monospace; max-width: 500px; margin: 80px auto; text-align: center; }
        input[type=text] { font-size: 1.5em; padding: 8px; width: 300px; text-align: center; }
        button { font-size: 1.2em; padding: 8px 24px; margin-top: 12px; cursor: pointer; }
      </style></head>
      <body>
        <h1>Mexican Toaster</h1>
        <p>Type a secret word to bake into the binary:</p>
        <form method="POST">
          <input type="text" name="word" placeholder="your secret word" autofocus><br>
          <button type="submit">Bake it in!</button>
        </form>
      </body></html>
    HTML
  end
end

trap('INT') { server.shutdown }
server.start
RUBYEOF

echo "  Written: $UPPER/app/server.rb"
echo ""

# ---------- Phase 3: Install webrick gem ----------
echo ">>> 3. Installing webrick gem (removed from Ruby 4.0 stdlib)"
GEM_DIR="$UPPER/lib/ruby/gems/4.0.0"
run ruby.com -S gem install webrick --install-dir "$GEM_DIR" --no-document
WEBRICK_LIB=$(find "$GEM_DIR/gems" -maxdepth 2 -name lib -path '*/webrick-*/lib' 2>/dev/null | head -1)
[ -d "$WEBRICK_LIB" ] || die "webrick gem lib not found"
echo ""

# ---------- Phase 4: Start the web server ----------
SECRET_PATH="$UPPER/app/secret.txt"

echo ">>> 4. Starting web server on http://localhost:$PORT"
echo ""
echo "  Open your browser and type a word!"
echo "  (or use: curl -d 'word=hello' http://localhost:$PORT)"
echo ""

ruby.com -I "$WEBRICK_LIB" "$UPPER/app/server.rb" "$PORT" "$SECRET_PATH" &
SERVER_PID=$!

# Wait for server to start
sleep 1
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  die "Server failed to start"
fi

# Wait for user to submit (server shuts itself down after POST)
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

# Check the word was saved
if [ ! -f "$SECRET_PATH" ]; then
  die "No word was submitted"
fi

WORD=$(cat "$SECRET_PATH")
echo ""
echo ">>> 5. Word received: $WORD"
echo ""

# ---------- Phase 5: Persist ----------
echo ">>> 6. Persist (bake the word into the binary)"
PERSIST_OUTPUT=$("$DEMO_BIN" persist 2>&1)
echo "$PERSIST_OUTPUT" | sed 's/^/    /'
echo ""

# After atomic rename, DEMO_BIN is the persisted binary
[ -f "$DEMO_BIN" ] || die "Persisted binary not found"

echo ">>> 7. Verify: read the baked-in word from the persisted binary"
echo ""
echo "  \$ $DEMO_BIN cat app/secret.txt"
RESULT=$("$DEMO_BIN" cat app/secret.txt 2>/dev/null) || die "Failed to read secret"
echo "    $RESULT"
echo ""

if [ "$RESULT" = "$WORD" ]; then
  # Copy persisted binary to a stable location before cleanup removes WORKDIR
  cp "$DEMO_BIN" "$BAKED_BIN"
  chmod +x "$BAKED_BIN"

  echo "  The word survived! It's baked into the binary."
  echo ""
  echo "  Saved to: $BAKED_BIN"
  echo ""
  echo "  Try it:"
  echo "    $BAKED_BIN cat app/secret.txt"
  echo "    bash $0 what $BAKED_BIN"
else
  echo "  ERROR: expected '$WORD' but got '$RESULT'"
  exit 1
fi
