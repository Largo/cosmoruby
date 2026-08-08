puts RUBY_DESCRIPTION
puts RUBY_PLATFORM
require "json"
puts JSON.generate({ok: true, n: 1+1})
p defined?(Gem)
p Gem.default_dir rescue p $!
File.write("wintest.txt", "hello from ruby\n")
puts File.read("wintest.txt").strip
File.delete("wintest.txt")
p ARGV
require "digest"
puts Digest::SHA256.hexdigest("abc")[0,16]
require "stringio"
require "set"
require "yaml"
require "zlib"
puts "stdlib-ok"
t = Thread.new { 40 + 2 }
puts t.value
exit 7
