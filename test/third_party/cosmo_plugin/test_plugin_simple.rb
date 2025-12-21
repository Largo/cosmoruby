#!/usr/bin/env ruby
# Simple test for cosmo plugin loading (no test framework needed)

# Use absolute path
archive_path = File.absolute_path('o//test/third_party/cosmo_plugin/test_hello.a')

puts "Testing Cosmo Plugin Loader"
puts "=" * 50
puts "Archive path: #{archive_path}"
puts "Archive exists: #{File.exist?(archive_path)}"
puts

if !File.exist?(archive_path)
  puts "ERROR: Archive not found!"
  exit 1
end

puts "Attempting to load plugin..."

# Try different loading methods
methods = [
  -> { require archive_path },
  -> { load archive_path },
  -> {
    dir = File.dirname(archive_path)
    base = File.basename(archive_path, '.a')
    $LOAD_PATH.unshift(dir)
    require base
  }
]

success = false
methods.each_with_index do |method, i|
  puts "  Trying method #{i+1}..."
  begin
    method.call
    puts "✓ Plugin loaded successfully with method #{i+1}!"
    success = true
    break
  rescue Exception => e
    puts "  Method #{i+1} failed: #{e.class}: #{e.message.split("\n").first}"
  end
end

unless success
  puts "✗ All loading methods failed!"
  exit 1
end

puts
puts "Checking if TestHello module is defined..."
if defined?(TestHello)
  puts "✓ TestHello module is defined"
else
  puts "✗ TestHello module NOT defined"
  exit 1
end

puts
puts "Testing TestHello.world method..."
begin
  result = TestHello.world
  if result == "Hello from plugin!"
    puts "✓ TestHello.world returned: #{result.inspect}"
  else
    puts "✗ Unexpected result: #{result.inspect}"
    exit 1
  end
rescue => e
  puts "✗ Method call failed: #{e.class}: #{e.message}"
  exit 1
end

puts
puts "Testing TestHello.add method..."
begin
  sum = TestHello.add(3, 4)
  if sum == 7
    puts "✓ TestHello.add(3, 4) returned: #{sum}"
  else
    puts "✗ Unexpected result: #{sum} (expected 7)"
    exit 1
  end
rescue => e
  puts "✗ Method call failed: #{e.class}: #{e.message}"
  exit 1
end

puts
puts "=" * 50
puts "ALL TESTS PASSED! 🎉"
puts "Plugin loading system is working correctly!"
