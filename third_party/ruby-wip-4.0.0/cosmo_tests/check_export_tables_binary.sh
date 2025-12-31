#!/bin/sh
set -eu

MODE="${MODE:-}"
O="o/${MODE}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CHECK="${ROOT}/third_party/ruby-wip-4.0.0/cosmo_tests/check_export_table_binary.rb"
HOST_RUBY="${HOST_RUBY:-ruby}"
RUBYOPT="${RUBYOPT:---disable-gems}"

check_target() {
  name="$1"
  dbg="${O}/third_party/ruby/${name}.dbg"
  if [ ! -f "$dbg" ]; then
    echo "missing ${dbg} (build o//third_party/ruby/${name})" >&2
    exit 1
  fi
  "$HOST_RUBY" --disable-gems "$CHECK" --label "$name" "$dbg"
}

check_target ruby
check_target irb
check_target miniruby
