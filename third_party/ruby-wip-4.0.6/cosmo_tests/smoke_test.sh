#!/bin/sh
# Smoke tests for a freshly packaged ruby.com, on Linux/macOS/BSD.
#
#   sh third_party/ruby/cosmo_tests/smoke_test.sh o/third_party/ruby/ruby.com
#
# 14 checks: APE magic, interpreter identity, the statically linked C
# extensions users actually reach for, a real loopback socket round-trip,
# threads, YJIT, RubyGems, and a run under `env -i` from an empty directory
# (which is what proves the stdlib really is embedded in the binary).
# Exits non-zero if any check fails.
#
# This is NOT sufficient on its own -- see win_smoke.sh.  A build that passed
# all 14 checks here has crashed on 100% of Windows runs before.
set -u
RUBY="$1"
pass=0; fail=0
t() {
  desc="$1"; shift
  if out=$("$@" 2>&1); then
    echo "PASS: $desc :: $out" | head -2; pass=$((pass+1))
  else
    echo "FAIL: $desc :: $out" | head -5; fail=$((fail+1))
  fi
}
echo "== APE magic =="
head -c 6 "$RUBY"; echo ""
t "version" "$RUBY" --version
t "RUBY_VERSION/PLATFORM" "$RUBY" -e 'puts RUBY_VERSION; puts RUBY_PLATFORM'
t "json" "$RUBY" -e 'require "json"; puts JSON.generate({ok: true})'
t "digest" "$RUBY" -e 'require "digest"; puts Digest::SHA256.hexdigest("x")[0,8]'
t "zlib" "$RUBY" -e 'require "zlib"; puts Zlib::Deflate.deflate("hello").bytesize'
t "yaml" "$RUBY" -e 'require "yaml"; puts YAML.load("a: 1")["a"]'
t "stringio" "$RUBY" -e 'require "stringio"; s=StringIO.new; s<<"hi"; puts s.string'
t "socket-echo" "$RUBY" -e 'require "socket"; s=TCPServer.new("127.0.0.1",0); p=s.addr[1]; th=Thread.new{c=s.accept; c.write(c.gets); c.close}; c=TCPSocket.new("127.0.0.1",p); c.puts("ping"); puts c.gets; th.join'
t "threads" "$RUBY" -e 'puts 4.times.map{|i| Thread.new{i*i}}.map(&:value).sum'
# --yjit must be *accepted* on every platform.  It used to raise
# "invalid YJIT option ''" on the aarch64 half of a fat APE, where the YJIT
# Rust staticlib is not linked at all and the weak C stub answered "no such
# option".  Whether YJIT actually *runs* is a separate question -- only on
# Linux/x86_64 -- so assert RubyVM::YJIT.enabled?, not the +YJIT string in
# RUBY_DESCRIPTION, which is set by option parsing and is inert on Windows
# and on aarch64.
# The expectation is computed *inside* the interpreter (RUBY_PLATFORM plus
# Etc.uname) rather than from the shell's `uname`, so it is also right when
# the aarch64 half is being exercised through qemu-user on an x86-64 host.
t "yjit" "$RUBY" --yjit -e '
  require "etc"
  want = RUBY_PLATFORM.start_with?("x86_64") &&
         (Etc.uname[:sysname] rescue "") == "Linux"
  got  = RubyVM::YJIT.enabled?
  raise "RubyVM::YJIT.enabled? expected #{want}, got #{got}" if want != got
  puts "yjit accepted, enabled=#{got} :: #{RUBY_DESCRIPTION}"'
t "gem" "$RUBY" -S gem --version
t "gem-preloaded" "$RUBY" -e 'raise "Gem not preloaded" unless defined?(Gem); puts Gem.default_dir'
t "gem-spec-list" "$RUBY" -e 'puts Gem::Specification.map(&:name).uniq.sort.first(3).join(",")'
echo "== env -i from empty dir =="
mkdir -p /tmp/emptydir-smoke && cd /tmp/emptydir-smoke
t "env-i" env -i "$RUBY" -e 'puts "env-i-ok #{RUBY_VERSION}"'
echo "== RESULT: pass=$pass fail=$fail =="
[ "$fail" -eq 0 ]
