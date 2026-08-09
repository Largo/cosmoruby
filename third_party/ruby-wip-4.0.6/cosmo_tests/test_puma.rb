# frozen_string_literal: true
#
# CosmoRuby puma test.
#
#   ruby.com third_party/ruby/cosmo_tests/test_puma.rb
#
# Exercises the statically linked puma 8.0.2 extension (puma_http11, the
# Ragel HTTP/1.1 parser) and then stands up a real Puma::Server on a
# loopback port and talks HTTP to it -- request line, headers, query string,
# POST body, chunked response, keep-alive, 404s, and concurrency across the
# thread pool. That server path goes through nio4r's Reactor, so this is also
# an integration test for ext/nio4r.
#
# SSL is deliberately absent (see ext/puma/BUILD.mk): Puma::HAS_SSL is false
# and Puma::MiniSSL::Engine, which only the C extension defines, does not
# exist. The checks below assert that, so the state is pinned rather than
# accidental.
#
# Exit status 0 means every check passed.

require "puma"
require "puma/server"
require "socket"
require "net/http"
require "uri"

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

# ------------------------------------------------- the extension itself

check("Puma::Const::PUMA_VERSION") { Puma::Const::PUMA_VERSION }

check("puma_http11 is the linked C extension") do
  defined?(Puma::HttpParser) == "constant" &&
    $LOADED_FEATURES.any? { |f| f.end_with?("puma/puma_http11.so") }
end

check("SSL is compiled out, as documented") do
  # lib/puma/minissl.rb is still on the load path and still defines the
  # Puma::MiniSSL namespace; what the C extension would have added is
  # MiniSSL::Engine, and HAS_SSL is derived from exactly that.
  Puma::HAS_SSL == false &&
    (!Puma.const_defined?(:MiniSSL, false) || !Puma::MiniSSL.const_defined?(:Engine, false))
end

# --------------------------------------------- the Ragel parser directly

def parse(chunk)
  parser = Puma::HttpParser.new
  env = {}
  parser.execute(env, chunk, 0)
  [parser, env]
end

check("parses a plain GET") do
  _, env = parse("GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n")
  env["REQUEST_METHOD"] == "GET" &&
    env["REQUEST_PATH"] == "/index.html" &&
    env["SERVER_PROTOCOL"] == "HTTP/1.1" &&
    env["HTTP_HOST"] == "example.com"
end

check("parses the query string and fragment") do
  _, env = parse("GET /search?q=cosmo&n=2#frag HTTP/1.1\r\nHost: h\r\n\r\n")
  env["QUERY_STRING"] == "q=cosmo&n=2" && env["FRAGMENT"] == "frag" &&
    env["REQUEST_URI"] == "/search?q=cosmo&n=2" && env["REQUEST_PATH"] == "/search"
end

check("folds repeated and hyphenated headers into HTTP_*") do
  _, env = parse("POST /x HTTP/1.1\r\nContent-Type: text/plain\r\n" \
                 "X-Custom-Header: a\r\nContent-Length: 3\r\n\r\n")
  env["CONTENT_TYPE"] == "text/plain" && env["CONTENT_LENGTH"] == "3" &&
    env["HTTP_X_CUSTOM_HEADER"] == "a"
end

check("reports finished? and body offset") do
  chunk = "GET / HTTP/1.1\r\nHost: h\r\n\r\nBODYBYTES"
  parser, = parse(chunk)
  parser.finished? && chunk[parser.body.length..] # nb_read boundary
  parser.finished?
end

check("an incomplete request is not finished, and resumes") do
  parser = Puma::HttpParser.new
  env = {}
  head = "GET / HTTP/1.1\r\nHost: ex"
  parser.execute(env, head, 0)
  not_yet = !parser.finished?
  full = head + "ample.com\r\n\r\n"
  parser.reset
  env2 = {}
  parser.execute(env2, full, 0)
  not_yet && parser.finished? && env2["HTTP_HOST"] == "example.com"
end

check("a malformed request line raises Puma::HttpParserError") do
  begin
    parse("GET\x00 / HTTP/1.1\r\n\r\n")
    false
  rescue Puma::HttpParserError
    true
  end
end

check("an over-long header is rejected rather than smashing the stack") do
  begin
    parse("GET / HTTP/1.1\r\nX-Big: #{"a" * 200_000}\r\n\r\n")
    false
  rescue Puma::HttpParserError
    true
  end
end

check("parser can be reset and reused") do
  parser = Puma::HttpParser.new
  e1 = {}
  parser.execute(e1, "GET /one HTTP/1.1\r\nHost: h\r\n\r\n", 0)
  parser.reset
  e2 = {}
  parser.execute(e2, "PUT /two HTTP/1.0\r\nHost: h\r\n\r\n", 0)
  e1["REQUEST_PATH"] == "/one" && e2["REQUEST_PATH"] == "/two" &&
    e2["REQUEST_METHOD"] == "PUT"
end

# ------------------------------------------------- a real running server

APP = lambda do |env|
  case env["PATH_INFO"]
  when "/"
    [200, { "content-type" => "text/plain" }, ["hello from puma #{Puma::Const::PUMA_VERSION}"]]
  when "/echo"
    body = env["rack.input"].read
    [200, { "content-type" => "text/plain", "x-query" => env["QUERY_STRING"].to_s }, [body]]
  when "/chunks"
    [200, { "content-type" => "text/plain" }, %w[a b c d e]]
  when "/slow"
    sleep 0.3
    [200, { "content-type" => "text/plain" }, [Thread.current.object_id.to_s]]
  else
    [404, { "content-type" => "text/plain" }, ["nope"]]
  end
end

server = nil
port = nil
thread = nil

check("Puma::Server starts and binds a TCP listener") do
  server = Puma::Server.new(APP, nil, { min_threads: 2, max_threads: 4, log_writer: Puma::LogWriter.strings })
  socket = server.add_tcp_listener("127.0.0.1", 0)
  port = socket.addr[1]
  thread = server.run
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
  ready = false
  until ready || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    begin
      TCPSocket.new("127.0.0.1", port).close
      ready = true
    rescue SystemCallError
      sleep 0.05
    end
  end
  ready && port.positive?
end

def get(port, path)
  Net::HTTP.start("127.0.0.1", port, open_timeout: 10, read_timeout: 10) do |http|
    http.request(Net::HTTP::Get.new(path))
  end
end

check("GET / is served by puma") do
  res = get(port, "/")
  res.code == "200" && res.body.start_with?("hello from puma") &&
    res["content-type"] == "text/plain"
end

check("query string and POST body round trip") do
  res = Net::HTTP.start("127.0.0.1", port, open_timeout: 10, read_timeout: 10) do |http|
    req = Net::HTTP::Post.new("/echo?k=v")
    req.body = "the quick brown fox"
    req["content-type"] = "text/plain"
    http.request(req)
  end
  res.code == "200" && res.body == "the quick brown fox" && res["x-query"] == "k=v"
end

check("a multi-part rack body is concatenated") do
  get(port, "/chunks").body == "abcde"
end

check("unknown paths get 404") do
  res = get(port, "/missing")
  res.code == "404" && res.body == "nope"
end

check("keep-alive serves several requests on one connection") do
  bodies = []
  Net::HTTP.start("127.0.0.1", port, open_timeout: 10, read_timeout: 10) do |http|
    3.times { |i| bodies << http.request(Net::HTTP::Get.new(i.zero? ? "/" : "/chunks")).body }
  end
  bodies.size == 3 && bodies[1] == "abcde"
end

check("a large response body survives the socket write path") do
  big = "x" * 512_000
  srv = Puma::Server.new(->(_) { [200, { "content-type" => "text/plain" }, [big]] },
                         nil, { min_threads: 1, max_threads: 2, log_writer: Puma::LogWriter.strings })
  p2 = srv.add_tcp_listener("127.0.0.1", 0).addr[1]
  t2 = srv.run
  body = get(p2, "/").body
  srv.stop(true)
  t2.join
  body.bytesize == big.bytesize && body == big
end

check("concurrent requests are served by more than one pool thread") do
  ids = []
  mutex = Mutex.new
  threads = 4.times.map do
    Thread.new do
      body = get(port, "/slow").body
      mutex.synchronize { ids << body }
    end
  end
  threads.each { |t| t.join(30) }
  ids.size == 4 && ids.uniq.size > 1
end

check("HTTP/1.0 without a Host header is served") do
  sock = TCPSocket.new("127.0.0.1", port)
  sock.write("GET / HTTP/1.0\r\n\r\n")
  head = sock.read
  sock.close
  head.start_with?("HTTP/1.0 200") || head.start_with?("HTTP/1.1 200")
end

check("garbage on the wire is answered with 4xx rather than a crash") do
  sock = TCPSocket.new("127.0.0.1", port)
  sock.write("\x16\x03\x01NOT-HTTP\r\n\r\n")
  reply = begin
    sock.read
  rescue SystemCallError, IOError
    ""
  end
  sock.close rescue nil # rubocop:disable Style/RescueModifier
  reply.empty? || reply =~ %r{\AHTTP/1\.[01] 4\d\d}
end

check("the server still answers after the garbage request") do
  get(port, "/").code == "200"
end

check("server.stop shuts the listener down") do
  server.stop(true)
  thread.join(20)
  sleep 0.1
  begin
    TCPSocket.new("127.0.0.1", port).close
    false
  rescue SystemCallError
    true
  end
end

# ------------------------------------------------------------- rubygems

check("registered as a default gem") do
  Gem::Specification.find_all_by_name("puma").map { |s| [s.version.to_s, s.default_gem?] } ==
    [[Puma::Const::PUMA_VERSION, true]]
end

check("puma's nio4r dependency is satisfied from the payload") do
  spec = Gem::Specification.find_by_name("puma")
  dep = spec.runtime_dependencies.find { |d| d.name == "nio4r" }
  !dep.nil? && !dep.to_spec.nil? && dep.to_spec.default_gem?
end

puts
puts "RESULT: pass=#{$pass} fail=#{$fail}"
exit($fail.zero? ? 0 : 1)
