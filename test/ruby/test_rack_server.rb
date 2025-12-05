#!/usr/bin/env ruby
# Simple Rack server without WEBrick

require 'rack'
require 'socket'

# Simple Rack app
app = lambda do |env|
  body = <<-HTML
    <!DOCTYPE html>
    <html>
    <head><title>Cosmopolitan Ruby + Rack</title></head>
    <body>
      <h1>Hello from Cosmopolitan Ruby + Rack!</h1>
      <p><strong>Ruby Version:</strong> #{RUBY_VERSION}</p>
      <p><strong>Rack Version:</strong> #{Rack::VERSION}</p>
      <p><strong>Request Method:</strong> #{env['REQUEST_METHOD']}</p>
      <p><strong>Request Path:</strong> #{env['PATH_INFO']}</p>
    </body>
    </html>
  HTML

  [200, { "Content-Type" => "text/html" }, [body]]
end

# Simple HTTP server
server = TCPServer.new('localhost', 9292)
puts "Rack app running on http://localhost:9292"
puts "Press Ctrl+C to stop"

loop do
  client = server.accept

  # Read HTTP request
  request_line = client.gets
  break unless request_line

  # Parse request
  method, path, _ = request_line.split

  # Read headers
  headers = {}
  while (line = client.gets) && line != "\r\n"
    key, value = line.split(': ', 2)
    headers[key] = value.strip if value
  end

  # Build Rack env
  env = {
    'REQUEST_METHOD' => method,
    'PATH_INFO' => path,
    'QUERY_STRING' => '',
    'SERVER_NAME' => 'localhost',
    'SERVER_PORT' => '9292',
    'rack.version' => Rack::VERSION,
    'rack.url_scheme' => 'http',
    'rack.input' => StringIO.new,
    'rack.errors' => $stderr,
    'rack.multithread' => false,
    'rack.multiprocess' => false,
    'rack.run_once' => false
  }

  # Call Rack app
  status, response_headers, body = app.call(env)

  # Send response
  client.print "HTTP/1.1 #{status} OK\r\n"
  response_headers.each do |key, value|
    client.print "#{key}: #{value}\r\n"
  end
  client.print "\r\n"
  body.each { |chunk| client.print chunk }
  client.close

  puts "#{Time.now} - #{method} #{path} - #{status}"
end
