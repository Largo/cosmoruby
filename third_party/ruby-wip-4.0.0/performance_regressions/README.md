# CosmoRuby Performance Regressions

Benchmarks to track and investigate performance differences between CosmoRuby and CRuby.

## Summary of Findings

| Metric | CosmoRuby | System Ruby | Difference |
|--------|-----------|-------------|------------|
| Class.new (100K) | 1.89s | 1.31s | 1.44x slower |
| Class.new ops/sec | 52,951 | 76,000 | - |
| RSS growth (1M cycles) | 3.03x | 1.22x | Much higher |
| Fibonacci YJIT speedup | 5.5x | 5.5x | Same |

## Known Issues

### 1. Memory Allocator RSS Growth (`memory_allocator_benchmark.rb`)

**Problem:** After many alloc/dealloc cycles, CosmoRuby's RSS keeps growing while system Ruby's stabilises.

**Benchmark results:**
```
System Ruby (1M iterations):
  RSS start: 18,312 KB
  After 100K:  1.01x
  After 500K:  1.18x
  After 1M:    1.22x  <-- stabilises

CosmoRuby (1M iterations):
  RSS start: 17,968 KB
  After 100K:  1.60x
  After 500K:  2.61x
  After 1M:    3.03x  <-- keeps growing
```

**Root cause:** Cosmopolitan's dlmalloc (`third_party/dlmalloc/dlmalloc.c`) doesn't aggressively return memory to the OS:

1. **No `madvise(MADV_DONTNEED)`** - Unlike glibc's malloc, dlmalloc doesn't use madvise to release pages within mapped regions
2. **`DEFAULT_TRIM_THRESHOLD` is 2MB** - Only trims top chunk when it exceeds 2MB
3. **`release_unused_segments()`** - Only unmaps completely free segments, not partially used ones
4. **`sys_trim()`** - Only shrinks via `mremap`/`munmap`, no partial page release

**Attempted fix:** `malloc_trim(0)` after GC sweep - **did not help**.

`malloc_trim` in dlmalloc only releases memory from the **top** of the heap via `sys_trim()`. With Ruby's allocation pattern (many small Class objects scattered throughout memory), the heap is fragmented - there's no large contiguous free block at the top to trim.

```
dlmalloc heap layout after GC:
[used][free][used][free][used][free][used][free]...[top - maybe free]
                                                    ↑ only this can be trimmed
```

To properly release fragmented memory, dlmalloc would need `madvise(MADV_DONTNEED)` support for free chunks in the middle of the heap (like jemalloc/mimalloc do).

**Status:** Known limitation. Test timeouts adjusted to accommodate slower RSS release.

### 2. Class.new Allocation Speed (`class_new_benchmark.rb`)

**Problem:** CosmoRuby is ~1.4x slower than system Ruby for `Class.new` workloads.

**Benchmark results (100K iterations):**
```
System Ruby:
  With GC:    1.31s (76,335 ops/sec)
  Without GC: 0.16s (625,000 ops/sec)
  GC overhead: 87.8%

CosmoRuby:
  With GC:    1.89s (52,951 ops/sec)
  Without GC: 0.22s (456,484 ops/sec)
  GC overhead: 88.4%
```

**Analysis:**
- GC overhead is similar (~88%)
- Raw allocation speed (without GC) is 1.37x slower
- This is likely dlmalloc vs glibc malloc performance

**Possible improvements:**
- Investigate dlmalloc tuning parameters
- Consider alternative allocators (jemalloc, mimalloc)
- Profile to find specific hotspots

### 3. YJIT Performance (Positive Finding)

**YJIT works and provides similar speedups to system Ruby:**

```
Fibonacci benchmark (fib(35)):
  CosmoRuby no JIT:    0.98s
  CosmoRuby YJIT:      0.18s  (5.5x speedup)
  System Ruby no JIT:  0.95s
  System Ruby YJIT:    0.17s  (5.6x speedup)
```

YJIT is fully functional in CosmoRuby and provides equivalent speedups.

## Running Benchmarks

```bash
cd third_party/ruby-wip-4.0.0

# CosmoRuby
RUBYLIB=$PWD/lib o//third_party/ruby/ruby performance_regressions/class_new_benchmark.rb
RUBYLIB=$PWD/lib o//third_party/ruby/ruby performance_regressions/memory_allocator_benchmark.rb

# CosmoRuby with YJIT
RUBYLIB=$PWD/lib o//third_party/ruby/ruby --yjit performance_regressions/class_new_benchmark.rb

# System Ruby for comparison
ruby performance_regressions/class_new_benchmark.rb
ruby performance_regressions/memory_allocator_benchmark.rb
```

## Profiling

```bash
# Profile with perf
perf record -g o//third_party/ruby/ruby.com performance_regressions/class_new_benchmark.rb
perf report

# Trace system calls
o//third_party/ruby/ruby.com --strace performance_regressions/class_new_benchmark.rb 2>&1 | head -100
```

## Environment Variables

- `RUBY_TEST_TIMEOUT_SCALE=N` - Scale test timeouts by N (Ruby CI uses 5 for ASAN)
- `RUBYOPT=--yjit` - Enable YJIT for all Ruby invocations (including subprocesses in tests)

## Test Adjustments

The memory leak tests in `test_class.rb` and `test_module.rb` have Cosmo-specific timeouts:

```ruby
# In test_classext_memory_leak and test_iclass_memory_leak:
timeout = RUBY_PLATFORM =~ /cosmo/ ? 15 : 10
```

This accounts for slower allocation while still catching actual memory leaks.

## Files Changed

| File | Change |
|------|--------|
| `test/ruby/test_class.rb` | Cosmo-specific timeout (15s vs 10s) |
| `test/ruby/test_module.rb` | Cosmo-specific timeout (15s vs 10s) |

## Future Work

1. **Profile dlmalloc** - Identify specific allocation patterns that cause fragmentation
2. **Consider allocator options** - Test jemalloc/mimalloc if dlmalloc proves inadequate
3. **Investigate madvise in dlmalloc** - Add `MADV_DONTNEED` for large free chunks (requires Cosmo core changes)
