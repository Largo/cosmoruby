/* -*- mode: c; indent-tabs-mode: nil; tab-width: 2; c-basic-offset: 2 -*- */
/* vi: set et ts=2 sw=2 fenc=utf-8 :vi */
/*
 * Cosmopolitan platform primitives for mimalloc
 *
 * This file implements the platform abstraction layer that mimalloc requires
 * using Cosmopolitan's portable APIs.
 */

#include "libc/calls/calls.h"
#include "libc/calls/struct/timespec.h"
#include "libc/calls/weirdtypes.h"
#include "libc/errno.h"
#include "libc/intrin/atomic.h"
#include "libc/mem/mem.h"
#include "libc/runtime/runtime.h"
#include "libc/str/str.h"
#include "libc/sysv/consts/madv.h"
#include "libc/sysv/consts/map.h"
#include "libc/sysv/consts/o.h"
#include "libc/sysv/consts/prot.h"
#include "libc/sysv/consts/clock.h"
#include "libc/fmt/conv.h"

#include "mimalloc.h"
#include "mimalloc/internal.h"
#include "mimalloc/prim.h"

/* ------------------------------------------------------------------------- */
/* Constants                                                                 */
/* ------------------------------------------------------------------------- */

#define MI_COSMO_LARGE_PAGE_SIZE (2 * 1024 * 1024)  /* 2 MiB */

/* ------------------------------------------------------------------------- */
/* Memory Configuration Initialisation                                       */
/* ------------------------------------------------------------------------- */

void _mi_prim_mem_init(mi_os_mem_config_t* config) {
  /* Use Cosmopolitan's page size detection */
  config->page_size = getpagesize();
  config->alloc_granularity = config->page_size;
  config->large_page_size = MI_COSMO_LARGE_PAGE_SIZE;

  /* Get physical memory size */
  config->physical_memory_in_kib = 0;
#if defined(__linux__)
  /* Try to read from /proc/meminfo on Linux */
  int fd = open("/proc/meminfo", O_RDONLY);
  if (fd >= 0) {
    char buf[256];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n > 0) {
      buf[n] = '\0';
      /* Look for "MemTotal:" line */
      const char* p = strstr(buf, "MemTotal:");
      if (p) {
        p += 9; /* Skip "MemTotal:" */
        while (*p == ' ') p++;
        config->physical_memory_in_kib = (size_t)strtol(p, NULL, 10);
      }
    }
    close(fd);
  }
#endif
  if (config->physical_memory_in_kib == 0) {
    /* Default: assume 4 GiB if we can't detect */
    config->physical_memory_in_kib = 4 * 1024 * 1024;
  }

  /* Virtual address bits - must match MI_MAX_VABITS in bits.h */
#if defined(__x86_64__) || defined(_M_X64)
  config->virtual_address_bits = 47;  /* x64 uses 47 bits (MI_ARCH_X64) */
#elif INTPTR_MAX == INT64_MAX
  config->virtual_address_bits = 48;  /* Other 64-bit uses 48 bits */
#else
  config->virtual_address_bits = 32;  /* 32-bit */
#endif

  /* OS capabilities */
  config->has_overcommit = true;         /* Most Unix systems overcommit */
  config->has_partial_free = true;       /* mmap can free in parts */
  config->has_virtual_reserve = true;    /* mmap PROT_NONE works */
  config->has_transparent_huge_pages = false;  /* Disabled for portability */
}

/* ------------------------------------------------------------------------- */
/* Memory Allocation                                                         */
/* ------------------------------------------------------------------------- */

int _mi_prim_free(void* addr, size_t size) {
  if (size == 0) return 0;
  int err = munmap(addr, size);
  return (err == -1) ? errno : 0;
}

static void* cosmo_mmap(void* addr, size_t size, int protect_flags, int flags, int fd) {
  void* p = mmap(addr, size, protect_flags, flags, fd, 0);
  if (p == MAP_FAILED) return NULL;
  return p;
}

int _mi_prim_alloc(void* hint_addr, size_t size, size_t try_alignment,
                   bool commit, bool allow_large, bool* is_large,
                   bool* is_zero, void** addr) {
  mi_assert_internal(size > 0);
  mi_assert_internal(commit || !allow_large);
  mi_assert_internal(try_alignment > 0);

  *is_zero = true;
  *is_large = false;

  int protect_flags = commit ? (PROT_READ | PROT_WRITE) : PROT_NONE;
  int flags = MAP_PRIVATE | MAP_ANONYMOUS;

  /* Try large pages if allowed and beneficial */
  if (allow_large && size >= MI_COSMO_LARGE_PAGE_SIZE) {
#if defined(MAP_HUGETLB)
    if (IsLinux()) {
      void* p = cosmo_mmap(hint_addr, size, protect_flags,
                           flags | MAP_HUGETLB, -1);
      if (p != NULL) {
        *is_large = true;
        *addr = p;
        return 0;
      }
      /* Fall through to regular allocation */
    }
#endif
  }

  /* Regular allocation */
  void* p = cosmo_mmap(hint_addr, size, protect_flags, flags, -1);

  /* If alignment is important and we didn't get it, try harder */
  if (p != NULL && try_alignment > 1 && ((uintptr_t)p % try_alignment) != 0) {
    /* Unmap and try with overallocation */
    munmap(p, size);
    size_t alloc_size = size + try_alignment;
    p = cosmo_mmap(NULL, alloc_size, protect_flags, flags, -1);
    if (p != NULL) {
      /* Calculate aligned address */
      uintptr_t aligned = ((uintptr_t)p + try_alignment - 1) & ~(try_alignment - 1);
      /* Trim excess */
      size_t prefix = aligned - (uintptr_t)p;
      size_t suffix = alloc_size - size - prefix;
      if (prefix > 0) munmap(p, prefix);
      if (suffix > 0) munmap((void*)(aligned + size), suffix);
      p = (void*)aligned;
    }
  }

  *addr = p;
  return (p != NULL) ? 0 : errno;
}

/* ------------------------------------------------------------------------- */
/* Memory Commit/Decommit                                                    */
/* ------------------------------------------------------------------------- */

int _mi_prim_commit(void* addr, size_t size, bool* is_zero) {
  *is_zero = false;
  int err = mprotect(addr, size, PROT_READ | PROT_WRITE);
  return (err != 0) ? errno : 0;
}

int _mi_prim_decommit(void* addr, size_t size, bool* needs_recommit) {
  int err = 0;
  /* Use MADV_DONTNEED to release memory back to OS */
#if defined(MADV_DONTNEED)
  err = madvise(addr, size, MADV_DONTNEED);
#endif
  *needs_recommit = false;
  return (err != 0) ? errno : 0;
}

int _mi_prim_reset(void* addr, size_t size) {
  int err = 0;
#if defined(MADV_FREE)
  err = madvise(addr, size, MADV_FREE);
  if (err != 0 && errno == EINVAL) {
    /* MADV_FREE not supported, try MADV_DONTNEED */
    err = madvise(addr, size, MADV_DONTNEED);
  }
#elif defined(MADV_DONTNEED)
  err = madvise(addr, size, MADV_DONTNEED);
#endif
  return (err != 0) ? errno : 0;
}

int _mi_prim_reuse(void* addr, size_t size) {
  MI_UNUSED(addr);
  MI_UNUSED(size);
  /* No special action needed on most platforms */
  return 0;
}

int _mi_prim_protect(void* addr, size_t size, bool protect) {
  int prot = protect ? PROT_NONE : (PROT_READ | PROT_WRITE);
  int err = mprotect(addr, size, prot);
  return (err != 0) ? errno : 0;
}

/* ------------------------------------------------------------------------- */
/* Huge Pages                                                                */
/* ------------------------------------------------------------------------- */

int _mi_prim_alloc_huge_os_pages(void* hint_addr, size_t size, int numa_node,
                                  bool* is_zero, void** addr) {
  MI_UNUSED(hint_addr);
  MI_UNUSED(numa_node);
  *is_zero = true;

#if defined(MAP_HUGETLB) && defined(MAP_HUGE_1GB)
  if (IsLinux()) {
    int flags = MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB | MAP_HUGE_1GB;
    void* p = mmap(hint_addr, size, PROT_READ | PROT_WRITE, flags, -1, 0);
    if (p != MAP_FAILED) {
      *addr = p;
      return 0;
    }
  }
#endif

  /* Huge pages not available */
  *addr = NULL;
  return ENOMEM;
}

/* ------------------------------------------------------------------------- */
/* NUMA Support                                                              */
/* ------------------------------------------------------------------------- */

size_t _mi_prim_numa_node(void) {
  /* Cosmopolitan doesn't expose NUMA directly; return 0 */
  return 0;
}

size_t _mi_prim_numa_node_count(void) {
  /* Assume single NUMA node for portability */
  return 1;
}

/* ------------------------------------------------------------------------- */
/* Clock                                                                     */
/* ------------------------------------------------------------------------- */

mi_msecs_t _mi_prim_clock_now(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ((mi_msecs_t)ts.tv_sec * 1000) + ((mi_msecs_t)ts.tv_nsec / 1000000);
}

/* ------------------------------------------------------------------------- */
/* Process Information                                                       */
/* ------------------------------------------------------------------------- */

void _mi_prim_process_info(mi_process_info_t* pinfo) {
  /* Simplified: don't use getrusage to avoid LIBC_PROC circular dependency.
   * The pinfo struct should already be zero-initialized by caller. */
  MI_UNUSED(pinfo);
}

/* ------------------------------------------------------------------------- */
/* Output                                                                    */
/* ------------------------------------------------------------------------- */

void _mi_prim_out_stderr(const char* msg) {
  if (msg != NULL) {
    size_t len = strlen(msg);
    write(2, msg, len);  /* Write directly to stderr (fd 2) */
  }
}

/* ------------------------------------------------------------------------- */
/* Environment Variables                                                     */
/* ------------------------------------------------------------------------- */

extern char** environ;

bool _mi_prim_getenv(const char* name, char* result, size_t result_size) {
  if (name == NULL || result == NULL || result_size < 1) return false;

  size_t len = strlen(name);
  if (len == 0) return false;

  char** env = environ;
  if (env == NULL) return false;

  for (int i = 0; i < 10000 && env[i] != NULL; i++) {
    const char* s = env[i];
    if (strncasecmp(name, s, len) == 0 && s[len] == '=') {
      /* Found it - copy value */
      const char* val = s + len + 1;
      size_t vlen = strlen(val);
      if (vlen >= result_size) vlen = result_size - 1;
      memcpy(result, val, vlen);
      result[vlen] = '\0';
      return true;
    }
  }

  return false;
}

/* ------------------------------------------------------------------------- */
/* Random                                                                    */
/* ------------------------------------------------------------------------- */

bool _mi_prim_random_buf(void* buf, size_t buf_len) {
  /* Try getrandom syscall on Linux */
#if defined(__linux__)
  extern long getrandom(void*, size_t, unsigned int);
  ssize_t ret = getrandom(buf, buf_len, 0);
  if (ret >= 0 && (size_t)ret == buf_len) return true;
#endif

  /* Fallback to /dev/urandom */
  int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
  if (fd < 0) return false;

  size_t count = 0;
  while (count < buf_len) {
    ssize_t ret = read(fd, (char*)buf + count, buf_len - count);
    if (ret <= 0) {
      if (errno == EINTR || errno == EAGAIN) continue;
      break;
    }
    count += ret;
  }
  close(fd);
  return (count == buf_len);
}

/* ------------------------------------------------------------------------- */
/* Thread Support                                                            */
/* ------------------------------------------------------------------------- */

/* Simplified: no-op implementations to avoid LIBC_MEM circular dependency.
 * Thread cleanup will happen at process exit instead of per-thread. */

void _mi_prim_thread_init_auto_done(void) {
  /* No-op: pthread_key_* would cause circular dependency */
}

void _mi_prim_thread_done_auto_done(void) {
  /* No-op */
}

void _mi_prim_thread_associate_default_theap(mi_theap_t* theap) {
  MI_UNUSED(theap);
  /* No-op */
}

bool _mi_prim_thread_is_in_threadpool(void) {
  return false;
}

/* ------------------------------------------------------------------------- */
/* Allocator Initialisation (called from MI_PRIM_HAS_ALLOCATOR_INIT)         */
/* ------------------------------------------------------------------------- */

bool _mi_is_redirected(void) {
  return false;
}

bool _mi_allocator_init(const char** message) {
  if (message != NULL) *message = NULL;
  return true;
}

void _mi_allocator_done(void) {
  /* Nothing to do */
}

/* ------------------------------------------------------------------------- */
/* Process Initialisation (called from MI_PRIM_HAS_PROCESS_ATTACH)           */
/* ------------------------------------------------------------------------- */

/*
 * These are called by our constructor/destructor instead of mimalloc's
 * automatic process attach. This is declared at the end of the file to
 * ensure mimalloc internal headers are already processed.
 */
extern void _mi_auto_process_init(void);
extern void _mi_auto_process_done(void);

__attribute__((constructor(50)))
static void mi_cosmo_process_init(void) {
  _mi_auto_process_init();
}

__attribute__((destructor(50)))
static void mi_cosmo_process_done(void) {
  _mi_auto_process_done();
}
