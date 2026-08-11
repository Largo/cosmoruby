# Cross-platform smoke test for a packaged CosmoRuby APE.
#
#   <ruby.com> cosmo_tests/ci_smoke.rb ci-arg-1 ci-arg-2
#
# Runs unchanged on Linux, Windows, macOS and the BSDs; the CI runs exactly
# this file on every platform.  Exits 0 when every check passes, 1 otherwise,
# and always prints a "SMOKE-RESULT:" line the workflow greps for.
#
# IMPORTANT (this is why the file exists): `ruby.com --version` is NOT a boot
# test.  It short-circuits before ruby_opt_init(), so it kept printing a
# correct banner for the whole period where every Windows run segfaulted
# during VM init (the Linux-only YJIT Rust call, see PORTING-NOTES.md).  Any
# useful test must get past VM init, require stdlib features and touch the
# filesystem.  This one does.

require "tmpdir"
require "fileutils"

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

# KNOWN ISSUE (Windows only, intermittent): a blocking socket operation can
# raise NoMethodError: undefined method 'kernel_sleep' for nil.  Evidence says
# this is asynchronous register corruption in cosmopolitan's Windows interrupt
# delivery, not a Ruby or port bug: in the failing artifact %rax compares
# unequal to Qnil (4) and then reads back as 4 four instructions later, with
# nothing writing it in between.  See PORTING-NOTES.md, "Windows: intermittent
# nil scheduler".  It fires in roughly half of CI runs and never reproduced
# locally in ~2100 connects; a retry succeeds.
#
# So: retry once, and if it recurs report WARN rather than FAIL -- but only for
# this exact signature on Windows.  Every other socket failure stays hard, so a
# real regression still turns the suite red.
def known_nil_scheduler?(e)
  e.is_a?(NoMethodError) && e.name == :kernel_sleep && e.receiver.nil?
rescue NoMethodError
  e.is_a?(NoMethodError) && e.message.include?("kernel_sleep")
end

def tcp_check(name, windows)
  attempts = 0
  begin
    attempts += 1
    ok = yield
    if ok
      $pass += 1
      puts "  [PASS] #{name}"
    else
      $fail += 1
      puts "  [FAIL] #{name} :: returned #{ok.inspect}"
    end
  rescue Exception => e
    # Note: this cannot delegate to check(), which rescues internally -- the
    # exception would never reach here.
    if windows && known_nil_scheduler?(e)
      retry if attempts < 2
      $warn += 1
      puts "  [WARN] #{name} :: known Windows nil-scheduler flake (#{e.class}: #{e.message})"
    else
      $fail += 1
      puts "  [FAIL] #{name} :: #{e.class}: #{e.message}"
      Array(e.backtrace).first(3).each { |l| puts "         #{l}" }
    end
  end
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

# RUBY_PLATFORM tells you the architecture ("x86_64-cosmo" / "aarch64-cosmo")
# but not the OS -- one APE runs on all of them -- so detect the host at
# runtime.  Cosmopolitan exposes Windows drives as /C, /D, ... ; ENV is a
# fallback for environments where the drive mapping is unavailable.
windows = Dir.exist?("/C/Windows") || ENV["OS"] == "Windows_NT"

puts "CosmoRuby CI smoke test"
puts "  RUBY_DESCRIPTION = #{RUBY_DESCRIPTION}"
puts "  RUBY_VERSION     = #{RUBY_VERSION}"
puts "  RUBY_PLATFORM    = #{RUBY_PLATFORM}"
puts "  RUBY_ENGINE      = #{RUBY_ENGINE}"
puts "  host os          = #{(RbConfig::CONFIG['host_os'] rescue '?')}"
puts "  argv             = #{ARGV.inspect}"
puts "  cwd              = #{Dir.pwd}"
puts "-" * 64

# --- interpreter identity -------------------------------------------------
check("RUBY_VERSION is 4.x")        { RUBY_VERSION.to_s.start_with?("4.") }
check("RUBY_PLATFORM is cosmo")     { RUBY_PLATFORM.to_s.include?("cosmo") }
check("RUBY_ENGINE is ruby")        { RUBY_ENGINE == "ruby" }
check("RUBY_DESCRIPTION has version") { RUBY_DESCRIPTION.include?(RUBY_VERSION) }

# --- embedded stdlib (/zip) ----------------------------------------------
check("/zip stdlib is mounted")     { Dir.exist?("/zip") }
check("$LOAD_PATH lives in /zip")   { $LOAD_PATH.any? { |p| p.to_s.start_with?("/zip") } }

# --- stdlib requires ------------------------------------------------------
check("require json")     { require "json";     JSON.generate({ "ok" => true }) == '{"ok":true}' }
check("require yaml")     { require "yaml";     YAML.load("a: 1")["a"] == 1 }
check("require zlib")     { require "zlib";     Zlib::Inflate.inflate(Zlib::Deflate.deflate("hello" * 10)) == "hello" * 10 }
check("require digest")   { require "digest";   Digest::SHA256.hexdigest("abc").start_with?("ba7816bf") }
check("require stringio") { require "stringio"; s = StringIO.new; s << "hi"; s.string == "hi" }
check("require socket")   { require "socket";   defined?(TCPServer) ? true : false }
check("require set")      { require "set";      Set[1, 2, 2].size == 2 }
check("require date")     { require "date";     Date.today.year >= 2020 }
check("require uri")      { require "uri";      URI.parse("https://example.com/x").host == "example.com" }

# --- RubyGems -------------------------------------------------------------
check("Gem is preloaded")  { defined?(Gem) ? true : false }
check("Gem.default_dir")   { Gem.default_dir.to_s.include?("/zip") }

# --- filesystem -----------------------------------------------------------
check("file write/read/delete") do
  Dir.mktmpdir("cosmoruby-ci") do |dir|
    path = File.join(dir, "smoke.txt")
    File.write(path, "hello from ruby\n" * 3)
    body = File.read(path)
    File.delete(path)
    body.lines.size == 3 && !File.exist?(path)
  end
end
check("Dir.glob + File.stat") do
  Dir.mktmpdir("cosmoruby-ci") do |dir|
    3.times { |i| File.write(File.join(dir, "f#{i}.dat"), "x" * (i + 1)) }
    Dir.glob(File.join(dir, "*.dat")).size == 3 &&
      File.size(File.join(dir, "f2.dat")) == 3
  end
end
check("binary IO round-trip") do
  Dir.mktmpdir("cosmoruby-ci") do |dir|
    path = File.join(dir, "bin.dat")
    blob = (0..255).map(&:chr).join.b
    File.binwrite(path, blob)
    File.binread(path) == blob
  end
end

# --- concurrency ----------------------------------------------------------
check("threads compute and join") do
  4.times.map { |i| Thread.new { i * i } }.map(&:value).sum == 14
end
check("mutex + queue") do
  q = Queue.new
  m = Mutex.new
  n = 0
  ts = 4.times.map { Thread.new { 25.times { m.synchronize { n += 1 } }; q << :done } }
  ts.each(&:join)
  n == 100 && q.size == 4
end

# --- sockets --------------------------------------------------------------
def loopback_echo(host)
  require "socket"
  server = TCPServer.new(host, 0)
  port = server.addr[1]
  acceptor = Thread.new { c = server.accept; c.write(c.gets); c.close }
  client = TCPSocket.new(host, port)
  client.puts("ping")
  got = client.gets
  client.close
  acceptor.join(10)
  server.close
  got.to_s.strip == "ping"
end

# UDP works on every platform.
check("udp loopback datagram") do
  require "socket"
  rx = UDPSocket.new
  rx.bind("127.0.0.1", 0)
  tx = UDPSocket.new
  tx.send("ping", 0, "127.0.0.1", rx.addr[1])
  got = rx.recvfrom(16)[0]
  rx.close
  tx.close
  got == "ping"
end

# TCP.  These were WARNINGS on Windows between 2026-08-08 and 2026-08-09
# because TCP was broken there (and, as the macOS runner then showed, on
# macOS too).  They are HARD CHECKS on every platform again: the cause was
# found and fixed -- two CosmoRuby headers `#undef`'d cosmopolitan's runtime
# socket constants and hard-coded the *Linux* values, so AF_INET6 was 10
# where the host wanted 23 (Windows) or 30 (XNU) and SOL_SOCKET was 1 where
# the host wanted 0xffff.  See PORTING-NOTES.md, "Socket ABI: the constants
# must be the host's, not Linux's".
#
# If any of these ever goes red on one OS only, that is the first thing to
# suspect.  cosmo_tests/test_sockets.rb is the detailed suite; what follows
# is the subset worth having in the fast CI smoke path.
tcp_check("tcp loopback echo (localhost)", windows) { loopback_echo("localhost") }
tcp_check("tcp loopback echo (127.0.0.1)", windows) { loopback_echo("127.0.0.1") }

tcp_check("Socket.tcp", windows) do
  require "socket"
  server = TCPServer.new("127.0.0.1", 0)
  port = server.addr[1]
  acceptor = Thread.new { c = server.accept; c.write("tcp-ok"); c.close }
  got = nil
  Socket.tcp("127.0.0.1", port) { |s| got = s.readpartial(64) }
  acceptor.join(10)
  server.close
  got == "tcp-ok"
end

# REGRESSION: the specific getaddrinfo family values.  The original failure
# printed "unknown:23" here, because Ruby's family tables said AF_INET6 was
# 10 while cosmopolitan's getaddrinfo (correctly) reported the host's 23.
check("getaddrinfo(127.0.0.1) is AF_INET") do
  require "socket"
  ai = Socket.getaddrinfo("127.0.0.1", 80, nil, :STREAM)
  !ai.empty? && ai.all? { |a| a[0] == "AF_INET" && a[4] == Socket::AF_INET && a[3] == "127.0.0.1" }
end

check("getaddrinfo family name matches family number") do
  require "socket"
  ai = Socket.getaddrinfo("localhost", 80, nil, :STREAM)
  !ai.empty? && ai.all? do |a|
    case a[4]
    when Socket::AF_INET  then a[0] == "AF_INET"
    when Socket::AF_INET6 then a[0] == "AF_INET6"
    else false # "unknown:NN" -- the regression
    end
  end
end

# REGRESSION: with the bug present, packing an IPv4 literal went down
# raddrinfo.c's IPv6 branch (inet_pton returned -1, which Ruby read as
# success) and produced a 28-byte sockaddr_in6 full of uninitialised heap.
check("sockaddr_in(ipv4) is a 16-byte AF_INET sockaddr") do
  require "socket"
  sa = Socket.sockaddr_in(0, "127.0.0.1")
  sa.bytesize == 16 && sa.unpack1("S") == Socket::AF_INET &&
    sa.unpack("C*")[4, 4] == [127, 0, 0, 1]
end

# The socket constants must be the HOST's, not Linux's.
if windows
  check("AF_INET6 is Winsock's 23")        { require "socket"; Socket::AF_INET6 == 23 }
  check("SOL_SOCKET is Winsock's 0xffff")  { require "socket"; Socket::SOL_SOCKET == 0xffff }
end

# SOL_SOCKET was sent as 1 instead of 0xffff off Linux, so every socket
# option raised Errno::EINVAL there.
check("setsockopt/getsockopt SOL_SOCKET SO_REUSEADDR") do
  require "socket"
  s = TCPServer.new("127.0.0.1", 0)
  s.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
  v = s.getsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR)
  s.close
  v.bool == true
end

# IPv6 loopback needs ::1 to actually be configured; not every CI runner or
# container has it, so this one stays soft.
soft("tcp loopback echo (::1)") { loopback_echo("::1") }

# --- sqlite3 (statically linked extension) --------------------------------
check("require sqlite3") { require "sqlite3"; !SQLite3::SQLITE_VERSION.empty? }
check("sqlite3 real database") do
  Dir.mktmpdir("cosmoruby-ci") do |dir|
    db = SQLite3::Database.new(File.join(dir, "ci.db"))
    db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, n INTEGER)")
    db.transaction do
      db.execute("INSERT INTO t (name, n) VALUES (?, ?)", ["alpha", 1])
      db.execute("INSERT INTO t (name, n) VALUES (?, ?)", ["beta", 2])
    end
    rows = db.execute("SELECT name, n FROM t ORDER BY n")
    total = db.get_first_value("SELECT SUM(n) FROM t")
    db.close
    rows == [["alpha", 1], ["beta", 2]] && total == 3
  end
end

# --- process / argv -------------------------------------------------------
check("ARGV passthrough") { ARGV == ["ci-arg-1", "ci-arg-2"] }
check("Process.pid")      { Process.pid.to_i > 0 }
soft("ENV readable")      { !ENV["PATH"].to_s.empty? }

# --- YJIT (kept last: a successful enable JITs everything after it) --------
#
# `RubyVM::YJIT.enable` used to segfault at <internal:yjit>:67 on Windows -- it
# calls straight into the YJIT Rust staticlib, which is built for
# x86_64-unknown-linux-gnu and whose globals are never initialised off Linux.
# Rails 8 turns YJIT on at boot (`config.yjit`, default true outside
# development/test), so *every* packaged Rails app died before serving a byte.
# That was the third bug of this family; see cosmo_yjit_usable() in yjit.h.
#
# YJIT really runs only on the Linux/x86-64 half of the APE.  Compute that from
# inside the interpreter -- RUBY_PLATFORM plus Etc.uname -- so the expectation
# is also right when the aarch64 half is driven through qemu-user on an x86-64
# host.  Everywhere else the answer must be an honest "no", never a crash.
yjit_can_run =
  begin
    require "etc"
    RUBY_PLATFORM.start_with?("x86_64") && Etc.uname[:sysname] == "Linux"
  rescue Exception
    false
  end

check("RubyVM::YJIT.enabled? is false before enabling") { RubyVM::YJIT.enabled? == false }

# Every entry point <internal:yjit> exposes, called on a build where YJIT is
# not running.  None of these may crash, raise, or answer something untrue.
check("RubyVM::YJIT introspection is safe before enabling") do
  RubyVM::YJIT.stats_enabled?               == false &&
    RubyVM::YJIT.log_enabled?               == false &&
    RubyVM::YJIT.trace_exit_locations_enabled? == false &&
    RubyVM::YJIT.runtime_stats.nil?         &&
    RubyVM::YJIT.log.nil?                   &&
    RubyVM::YJIT.exit_locations.nil?        &&
    RubyVM::YJIT.reset_stats!.nil?          &&
    RubyVM::YJIT.code_gc.nil?               &&
    RubyVM::YJIT.stats_string               == ""
end

check("RubyVM::YJIT.dump_exit_locations raises rather than crashing") do
  begin
    RubyVM::YJIT.dump_exit_locations(File.join(Dir.tmpdir, "cosmoruby-yjit.dump"))
    false
  rescue ArgumentError
    true
  end
end

# The two lines that matter: this is literally what Rails' :enable_yjit
# initializer runs.
check("RubyVM::YJIT.enable does not crash") { RubyVM::YJIT.enable == yjit_can_run }
check("RubyVM::YJIT.enabled? agrees with enable") { RubyVM::YJIT.enabled? == yjit_can_run }

# RUBY_DESCRIPTION used to advertise +YJIT where YJIT could not run, which is
# what lets feature detection be fooled into the crash in the first place.
check("RUBY_DESCRIPTION +YJIT agrees with enabled?") do
  RUBY_DESCRIPTION.include?("+YJIT") == RubyVM::YJIT.enabled?
end

# ... and once more with YJIT on where it can be on, so the enabled path is
# covered too.
check("RubyVM::YJIT introspection is safe after enabling") do
  # insns_compiled is nil while YJIT is off and an Array once it is on; either
  # is a valid answer, a segfault is not.
  insns = RubyVM::YJIT.insns_compiled(method(:known_nil_scheduler?))
  RubyVM::YJIT.stats_enabled? == false &&
    RubyVM::YJIT.code_gc.nil? &&
    RubyVM::YJIT.reset_stats!.nil? &&
    (insns.nil? || insns.is_a?(Array))
end

puts "-" * 64
puts "SMOKE-RESULT: pass=#{$pass} fail=#{$fail} warn=#{$warn}"
puts($fail.zero? ? "SMOKE-OK" : "SMOKE-FAILED")
exit($fail.zero? ? 0 : 1)
