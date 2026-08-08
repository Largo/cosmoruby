#!/usr/bin/env ruby
# Benchmark: Compare allocators with 1M class allocations
# Reports heap stats every 100k allocations

TOTAL_CLASSES = 1_000_000
REPORT_INTERVAL = 100_000

def format_bytes(bytes)
  if bytes >= 1024 * 1024
    "%.2f MB" % (bytes / 1024.0 / 1024.0)
  elsif bytes >= 1024
    "%.2f KB" % (bytes / 1024.0)
  else
    "#{bytes} B"
  end
end

def report_stats(label, classes_created, start_time)
  gc_stat = GC.stat
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

  puts "\n=== #{label} (#{classes_created} classes) ==="
  puts "Time elapsed: %.3f seconds" % elapsed
  puts "Heap allocated pages: #{gc_stat[:heap_allocated_pages]}"
  puts "Heap live slots: #{gc_stat[:heap_live_slots]}"
  puts "Heap free slots: #{gc_stat[:heap_free_slots]}"
  puts "Total allocated objects: #{gc_stat[:total_allocated_objects]}"
  puts "Total freed objects: #{gc_stat[:total_freed_objects]}"
  puts "GC count: #{gc_stat[:count]}"
  puts "Major GC count: #{gc_stat[:major_gc_count]}"
  puts "Minor GC count: #{gc_stat[:minor_gc_count]}"

  # Memory from /proc/self/status if available
  if File.exist?('/proc/self/status')
    status = File.read('/proc/self/status')
    if status =~ /VmRSS:\s+(\d+)\s+kB/
      puts "RSS: #{format_bytes($1.to_i * 1024)}"
    end
    if status =~ /VmHWM:\s+(\d+)\s+kB/
      puts "Peak RSS (HWM): #{format_bytes($1.to_i * 1024)}"
    end
  end

  elapsed
end

puts "Ruby version: #{RUBY_VERSION}"
puts "Platform: #{RUBY_PLATFORM}"
puts "Description: #{RUBY_DESCRIPTION}"
puts "\nBenchmark: Creating #{TOTAL_CLASSES} dummy classes"
puts "Reporting every #{REPORT_INTERVAL} allocations"
puts "=" * 60

# Force initial GC to start clean
GC.start

# Store classes to prevent immediate GC
classes = []

start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
report_stats("Initial state", 0, start_time)

TOTAL_CLASSES.times do |i|
  # Create a unique class
  classes << Class.new

  # Report every REPORT_INTERVAL
  if (i + 1) % REPORT_INTERVAL == 0
    report_stats("After allocation", i + 1, start_time)
  end
end

final_time = report_stats("All allocations complete", TOTAL_CLASSES, start_time)

puts "\n" + "=" * 60
puts "PHASE 2: Testing GC with gradual release"
puts "=" * 60

# Now test freeing - release in batches
release_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

(TOTAL_CLASSES / REPORT_INTERVAL).times do |batch|
  # Release 100k classes
  REPORT_INTERVAL.times { classes.pop }

  # Force GC
  GC.start

  remaining = classes.length
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - release_start
  gc_stat = GC.stat

  puts "\n=== After releasing #{(batch + 1) * REPORT_INTERVAL} classes (#{remaining} remaining) ==="
  puts "Time since release start: %.3f seconds" % elapsed
  puts "Heap live slots: #{gc_stat[:heap_live_slots]}"
  puts "Heap free slots: #{gc_stat[:heap_free_slots]}"
  puts "GC count: #{gc_stat[:count]}"

  if File.exist?('/proc/self/status')
    status = File.read('/proc/self/status')
    if status =~ /VmRSS:\s+(\d+)\s+kB/
      puts "RSS: #{format_bytes($1.to_i * 1024)}"
    end
  end
end

total_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
puts "\n" + "=" * 60
puts "FINAL SUMMARY"
puts "=" * 60
puts "Total benchmark time: %.3f seconds" % total_time
puts "Allocation phase: %.3f seconds" % final_time
puts "Release/GC phase: %.3f seconds" % (total_time - final_time)

final_gc = GC.stat
puts "\nFinal GC stats:"
puts "  Total GC runs: #{final_gc[:count]}"
puts "  Major GC: #{final_gc[:major_gc_count]}"
puts "  Minor GC: #{final_gc[:minor_gc_count]}"
puts "  Heap allocated pages: #{final_gc[:heap_allocated_pages]}"
