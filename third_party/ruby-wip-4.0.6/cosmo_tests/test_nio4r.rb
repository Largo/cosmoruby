# frozen_string_literal: true
#
# CosmoRuby nio4r test.
#
#   ruby.com third_party/ruby/cosmo_tests/test_nio4r.rb
#
# Exercises the statically linked nio4r 2.7.5 extension (libev, poll(2)
# backend -- see ext/nio4r/BUILD.mk for why poll and not epoll/kqueue):
# NIO::Selector register/deregister/select/wakeup, readiness for read and
# write, timeouts, blocking and non-blocking selects, cross-thread wakeup,
# NIO::Monitor interests and values, and NIO::ByteBuffer.
#
# This is puma's I/O core, so a failure here means a packaged Rails app will
# not serve. Exit status 0 means every check passed.

require "nio"
require "socket"

$pass = 0
$fail = 0

def check(name)
  got = yield
  if got
    $pass += 1
    puts "PASS: #{name}#{got == true ? "" : " :: #{got.inspect}"}"
  else
    $fail += 1
    puts "FAIL: #{name}"
  end
rescue => e
  $fail += 1
  puts "FAIL: #{name} :: #{e.class}: #{e.message}"
end

def pipe_pair
  # A loopback TCP pair: the one thing every cosmopolitan host agrees on, and
  # what puma actually selects over.
  server = TCPServer.new("127.0.0.1", 0)
  client = TCPSocket.new("127.0.0.1", server.addr[1])
  peer = server.accept
  server.close
  [client, peer]
end

# --------------------------------------------------- engine and backend

check("NIO::VERSION") { NIO::VERSION }

check("the C extension is in use, not the pure-Ruby selector") do
  NIO::ENGINE == "libev"
end

check("the backend is poll") do
  # If this ever comes back :select, libev rejected poll() at runtime and fell
  # back; if it comes back :epoll/:kqueue then BUILD.mk's -DEV_USE_* set is
  # not what actually got compiled.
  NIO::Selector.new.backend == :poll
end

check("supported backends are exactly the portable pair") do
  NIO::Selector.backends.sort == %i[poll select].sort
end

check("a selector can be pinned to the select backend") do
  s = NIO::Selector.new(:select)
  got = s.backend
  s.close
  got == :select
end

# ------------------------------------------------------------ selector

check("register returns a Monitor and is remembered") do
  a, b = pipe_pair
  s = NIO::Selector.new
  m = s.register(a, :r)
  ok = m.is_a?(NIO::Monitor) && m.io == a && m.interests == :r && s.registered?(a) && !s.empty?
  s.close
  [a, b].each(&:close)
  ok
end

check("deregister removes and closes the monitor") do
  a, b = pipe_pair
  s = NIO::Selector.new
  m = s.register(a, :r)
  s.deregister(a)
  ok = !s.registered?(a) && m.closed? && s.empty?
  s.close
  [a, b].each(&:close)
  ok
end

check("select returns nil on timeout when nothing is ready") do
  a, b = pipe_pair
  s = NIO::Selector.new
  s.register(a, :r)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  got = s.select(0.2)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  s.close
  [a, b].each(&:close)
  got.nil? && elapsed >= 0.1
end

check("select(0) is a non-blocking poll") do
  a, b = pipe_pair
  s = NIO::Selector.new
  s.register(a, :r)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  got = s.select(0)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  s.close
  [a, b].each(&:close)
  got.nil? && elapsed < 0.5
end

check("readable socket is selected") do
  a, b = pipe_pair
  s = NIO::Selector.new
  m = s.register(a, :r)
  b.write("ping")
  ready = s.select(2)
  ok = ready&.to_a == [m] && m.readable? && a.readpartial(4) == "ping"
  s.close
  [a, b].each(&:close)
  ok
end

check("select yields to a block") do
  a, b = pipe_pair
  s = NIO::Selector.new
  s.register(a, :r)
  b.write("x")
  seen = []
  n = s.select(2) { |mon| seen << mon.io }
  ok = n == 1 && seen == [a]
  s.close
  [a, b].each(&:close)
  ok
end

check("a writable socket is selected for :w") do
  a, b = pipe_pair
  s = NIO::Selector.new
  m = s.register(a, :w)
  ready = s.select(2)
  ok = ready&.to_a == [m] && m.writable?
  s.close
  [a, b].each(&:close)
  ok
end

check("interests can be changed after registration") do
  a, b = pipe_pair
  s = NIO::Selector.new
  m = s.register(a, :w)
  m.interests = :r
  ok1 = m.interests == :r && s.select(0.2).nil?
  b.write("y")
  ok2 = s.select(2)&.to_a == [m]
  s.close
  [a, b].each(&:close)
  ok1 && ok2
end

check("monitor#value carries user data (this is how puma finds its client)") do
  a, b = pipe_pair
  s = NIO::Selector.new
  m = s.register(a, :r)
  m.value = { client: :marker }
  b.write("z")
  got = s.select(2).first.value
  s.close
  [a, b].each(&:close)
  got == { client: :marker }
end

check("several sockets, only the ready ones come back") do
  pairs = Array.new(8) { pipe_pair }
  s = NIO::Selector.new
  monitors = pairs.map { |a, _| s.register(a, :r) }
  # Make numbers 1, 4 and 6 readable.
  [1, 4, 6].each { |i| pairs[i][1].write("hit") }
  ready = []
  # poll(2) may report them in one or more wakeups; drain for up to 2s.
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
  while ready.size < 3 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    (s.select(0.2) || []).each do |m|
      next if ready.include?(m)

      m.io.readpartial(3)
      ready << m
    end
  end
  ok = ready.map { |m| monitors.index(m) }.sort == [1, 4, 6]
  s.close
  pairs.flatten.each(&:close)
  ok
end

check("wakeup interrupts a blocking select from another thread") do
  s = NIO::Selector.new
  a, b = pipe_pair
  s.register(a, :r)
  t = Thread.new do
    sleep 0.2
    s.wakeup
  end
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  got = s.select # no timeout: blocks until woken
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  t.join
  s.close
  [a, b].each(&:close)
  # A woken (rather than ready) select returns an empty set, not nil.
  got == [] && elapsed >= 0.15 && elapsed < 5
end

check("a blocking select does not block other Ruby threads (GVL is released)") do
  s = NIO::Selector.new
  a, b = pipe_pair
  s.register(a, :r)
  ticks = 0
  worker = Thread.new { 20.times { ticks += 1; sleep 0.01 } }
  b.write("go") if false # deliberately not ready yet
  s.select(0.4)
  worker.join
  s.close
  [a, b].each(&:close)
  ticks == 20
end

check("selector#close makes it closed and empty") do
  s = NIO::Selector.new
  a, b = pipe_pair
  s.register(a, :r)
  s.close
  ok = s.closed?
  [a, b].each(&:close)
  ok
end

check("registering a closed IO raises") do
  s = NIO::Selector.new
  a, b = pipe_pair
  a.close
  begin
    s.register(a, :r)
    false
  rescue IOError, ArgumentError, Errno::EBADF
    true
  ensure
    s.close
    b.close
  end
end

# ---------------------------------------------------------- ByteBuffer

check("ByteBuffer basics") do
  buf = NIO::ByteBuffer.new(256)
  buf << "hello "
  buf << "world"
  buf.flip
  buf.capacity == 256 && buf.position == 0 && buf.limit == 11 && buf.get(11) == "hello world"
end

check("ByteBuffer clear/compact/remaining") do
  buf = NIO::ByteBuffer.new(16)
  buf << "abcdef"
  ok1 = buf.remaining == 10
  buf.flip
  buf.get(3)
  buf.compact
  ok2 = buf.position == 3
  buf.clear
  ok1 && ok2 && buf.position.zero? && buf.limit == 16
end

check("ByteBuffer overflow raises") do
  buf = NIO::ByteBuffer.new(4)
  begin
    buf << "toolong"
    false
  rescue NIO::ByteBuffer::OverflowError
    true
  end
end

check("ByteBuffer read_from / write_to a socket") do
  a, b = pipe_pair
  b.write("payload")
  buf = NIO::ByteBuffer.new(64)
  # read_from is a single non-blocking read: wait for the bytes to actually
  # arrive first, and keep reading until all 7 are in. On a loopback socket
  # under macOS the write is not visible to the reader immediately.
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
  while buf.position < 7 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    IO.select([a], nil, nil, 0.2)
    begin
      buf.read_from(a)
    rescue IO::WaitReadable, NIO::ByteBuffer::UnderflowError
      nil
    end
  end
  buf.flip
  c, d = pipe_pair
  buf.write_to(c)
  got = d.read(7)
  [a, b, c, d].each(&:close)
  got == "payload"
end

# ------------------------------------------------------------- rubygems

check("registered as a default gem") do
  Gem::Specification.find_all_by_name("nio4r").map { |s| [s.version.to_s, s.default_gem?] } ==
    [[NIO::VERSION, true]]
end

puts
puts "RESULT: pass=#{$pass} fail=#{$fail}"
exit($fail.zero? ? 0 : 1)
