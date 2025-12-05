#!/usr/bin/env ruby
# Test gem path detection logic

require 'rubygems'

puts "=" * 60
puts "Gem Path Detection Debug"
puts "=" * 60
puts

puts "GEM_HOME environment variable set: #{ENV.key?('GEM_HOME')}"
puts "GEM_HOME value: #{ENV['GEM_HOME'].inspect}"
puts

puts "Gem.dir: #{Gem.dir}"
puts "Gem.dir exists: #{File.exist?(Gem.dir)}"
puts "Gem.dir writable: #{File.writable?(Gem.dir)}"
puts

puts "Gem.user_dir: #{Gem.user_dir}"
puts "Gem.user_dir exists: #{File.exist?(Gem.user_dir)}"
puts "Gem.user_dir writable: #{File.writable?(Gem.user_dir) rescue 'N/A (does not exist)'}"
puts

puts "Gem.default_user_install: #{Gem.default_user_install}"
puts

puts "Gem.path:"
Gem.path.each_with_index do |path, i|
  puts "  #{i+1}. #{path}"
  puts "     exists: #{File.exist?(path)}, writable: #{File.writable?(path)}"
end
