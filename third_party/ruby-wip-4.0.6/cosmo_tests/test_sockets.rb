# Socket / TCP acceptance + regression tests for a packaged CosmoRuby APE.
#
#   <ruby.com> cosmo_tests/test_sockets.rb
#
# Runs unchanged on Linux, Windows, macOS and the BSDs.  Exits 0 when every
# check passes, 1 otherwise.
#
# WHY THIS FILE EXISTS
# --------------------
# Between the 4.0.0 and 4.0.6 ports, TCP worked on Linux and was completely
# broken on Windows *and* macOS.  The cause was not cosmopolitan: it was two
# CosmoRuby headers -- ext/socket/socket_constants.h and
# include/errno_wrapper.h -- which `#undef`'d cosmopolitan's runtime socket
# constants and hard-coded the *Linux* numbers, "since we're building for
# Cosmopolitan".  Cosmopolitan resolves those symbols at startup to whatever
# the host OS uses (AF_INET6 = 10 linux / 23 windows / 30 xnu, SOL_SOCKET = 1
# linux / 0xffff windows+xnu+bsd, ...) and passes them straight through to
# the kernel or to Winsock, so the hard-coded values were wrong everywhere
# except Linux.
#
# The nastiest consequence was silent memory corruption rather than a clean
# error: raddrinfo.c's numeric_getaddrinfo() calls
# `inet_pton(AF_INET6, node, buf)` and only tests for a non-zero return.
# With AF_INET6 forced to 10, cosmopolitan's inet_pton took its
# "unsupported address family" arm and returned -1 -- which is non-zero --
# so Ruby built a sockaddr_in6 out of an *uninitialised* buffer for a plain
# IPv4 literal.  bind()/connect() then failed with EAFNOSUPPORT on Windows
# and EPFNOSUPPORT on macOS, for the address "127.0.0.1".
#
# So the checks below are deliberately paranoid about the *numbers*, not
# only about whether a connection succeeds: a regression here shows up first
# as a wrong address family, and only later as a broken socket.

require "socket"

$pass = 0
$fail = 0
$warn = 0

def check(name)
  ok = yield
  if ok
    $pass += 1
    puts "  [PASS] #{name}"
  else
    $fail += 1
    puts "  [FAIL] #{name} :: returned #{ok.inspect}"
  end
rescue Exception => e
  $fail += 1
  puts "  [FAIL] #{name} :: #{e.class}: #{e.message}"
  Array(e.backtrace).first(3).each { |l| puts "         #{l}" }
end

def soft(name)
  ok = yield
  if ok
    $pass += 1
    puts "  [PASS] #{name}"
  else
    $warn += 1
    puts "  [WARN] #{name} :: returned #{ok.inspect}"
  end
rescue Exception => e
  $warn += 1
  puts "  [WARN] #{name} :: #{e.class}: #{e.message}"
end

windows = Dir.exist?("/C/Windows") || ENV["OS"] == "Windows_NT"

puts "CosmoRuby socket tests"
puts "  RUBY_DESCRIPTION = #{RUBY_DESCRIPTION}"
puts "  windows          = #{windows}"
puts "  AF_INET          = #{Socket::AF_INET}"
puts "  AF_INET6         = #{Socket::AF_INET6}"
puts "  SOL_SOCKET       = #{Socket::SOL_SOCKET}"
puts "  SO_REUSEADDR     = #{Socket::SO_REUSEADDR}"
puts "  SO_ERROR         = #{Socket::SO_ERROR}"
puts "  IPV6_V6ONLY      = #{Socket::IPV6_V6ONLY}"
puts "-" * 64

# --- ABI: the constants must be the HOST's, not Linux's -------------------
# Cosmopolitan resolves these per host; a build that hard-codes Linux values
# is exactly the bug this file guards against.  We do not assert a single
# number (the APE runs on six operating systems), we assert the mapping is
# self-consistent and, on Windows, that it is *not* the Linux value.

check("AF_INET is 2 everywhere")      { Socket::AF_INET == 2 }
check("AF_INET6 is a known value")    { [10, 23, 24, 28, 30].include?(Socket::AF_INET6) }
check("SOL_SOCKET is a known value")  { [1, 0xffff].include?(Socket::SOL_SOCKET) }

if windows
  check("AF_INET6 is Winsock's 23")   { Socket::AF_INET6 == 23 }
  check("SOL_SOCKET is Winsock's 0xffff") { Socket::SOL_SOCKET == 0xffff }
  check("IPV6_V6ONLY is Winsock's 27") { Socket::IPV6_V6ONLY == 27 }
end

# --- REGRESSION: getaddrinfo address families -----------------------------
# The original failure printed "unknown:23" here, because Ruby's family
# tables said AF_INET6 was 10 while cosmopolitan's getaddrinfo (correctly)
# reported the host's 23.

check("getaddrinfo(127.0.0.1) is AF_INET") do
  ai = Socket.getaddrinfo("127.0.0.1", 80, nil, :STREAM)
  !ai.empty? && ai.all? { |a| a[0] == "AF_INET" && a[4] == Socket::AF_INET && a[3] == "127.0.0.1" }
end

check("getaddrinfo family name matches family number") do
  ai = Socket.getaddrinfo("localhost", 80, nil, :STREAM)
  !ai.empty? && ai.all? do |a|
    name, num = a[0], a[4]
    case num
    when Socket::AF_INET  then name == "AF_INET"
    when Socket::AF_INET6 then name == "AF_INET6"
    else false # this is the "unknown:23" regression
    end
  end
end

check("no getaddrinfo entry reports an unknown family") do
  ai = Socket.getaddrinfo("localhost", 80, nil, :STREAM)
  ai.none? { |a| a[0].to_s.start_with?("unknown:") }
end

# --- REGRESSION: inet_pton via Socket.sockaddr_in -------------------------
# This is the tightest test for the root cause.  With the bug present,
# packing an IPv4 literal produced a 28-byte sockaddr_in6 whose family was
# 10 and whose address bytes were uninitialised heap.

check("sockaddr_in(ipv4) is a 16-byte AF_INET sockaddr") do
  sa = Socket.sockaddr_in(0, "127.0.0.1")
  fam = sa.unpack1("S")           # native-endian sa_family
  sa.bytesize == 16 && fam == Socket::AF_INET &&
    sa.unpack("C*")[4, 4] == [127, 0, 0, 1]
end

check("sockaddr_in(ipv6) is a 28-byte AF_INET6 sockaddr") do
  sa = Socket.sockaddr_in(0, "::1")
  fam = sa.unpack1("S")
  sa.bytesize == 28 && fam == Socket::AF_INET6
end

check("Addrinfo.ip round-trips both families") do
  Addrinfo.ip("127.0.0.1").afamily == Socket::AF_INET &&
    Addrinfo.ip("::1").afamily == Socket::AF_INET6 &&
    Addrinfo.ip("::1").ipv6? && Addrinfo.ip("127.0.0.1").ipv4?
end

# --- TCP: the thing users actually care about ------------------------------
def loopback_echo(host)
  server = TCPServer.new(host, 0)
  port = server.addr[1]
  acceptor = Thread.new do
    c = server.accept
    c.write("re:" + c.readpartial(64))
    c.close
  end
  client = TCPSocket.new(host, port)
  client.write("ping")
  got = client.readpartial(64)
  client.close
  acceptor.join(10)
  server.close
  got == "re:ping"
end

check("tcp loopback echo (127.0.0.1)") { loopback_echo("127.0.0.1") }
check("tcp loopback echo (localhost)") { loopback_echo("localhost") }

check("Socket.tcp") do
  server = TCPServer.new("127.0.0.1", 0)
  port = server.addr[1]
  acceptor = Thread.new { c = server.accept; c.write("tcp-ok"); c.close }
  got = nil
  Socket.tcp("127.0.0.1", port) { |s| got = s.readpartial(64) }
  acceptor.join(10)
  server.close
  got == "tcp-ok"
end

check("TCPServer#addr reports AF_INET") do
  s = TCPServer.new("127.0.0.1", 0)
  a = s.addr
  s.close
  a[0] == "AF_INET" && a[3] == "127.0.0.1"
end

# IPv6 loopback needs the host to actually have ::1 configured; CI runners
# and containers sometimes do not, so this one is soft.
soft("tcp loopback echo (::1)") { loopback_echo("::1") }

# --- socket options -------------------------------------------------------
# SOL_SOCKET is 1 on Linux and 0xffff elsewhere; passing the wrong one gave
# "Errno::EINVAL - setsockopt(2)" on Windows.

check("setsockopt/getsockopt SOL_SOCKET SO_REUSEADDR") do
  s = TCPServer.new("127.0.0.1", 0)
  s.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
  v = s.getsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR)
  s.close
  v.bool == true
end

# Socket::Option#int requires getsockopt to report a 4-byte value.  Winsock
# answers boolean options with a single byte; cosmopolitan widens that back
# to an int in libc/sock/getsockopt-nt.c.
#
# NOTE: do not assert the value is exactly 1.  POSIX only promises "non-zero
# means enabled", and the 4.4BSD lineage returns the internal flag bit:
# MacOS/XNU and the BSDs answer TCP_NODELAY with TF_NODELAY == 4, Linux and
# Windows answer 1.  Asserting == 1 is a test bug, not a platform bug.
check("getsockopt IPPROTO_TCP TCP_NODELAY reports an int") do
  server = TCPServer.new("127.0.0.1", 0)
  port = server.addr[1]
  acceptor = Thread.new { server.accept.close }
  s = TCPSocket.new("127.0.0.1", port)
  s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
  v = s.getsockopt(:IPPROTO_TCP, :TCP_NODELAY)
  s.close
  acceptor.join(10)
  server.close
  bytes = v.data.bytesize
  raise "getsockopt reported #{bytes} bytes, want 4 (raw #{v.data.unpack('C*').inspect})" unless bytes == 4
  raise "TCP_NODELAY read back as 0 after being enabled" if v.int.zero?
  true
end

# SO_ERROR must be translated out of Winsock's numbering; this is how every
# non-blocking connect learns why it failed.
check("SO_ERROR after refused connect is ECONNREFUSED") do
  probe = TCPServer.new("127.0.0.1", 0)
  port = probe.addr[1]
  probe.close
  s = Socket.new(:INET, :STREAM)
  begin
    s.connect_nonblock(Socket.sockaddr_in(port, "127.0.0.1"))
  rescue IO::WaitWritable, Errno::EINPROGRESS
    # expected
  rescue Errno::ECONNREFUSED
    s.close
    next true # some hosts fail immediately, which is also correct
  end
  IO.select(nil, [s], [s], 10)
  err = s.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR).int
  s.close
  want = Errno::ECONNREFUSED::Errno
  unless err == want
    raise "SO_ERROR reported #{err}, want ECONNREFUSED=#{want}" \
          " -- the host kernel's own errno number leaked out untranslated" \
          " (winsock says 10061, xnu/bsd say 61)"
  end
  true
end

check("ipv6only! does not raise 'unknown protocol level'") do
  s = Socket.new(Socket::AF_INET6, Socket::SOCK_STREAM, 0)
  begin
    s.ipv6only!
    true
  ensure
    s.close
  end
end

# --- UDP (worked throughout, kept as a control) ---------------------------
check("udp loopback datagram") do
  rx = UDPSocket.new
  rx.bind("127.0.0.1", 0)
  tx = UDPSocket.new
  tx.send("ping", 0, "127.0.0.1", rx.addr[1])
  got = rx.recvfrom(16)[0]
  rx.close
  tx.close
  got == "ping"
end

puts "-" * 64
puts "SOCKET-RESULT: pass=#{$pass} fail=#{$fail} warn=#{$warn}"
puts($fail.zero? ? "SOCKET-OK" : "SOCKET-FAILED")
exit($fail.zero? ? 0 : 1)
