#!/bin/sh
set -eu

HOST_RUBY="${HOST_RUBY:-ruby}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${ROOT}/third_party/ruby-wip-4.0.6"
# MINIRUBY="/third_party/ruby/miniruby.zipless"
MINIRUBY="/third_party/ruby/miniruby"
TARGET_RUBY="${TARGET_RUBY:-${ROOT}/o/${MINIRUBY}}"

if [ ! -x "$TARGET_RUBY" ]; then
  echo "missing target ruby: $TARGET_RUBY (build o/${MINIRUBY})" >&2
  exit 1
fi

export COSMO_RUBY_PLUGIN_PATH="${COSMO_RUBY_PLUGIN_PATH:-${ROOT}/o/third_party/ruby/ext}"
export RUBYOPT="${RUBYOPT:---disable-gems}"
export RUBYLIB="${SRC}/lib:${SRC}/ext/monitor/lib"

exec "$HOST_RUBY" "${SRC}/bootstraptest/runner.rb" \
  --ruby="${TARGET_RUBY}" \
  "$@"
