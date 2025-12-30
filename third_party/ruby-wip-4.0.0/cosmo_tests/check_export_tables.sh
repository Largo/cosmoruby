#!/bin/sh
set -eu

MODE="${MODE:-}"
O="o/${MODE}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="${ROOT}/cosmo_tests/check_export_table.rb"
HOST_RUBY="${HOST_RUBY:-ruby}"
RUBYOPT="${RUBYOPT:---disable-gems}"

check_target() {
  name="$1"
  dbg="${O}/third_party/ruby/${name}.dbg"
  exports="${O}/third_party/ruby/${name}_exports.c"
  if [ ! -f "$dbg" ]; then
    echo "missing ${dbg} (build o//third_party/ruby/${name})" >&2
    exit 1
  fi
  if [ ! -f "$exports" ]; then
    echo "missing ${exports} (build o//third_party/ruby/${name})" >&2
    exit 1
  fi
  "$HOST_RUBY" --disable-gems "$CHECK" --label "$name" "$dbg" "$exports"
}

check_target ruby
check_target irb
check_target miniruby
