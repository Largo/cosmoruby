require 'rack'
require 'webrick'
require 'stringio'

# Load the Rack app
app = Rack::Builder.parse_file('rack_app_simple.ru')

# Create WEBrick server with Rack handler
server = WEBrick::HTTPServer.new(Port: 9292)

# Mount the Rack app
server.mount_proc '/' do |req, res|
  # Convert WEBrick request to Rack env
  body_str = (req.body || '').b  # Force binary encoding
  rack_input = StringIO.new(body_str)
  rack_input.set_encoding(Encoding::ASCII_8BIT)

  env = {
    'REQUEST_METHOD' => req.request_method,
    'SCRIPT_NAME' => '',
    'PATH_INFO' => req.path,
    'QUERY_STRING' => req.query_string || '',
    'SERVER_NAME' => req.host || 'localhost',
    'SERVER_PORT' => req.port.to_s,
    'SERVER_PROTOCOL' => req.request_line.split(' ').last || 'HTTP/1.1',
    'rack.version' => [1, 3],
    'rack.input' => rack_input,
    'rack.errors' => $stderr,
    'rack.url_scheme' => 'http',
    'rack.multithread' => true,
    'rack.multiprocess' => false,
    'rack.run_once' => false
  }

  # Add HTTP headers
  req.header.each { |k, v| env["HTTP_#{k.upcase.tr('-', '_')}"] = v.join(', ') }

  # Call Rack app
  status, headers, body = app.call(env)

  # Set response
  res.status = status
  headers.each { |k, v| res[k.downcase] = v }  # Rack 3 uses lowercase headers
  body.each { |chunk| res.body << chunk }
  body.close if body.respond_to?(:close)
end

puts 'Starting Rack app on http://localhost:9292'
puts 'Press Ctrl+C to stop'

trap('INT') { server.shutdown }
server.start
