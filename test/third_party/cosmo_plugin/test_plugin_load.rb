#!/usr/bin/env ruby
# Test script for cosmo plugin loading

require 'test/unit'

class TestCosmoPluginLoad < Test::Unit::TestCase
  def test_load_archive_extension
    # Try to require the .a archive
    archive_path = File.expand_path('../../../o//test/third_party/cosmo_plugin/test_hello.a', __FILE__)

    puts "Looking for archive at: #{archive_path}"
    assert File.exist?(archive_path), "Archive file should exist at #{archive_path}"

    # Load the plugin
    require archive_path

    # Test that the module is defined
    assert defined?(TestHello), "TestHello module should be defined after loading"

    # Test the world method
    result = TestHello.world
    assert_equal "Hello from plugin!", result
    puts "✓ TestHello.world => #{result.inspect}"

    # Test the add method
    sum = TestHello.add(3, 4)
    assert_equal 7, sum
    puts "✓ TestHello.add(3, 4) => #{sum}"
  end
end
