#!/usr/bin/env ruby
# Benchmark: YJIT JIT compiler performance
#
# Tests computational workloads where YJIT provides significant speedups.
# Expected: ~5x speedup with YJIT enabled.
#
# Run with:
#   ruby yjit_benchmark.rb           # No JIT
#   ruby --yjit yjit_benchmark.rb    # With YJIT

N = (ARGV[0] || 35).to_i

puts "Ruby: #{RUBY_VERSION} #{RUBY_PLATFORM}"
puts "YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts

def fib(n)
  return n if n < 2
  fib(n - 1) + fib(n - 2)
end

def tak(x, y, z)
  if y < x
    tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y))
  else
    z
  end
end

# Warmup
fib(20)
tak(10, 5, 0)

puts "=== Fibonacci(#{N}) ==="
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
result = fib(N)
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "Result: #{result}"
puts "Time: #{elapsed.round(3)}s"
puts

puts "=== Tak(18, 12, 6) ==="
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
result = tak(18, 12, 6)
elapsed_tak = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "Result: #{result}"
puts "Time: #{elapsed_tak.round(3)}s"
puts

puts "=== String operations (1M iterations) ==="
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
1_000_000.times do |i|
  s = "hello world #{i}"
  s.upcase
  s.split
  s.gsub('o', '0')
end
elapsed_str = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "Time: #{elapsed_str.round(3)}s"
puts

puts "=== Array operations (100K iterations) ==="
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
100_000.times do
  arr = (1..100).to_a
  arr.map { |x| x * 2 }
  arr.select { |x| x.even? }
  arr.reduce(0, :+)
end
elapsed_arr = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "Time: #{elapsed_arr.round(3)}s"
puts

total = elapsed + elapsed_tak + elapsed_str + elapsed_arr
puts "=== Total: #{total.round(3)}s ==="
