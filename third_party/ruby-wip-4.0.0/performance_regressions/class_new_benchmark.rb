#!/usr/bin/env ruby
# Benchmark: Class.new allocation performance
#
# CosmoRuby is ~3x slower than CRuby for this workload.
# This tests memory allocation/GC performance, not Ruby bytecode execution.
#
# Run with:
#   ruby class_new_benchmark.rb
#   ruby --yjit class_new_benchmark.rb

ITERATIONS = (ARGV[0] || 100_000).to_i

puts "Ruby: #{RUBY_VERSION} #{RUBY_PLATFORM}"
puts "YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "Iterations: #{ITERATIONS}"
puts

code = proc { Class.new }

# Warmup
1_000.times(&code)
GC.start

# Get baseline memory
rss_before = `ps -o rss= -p #{$$}`.to_i rescue 0

# Benchmark with GC enabled
GC.start
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
ITERATIONS.times(&code)
elapsed_gc = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

GC.start
rss_after = `ps -o rss= -p #{$$}`.to_i rescue 0

# Benchmark with GC disabled
GC.disable
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
ITERATIONS.times(&code)
elapsed_no_gc = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
GC.enable
GC.start

puts "With GC:    #{elapsed_gc.round(3)}s (#{(ITERATIONS / elapsed_gc).round(0)} ops/sec)"
puts "Without GC: #{elapsed_no_gc.round(3)}s (#{(ITERATIONS / elapsed_no_gc).round(0)} ops/sec)"
puts "GC overhead: #{((elapsed_gc - elapsed_no_gc) / elapsed_gc * 100).round(1)}%"
puts
puts "RSS: #{rss_before} => #{rss_after} KB (#{(rss_after.to_f / rss_before).round(2)}x)" if rss_before > 0
