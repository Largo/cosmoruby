#!/usr/bin/env ruby
# Test script for MbedTLS Ruby extension

require 'socket'
require 'mbedtls'

def test_https_connection
  puts "Testing HTTPS connection to example.com..."

  begin
    # Open TCP connection
    socket = TCPSocket.new('example.com', 443)
    puts "✓ TCP connection established"

    # Wrap with SSL
    ssl = MbedTLS::SSL.new(socket, hostname: 'example.com', verify: true)
    puts "✓ SSL context created"

    # Perform handshake
    ssl.connect
    puts "✓ SSL handshake completed"

    # Send HTTP request
    request = "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n"
    bytes_written = ssl.write(request)
    puts "✓ Sent #{bytes_written} bytes"

    # Read response
    response = ""
    loop do
      chunk = ssl.read(4096)
      break if chunk.empty?
      response += chunk
    end
    puts "✓ Received #{response.length} bytes"

    # Check response
    if response.include?("HTTP/1.1")
      puts "✓ Valid HTTP response received"
      puts "\nFirst 200 characters of response:"
      puts response[0...200]
      puts "..."
    else
      puts "✗ Invalid response"
      return false
    end

    # Close connection
    ssl.close
    socket.close
    puts "✓ Connection closed cleanly"

    puts "\n✓✓✓ All tests passed! ✓✓✓"
    return true

  rescue => e
    puts "✗ Test failed: #{e.class}: #{e.message}"
    puts e.backtrace.join("\n")
    return false
  end
end

def test_module_loaded
  puts "Testing MbedTLS module..."

  if defined?(MbedTLS)
    puts "✓ MbedTLS module loaded"
  else
    puts "✗ MbedTLS module not loaded"
    return false
  end

  if defined?(MbedTLS::SSL)
    puts "✓ MbedTLS::SSL class defined"
  else
    puts "✗ MbedTLS::SSL class not defined"
    return false
  end

  if defined?(MbedTLS::SSLError)
    puts "✓ MbedTLS::SSLError exception defined"
  else
    puts "✗ MbedTLS::SSLError exception not defined"
    return false
  end

  return true
end

# Run tests
puts "=" * 60
puts "MbedTLS Ruby Extension Test Suite"
puts "=" * 60
puts

if test_module_loaded
  puts
  test_https_connection
else
  puts "\n✗✗✗ Module loading tests failed ✗✗✗"
  exit 1
end
