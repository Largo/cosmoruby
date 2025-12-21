#!/usr/bin/env bash
# CosmoRuby configuration shim: toggles static vs plugin (.a) extensions.
# Usage: cosmo_configure.sh [--with-static-linked-ext] [--with-plugin-ext]
# Defaults to plugin mode (dynamic load via cosmo_plugin).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RBCONFIG="$ROOT/third_party/ruby/lib/rbconfig.rb"
CONFIG_H="$ROOT/third_party/ruby/include/ruby/config.h"
MODE="plugin" # default
BOOTSTRAP=false

for arg in "$@"; do
  case "$arg" in
    --with-static-linked-ext) MODE="static" ;;
    --with-plugin-ext) MODE="plugin" ;;
    --bootstrap) BOOTSTRAP=true ;;
    -h|--help)
      cat <<EOF
CosmoRuby configure shim
  --with-static-linked-ext   keep extensions linked into ruby.a (EXTSTATIC=1, DLEXT=.so)
  --with-plugin-ext          use cosmo_plugin-loaded .a extensions (EXTSTATIC=0, DLEXT=.a) [default]
  --bootstrap                build/copy automate_mkdeps + mtdeps into build/bootstrap
EOF
      exit 0
      ;;
    *)
      echo "warning: ignoring unsupported option '$arg'" >&2
      ;;
  esac
done

if [[ ! -f "$RBCONFIG" || ! -f "$CONFIG_H" ]]; then
  echo "cosmo_configure: missing rbconfig.rb or config.h" >&2
  exit 1
fi

RUBY_BIN="${HOST_RUBY:-ruby}"
export RUBYOPT=--disable-gems

MODE_UPPER=$(printf '%s' "$MODE" | tr a-z A-Z)
echo "cosmo_configure: MODE=${MODE} (using $RUBY_BIN)"

"$BOOTSTRAP" && {
  STUB="$ROOT/build/bootstrap/mkdeps_stub.sh"
  if [[ ! -x "$STUB" ]]; then
    echo "cosmo_configure: missing mkdeps stub at $STUB" >&2
    exit 1
  fi
  echo "cosmo_configure: building automate_mkdeps + mtdeps with stub mkdeps"
  make -C "$ROOT" MKDEPS="$STUB" -j1 o//third_party/mexican_toaster/automate_mkdeps
  make -C "$ROOT" MKDEPS="$STUB" -j1 o//third_party/mexican_toaster/mtdeps
  mkdir -p "$ROOT/build/bootstrap"
  cp "$ROOT/o//third_party/mexican_toaster/automate_mkdeps" "$ROOT/build/bootstrap/automate_mkdeps"
  cp "$ROOT/o//third_party/mexican_toaster/mtdeps" "$ROOT/build/bootstrap/mtdeps"
  echo "cosmo_configure: bootstrap copies placed in build/bootstrap/"
}

"$RUBY_BIN" - "$RBCONFIG" "$CONFIG_H" "$MODE" <<'RUBY'
rbconfig, configh, mode = ARGV.map { |p| p }
rbconfig = File.realpath(rbconfig)
configh = File.realpath(configh)

def rewrite(path)
  text = File.read(path)
  new = yield(text)
  return false if new == text
  File.write(path, new)
  true
end

plugin_mode = mode == "plugin"

changed = false

changed |= rewrite(rbconfig) do |t|
  dlextext = plugin_mode ? "a" : "so"
  t = t.sub(/CONFIG\["DLEXT"\]\s*=\s*".*?"/, "CONFIG[\"DLEXT\"] = \"#{dlextext}\"")
  t = t.sub(/'--with-static-linked-ext'\s*/, "") if plugin_mode
  extstatic = plugin_mode ? "no" : "yes"
  if t !~ /CONFIG\["EXTSTATIC"\]/
    t = t.sub(/^  CONFIG\["DLEXT"\].*\n/, "\\0  CONFIG[\"EXTSTATIC\"] = \"#{extstatic}\"\n")
  else
    t = t.sub(/CONFIG\["EXTSTATIC"\]\s*=\s*".*?"/, "CONFIG[\"EXTSTATIC\"] = \"#{extstatic}\"")
  end
  t
end

changed |= rewrite(configh) do |t|
  if plugin_mode
    t = t.sub(/#define\s+EXTSTATIC\s+\d+/, "#define EXTSTATIC 0")
    t = t.sub(/#define\s+DLEXT_MAXLEN\s+\d+/, "#define DLEXT_MAXLEN 2")
    t = t.sub(/#define\s+DLEXT\s+\".*?\"/, '#define DLEXT ".a"')
    t = t.sub(/#define\s+SOEXT\s+\".*?\"/,  '#define SOEXT ".a"')
  else
    t = t.sub(/#define\s+EXTSTATIC\s+\d+/, "#define EXTSTATIC 1")
    t = t.sub(/#define\s+DLEXT_MAXLEN\s+\d+/, "#define DLEXT_MAXLEN 3")
    t = t.sub(/#define\s+DLEXT\s+\".*?\"/, '#define DLEXT ".so"')
    t = t.sub(/#define\s+SOEXT\s+\".*?\"/,  '#define SOEXT ".so"')
  end
  t
end

puts changed ? "cosmo_configure: updated configs for #{mode} mode" : "cosmo_configure: no changes (mode=#{mode})"
RUBY
