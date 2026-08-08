# Non-gating socket diagnostic for the CI runners.
#
#   <ruby.com> cosmo_tests/ci_diag_sockets.rb
#
# ALWAYS exits 0.  It exists to characterise host-specific socket behaviour
# that the Vagrant VM used for local development does not reproduce -- in
# particular the "undefined method 'kernel_sleep' for nil" NoMethodError seen
# on the GitHub windows-latest runner inside Socket#connect / TCPSocket#new
# while cosmo_tests/test_sockets.rb passed on the same machine and the same
# binary.
#
# Delete this file once the behaviour it chases is understood and fixed.

require "socket"

def hr(title)
  puts
  puts "-" * 70
  puts title
  puts "-" * 70
end

def report(label)
  t0 = Time.now
  value = yield
  puts "  OK    %-46s %s (%.3fs)" % [label, value.inspect[0, 40], Time.now - t0]
  true
rescue Exception => e
  puts "  ERROR %-46s %s: %s (%.3fs)" % [label, e.class, e.message, Time.now - t0]
  if e.is_a?(NoMethodError)
    begin
      puts "        NoMethodError#name     = #{e.name.inspect}"
      puts "        NoMethodError#receiver = #{e.receiver.inspect} (#{e.receiver.class})"
    rescue Exception => e2
      puts "        (receiver unavailable: #{e2.class}: #{e2.message})"
    end
  end
  puts "        Fiber.scheduler        = #{(Fiber.respond_to?(:scheduler) ? Fiber.scheduler.inspect : 'n/a')}"
  puts "        Fiber.current_scheduler= #{(Fiber.respond_to?(:current_scheduler) ? (Fiber.current_scheduler.inspect rescue 'raised') : 'n/a')}"
  puts "        Thread.current         = #{Thread.current.inspect}"
  puts "        Thread.list.size       = #{Thread.list.size}"
  Array(e.backtrace).each { |l| puts "        bt: #{l}" }
  false
end

# ---------------------------------------------------------------- environment
hr "environment"
puts "  RUBY_DESCRIPTION   = #{RUBY_DESCRIPTION}"
puts "  windows?           = #{Dir.exist?('/C/Windows') || ENV['OS'] == 'Windows_NT'}"
puts "  cwd                = #{Dir.pwd}"
puts "  Fiber.scheduler    = #{(Fiber.scheduler.inspect rescue 'raised')}"
puts "  Thread.current     = #{Thread.current.inspect}"
puts "  AF_INET6/SOL_SOCKET= #{Socket::AF_INET6} / #{Socket::SOL_SOCKET}"
begin
  puts "  getaddrinfo(localhost) = #{Socket.getaddrinfo('localhost', 80, nil, :STREAM).inspect}"
rescue Exception => e
  puts "  getaddrinfo(localhost) raised #{e.class}: #{e.message}"
end
begin
  puts "  ip_address_list        = #{Socket.ip_address_list.map(&:inspect).inspect}"
rescue Exception => e
  puts "  ip_address_list raised #{e.class}: #{e.message}"
end

# ------------------------------------------------------------------ scenarios
# Each scenario stands up a fresh listener and connects to it a different way.
# The point is to find which connect path trips, not to test correctness.

def with_server(host)
  server = TCPServer.new(host, 0)
  port = server.addr[1]
  acceptor = Thread.new do
    begin
      c = server.accept
      c.write("ok")
      c.close
    rescue Exception
      # ignore; the diagnostic only cares about the client side
    end
  end
  begin
    yield(server, port)
  ensure
    acceptor.kill rescue nil
    acceptor.join(5) rescue nil
    server.close rescue nil
  end
end

def scenarios
  {
    "TCPSocket.new(localhost)" => -> {
      with_server("localhost") { |_, port| s = TCPSocket.new("localhost", port); r = s.read(2); s.close; r }
    },
    "TCPSocket.new(127.0.0.1)" => -> {
      with_server("127.0.0.1") { |_, port| s = TCPSocket.new("127.0.0.1", port); r = s.read(2); s.close; r }
    },
    "TCPSocket.new(::1)" => -> {
      with_server("::1") { |_, port| s = TCPSocket.new("::1", port); r = s.read(2); s.close; r }
    },
    "Socket.tcp(127.0.0.1)" => -> {
      with_server("127.0.0.1") { |_, port| Socket.tcp("127.0.0.1", port) { |s| s.read(2) } }
    },
    "Addrinfo#connect(127.0.0.1)" => -> {
      with_server("127.0.0.1") { |_, port| s = Addrinfo.tcp("127.0.0.1", port).connect; r = s.read(2); s.close; r }
    },
    "raw Socket#connect(127.0.0.1)" => -> {
      with_server("127.0.0.1") do |_, port|
        s = Socket.new(:INET, :STREAM)
        s.connect(Socket.sockaddr_in(port, "127.0.0.1"))
        r = s.read(2); s.close; r
      end
    },
    "connect_nonblock + IO.select" => -> {
      with_server("127.0.0.1") do |_, port|
        s = Socket.new(:INET, :STREAM)
        begin
          s.connect_nonblock(Socket.sockaddr_in(port, "127.0.0.1"))
        rescue IO::WaitWritable, Errno::EINPROGRESS
          IO.select(nil, [s], nil, 10)
        end
        r = s.read(2); s.close; r
      end
    },
    "TCPSocket.new inside a Thread" => -> {
      with_server("127.0.0.1") do |_, port|
        Thread.new { s = TCPSocket.new("127.0.0.1", port); r = s.read(2); s.close; r }.value
      end
    },
  }
end

def thread_churn
  q = Queue.new
  m = Mutex.new
  n = 0
  ts = 4.times.map { Thread.new { 25.times { m.synchronize { n += 1 } }; q << :done } }
  ts.each(&:join)
  [n, q.size]
end

hr "pass 1: cold (no prior thread churn) -- like cosmo_tests/test_sockets.rb"
results_cold = scenarios.to_h { |name, body| [name, report(name, &body)] }

hr "thread churn (what ci_smoke.rb does before its socket checks)"
puts "  #{thread_churn.inspect}"
puts "  Thread.list.size = #{Thread.list.size}"

hr "pass 2: warm (after thread churn) -- like cosmo_tests/ci_smoke.rb"
results_warm = scenarios.to_h { |name, body| [name, report(name, &body)] }

hr "pass 3: repeat of pass 2 (is it deterministic?)"
results_again = scenarios.to_h { |name, body| [name, report(name, &body)] }

hr "summary (cold / warm / again)"
scenarios.each_key do |name|
  puts "  %-34s %-5s %-5s %-5s" % [
    name,
    results_cold[name] ? "ok" : "FAIL",
    results_warm[name] ? "ok" : "FAIL",
    results_again[name] ? "ok" : "FAIL",
  ]
end

puts
puts "DIAG-DONE"
exit 0
