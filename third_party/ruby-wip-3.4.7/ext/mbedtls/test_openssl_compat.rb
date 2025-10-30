#!/usr/bin/env ruby
# Test OpenSSL compatibility layer

require 'socket'
require 'openssl'

puts "=" * 60
puts "OpenSSL Compatibility Layer Test"
puts "=" * 60
puts

# Test 1: Module and constants
puts "Testing module structure..."
if defined?(OpenSSL::SSL)
  puts "✓ OpenSSL::SSL module defined"
else
  puts "✗ OpenSSL::SSL module not defined"
  exit 1
end

if defined?(OpenSSL::SSL::SSLSocket)
  puts "✓ OpenSSL::SSL::SSLSocket class defined"
else
  puts "✗ OpenSSL::SSL::SSLSocket class not defined"
  exit 1
end

if defined?(OpenSSL::SSL::VERIFY_PEER)
  puts "✓ OpenSSL::SSL::VERIFY_PEER constant defined (#{OpenSSL::SSL::VERIFY_PEER})"
else
  puts "✗ OpenSSL::SSL::VERIFY_PEER constant not defined"
  exit 1
end

puts

# Test 2: SSLContext creation
puts "Testing SSLContext..."
begin
  ctx = OpenSSL::SSL::SSLContext.new
  ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
  puts "✓ SSLContext created and configured"
rescue => e
  puts "✗ SSLContext failed: #{e.message}"
  exit 1
end

puts

# Test 3: HTTPS connection
puts "Testing HTTPS connection to example.com..."
begin
  tcp_socket = TCPSocket.new('example.com', 443)
  puts "✓ TCP connection established"

  ssl_socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, ctx)
  ssl_socket.hostname = 'example.com'
  puts "✓ SSLSocket created"

  ssl_socket.connect
  puts "✓ SSL handshake completed"

  request = "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n"
  ssl_socket.write(request)
  puts "✓ HTTP request sent"

  response = ssl_socket.read(1024)
  puts "✓ Response received (#{response.bytesize} bytes)"

  if response.include?("HTTP/1.1")
    puts "✓ Valid HTTP response"
  else
    puts "✗ Invalid response"
    exit 1
  end

  ssl_socket.close
  tcp_socket.close
  puts "✓ Connection closed cleanly"

rescue => e
  puts "✗ Test failed: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

puts
puts "✓✓✓ All OpenSSL compatibility tests passed! ✓✓✓"
puts
puts "Now testing with Net::HTTP..."

# Test 4: Net::HTTP integration
begin
  require 'net/http'

  uri = URI('https://example.com/')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER

  response = http.get(uri.path)

  if response.code == "200"
    puts "✓ Net::HTTP GET request successful"
    puts "✓ Response code: #{response.code}"
    puts "✓ Response body: #{response.body.bytesize} bytes"
  else
    puts "✗ Unexpected response code: #{response.code}"
    exit 1
  end

rescue => e
  puts "✗ Net::HTTP test failed: #{e.class}: #{e.message}"
  puts e.backtrace.first(10).join("\n")
  exit 1
end

puts
puts "🎉 All tests passed! OpenSSL compatibility layer is working! 🎉"
