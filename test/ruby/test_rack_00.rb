#!/usr/bin/env ruby
# Test Rack gem installation

puts "=" * 60
puts "Testing Rack Gem"
puts "=" * 60
puts

# Test 1: Can we require rack?
puts "1. Testing require 'rack'..."
begin
  require 'rack'
  puts "   ✓ Rack loaded successfully"
  puts "   ✓ Rack version: #{Rack::VERSION}"
rescue LoadError => e
  puts "   ✗ Failed to load Rack: #{e.message}"
  exit 1
end

puts

# Test 2: Can we create a simple Rack app?
puts "2. Testing Rack application creation..."
begin
  app = lambda do |env|
    [
      200,
      { "Content-Type" => "text/plain" },
      ["Hello from Rack! Request path: #{env['PATH_INFO']}"]
    ]
  end
  puts "   ✓ Created Rack application (lambda)"
rescue => e
  puts "   ✗ Failed to create Rack app: #{e.message}"
  exit 1
end

puts

# Test 3: Can we use Rack::Builder?
puts "3. Testing Rack::Builder..."
begin
  app = Rack::Builder.new do
    use Rack::CommonLogger
    use Rack::ShowExceptions

    run lambda { |env|
      [200, {"Content-Type" => "text/html"}, ["<h1>Hello from Rack::Builder!</h1>"]]
    }
  end
  puts "   ✓ Rack::Builder works"
rescue => e
  puts "   ✗ Rack::Builder failed: #{e.message}"
  exit 1
end

puts

# Test 4: Can we create a mock request?
puts "4. Testing Rack::MockRequest..."
begin
  require 'rack/mock'

  simple_app = lambda { |env| [200, {"Content-Type" => "text/plain"}, ["Hello World"]] }

  request = Rack::MockRequest.new(simple_app)
  response = request.get("/")

  puts "   ✓ Mock request successful"
  puts "   ✓ Response status: #{response.status}"
  puts "   ✓ Response body: #{response.body}"
rescue => e
  puts "   ✗ Mock request failed: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

puts

# Test 5: Can we use Rack utilities?
puts "5. Testing Rack utilities..."
begin
  # Test query string parsing
  params = Rack::Utils.parse_query("foo=bar&baz=qux")
  puts "   ✓ Rack::Utils.parse_query: #{params.inspect}"

  # Test URL escaping
  escaped = Rack::Utils.escape("hello world")
  puts "   ✓ Rack::Utils.escape: #{escaped}"

  # Test MIME type lookup
  mime = Rack::Mime.mime_type('.html')
  puts "   ✓ Rack::Mime.mime_type('.html'): #{mime}"
rescue => e
  puts "   ✗ Rack utilities failed: #{e.message}"
  exit 1
end

puts
puts "=" * 60
puts "🎉 All Rack tests passed! 🎉"
puts "=" * 60
puts
puts "Rack is fully functional and ready to use!"
