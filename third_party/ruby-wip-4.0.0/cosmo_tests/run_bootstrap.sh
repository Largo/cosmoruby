#!/bin/sh
set -eu

HOST_RUBY="${HOST_RUBY:-ruby}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="${ROOT}/third_party/ruby-wip-3.4.7"
TARGET_RUBY="${TARGET_RUBY:-${ROOT}/o/third_party/ruby/miniruby.zipless}"

if [ ! -x "$TARGET_RUBY" ]; then
  echo "missing target ruby: $TARGET_RUBY (build o//third_party/ruby/miniruby.zipless)" >&2
  exit 1
fi

export COSMO_RUBY_PLUGIN_PATH="${COSMO_RUBY_PLUGIN_PATH:-${ROOT}/o/third_party/ruby/ext}"
export RUBYOPT="${RUBYOPT:---disable-gems}"

exec "$HOST_RUBY" "${SRC}/bootstraptest/runner.rb" \
  --ruby="${TARGET_RUBY} -I${SRC}/lib -I${SRC}/ext/monitor/lib" \
  "$@"
