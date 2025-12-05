#!/usr/bin/env ruby
# Test Rack with WEBrick directly

require 'rack'
require 'webrick'

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
      <p><strong>Query String:</strong> #{env['QUERY_STRING']}</p>
      <hr>
      <p><a href="/">Refresh</a></p>
    </body>
    </html>
  HTML

  [200, { "Content-Type" => "text/html" }, [body]]
end

# Use WEBrick directly with Rack
server = WEBrick::HTTPServer.new(Port: 9292)

server.mount_proc '/' do |req, res|
  # Build Rack env from WEBrick request
  env = {
    'REQUEST_METHOD' => req.request_method,
    'PATH_INFO' => req.path,
    'QUERY_STRING' => req.query_string || '',
    'SERVER_NAME' => req.host,
    'SERVER_PORT' => server.config[:Port].to_s,
    'rack.version' => Rack::VERSION,
    'rack.url_scheme' => 'http',
    'rack.input' => StringIO.new(req.body || ''),
    'rack.errors' => $stderr,
    'rack.multithread' => false,
    'rack.multiprocess' => false,
    'rack.run_once' => false
  }

  # Call Rack app
  status, headers, body = app.call(env)

  # Build WEBrick response
  res.status = status
  headers.each { |key, value| res[key] = value }
  body.each { |chunk| res.body << chunk }
end

puts "Rack app running on http://localhost:9292"
puts "Press Ctrl+C to stop"

trap('INT') { server.shutdown }

server.start
