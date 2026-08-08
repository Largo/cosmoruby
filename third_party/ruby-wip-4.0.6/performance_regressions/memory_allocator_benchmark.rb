#!/usr/bin/env ruby
# Benchmark: Memory allocator RSS growth
#
# Tests how RSS grows after many alloc/dealloc cycles.
# CosmoRuby shows ~2.85x RSS growth after 3M Class.new cycles.
# This may be due to Cosmopolitan's dlmalloc not returning pages to OS.
#
# Run with:
#   ruby memory_allocator_benchmark.rb [iterations]

ITERATIONS = (ARGV[0] || 1_000_000).to_i

puts "Ruby: #{RUBY_VERSION} #{RUBY_PLATFORM}"
puts "YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "Iterations: #{ITERATIONS}"
puts

def get_rss
  `ps -o rss= -p #{$$}`.to_i rescue 0
end

code = proc { Class.new }

# Warmup
1_000.times(&code)
GC.start
sleep 0.1

rss_start = get_rss
puts "RSS start: #{rss_start} KB"

start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# Run in chunks to observe memory growth pattern
chunk_size = ITERATIONS / 10
10.times do |i|
  chunk_size.times(&code)
  GC.start
  rss_now = get_rss
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
  growth = rss_start > 0 ? (rss_now.to_f / rss_start).round(2) : 0
  puts "After #{(i + 1) * chunk_size}: RSS #{rss_now} KB (#{growth}x) [#{elapsed.round(2)}s]"
end

GC.start
sleep 0.1
rss_end = get_rss

puts
puts "Final RSS: #{rss_end} KB"
puts "Total growth: #{(rss_end.to_f / rss_start).round(3)}x" if rss_start > 0
puts
puts "Expected: < 2.0x for test to pass"
