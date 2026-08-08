#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TARGET_RUBY="${TARGET_RUBY:-${ROOT}/o/third_party/ruby/ruby.zipless}"
PLUGIN_PATH="${COSMO_RUBY_PLUGIN_PATH:-${ROOT}/o/third_party/ruby/ext}"
RUBYOPT="${RUBYOPT:---disable-gems}"

if [ ! -x "$TARGET_RUBY" ]; then
  echo "missing target ruby: $TARGET_RUBY (build o//third_party/ruby/ruby.zipless)" >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

export COSMO_RUBY_PLUGIN_PATH="$PLUGIN_PATH"
export RUBYOPT

check_one() {
  feature="$1"
  printf 'checking %s... ' "$feature"
  : >"$tmp"
  if "$TARGET_RUBY" --disable-gems -e "require \"${feature}\"; puts \"ok\"" 2>"$tmp"; then
    echo "ok"
    return 0
  fi
  echo "fail"
  if [ -s "$tmp" ]; then
    cat "$tmp" >&2
  fi
  exit 1
}

check_one monitor
check_one pathname
check_one stringio
check_one socket
check_one io/console
check_one io/wait
check_one ripper
