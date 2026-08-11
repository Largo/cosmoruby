#ifndef YJIT_H
#define YJIT_H 1
//
// This file contains definitions YJIT exposes to the CRuby codebase
//

#include "ruby/internal/config.h"
#include "ruby_assert.h" // for RUBY_DEBUG
#include "vm_core.h"
#include "method.h"

#ifdef __COSMOPOLITAN__
# include "libc/dce.h"   // for IsLinux()
#endif

// YJIT_STATS controls whether to support runtime counters in the interpreter
#ifndef YJIT_STATS
# define YJIT_STATS (USE_YJIT && RUBY_DEBUG)
#endif

// ===========================================================================
// CosmoRuby: cosmo_yjit_usable() -- the single predicate that decides whether
// the YJIT *Rust staticlib* can actually be executed by the process we are.
//
// A cosmopolitan APE is one file that runs on several OSes and (when fat) two
// architectures, but YJIT's Rust half is built exactly once, for
// x86_64-unknown-linux-gnu:
//
//   * on the aarch64 half of a fat APE it is not linked at all
//     (yjit/BUILD.mk forces RUBY_YJIT_ENABLED=0), so the __attribute__((weak))
//     stubs at the bottom of yjit.c are the whole implementation;
//   * on Windows/macOS/BSD the staticlib *is* linked -- it is the same x86-64
//     image -- but its global state is never initialised, because rb_yjit_init()
//     is not called there, and several of its entry points then dereference
//     null.  That is the family of bugs recorded in PORTING-NOTES.md:
//     rb_yjit_init_builtin_cmes() (every 4.0.6 APE segfaulted at VM init on
//     Windows) and rb_yjit_enable() (every Rails 8 app segfaulted at boot on
//     Windows, because Rails enables YJIT from config.yjit).
//
// **Rule**: a function implemented in the YJIT Rust staticlib may be called
// from C only when cosmo_yjit_usable() is true, or from a path that cannot be
// reached unless rb_yjit_enabled_p is true (which implies rb_yjit_init() ran,
// which implies cosmo_yjit_usable()).  Every Ruby-visible entry point --
// everything RubyVM::YJIT exposes -- goes through the guarded shims in yjit.c.
// When the guard fires the answer must be an honest "YJIT is not running here"
// (false / nil / no-op), never an exception and never a wrong value.
//
// Off cosmopolitan this is a compile-time `true` and everything below folds
// away, so upstream behaviour is untouched.
// ===========================================================================
static inline bool
cosmo_yjit_usable(void)
{
#if !USE_YJIT
    return false;
#elif !defined(__COSMOPOLITAN__)
    return true;
#elif defined(__x86_64__)
    return IsLinux();
#else
    return false;   // aarch64: the Rust staticlib was never built
#endif
}

#if USE_YJIT

// We generate x86 or arm64 assembly
#if defined(_WIN32) ? defined(_M_AMD64) : (defined(__x86_64__) || defined(__aarch64__))
// x86_64 platforms without mingw/msys or x64-mswin
#else
# error YJIT unsupported platform
#endif

// Expose these as declarations since we are building YJIT.
extern uint64_t rb_yjit_call_threshold;
extern uint64_t rb_yjit_cold_threshold;
extern uint64_t rb_yjit_live_iseq_count;
extern uint64_t rb_yjit_iseq_alloc_count;
extern bool rb_yjit_enabled_p;
void rb_yjit_incr_counter(const char *counter_name);
void rb_yjit_invalidate_all_method_lookup_assumptions(void);
void rb_yjit_cme_invalidate(rb_callable_method_entry_t *cme);
void rb_yjit_collect_binding_alloc(void);
void rb_yjit_collect_binding_set(void);
void rb_yjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception);
void rb_yjit_init_builtin_cmes(void);
void rb_yjit_init(bool yjit_enabled);
void rb_yjit_free_at_exit(void);
void rb_yjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop);
void rb_yjit_constant_state_changed(ID id);
void rb_yjit_iseq_mark(void *payload);
void rb_yjit_iseq_update_references(const rb_iseq_t *iseq);
void rb_yjit_iseq_free(const rb_iseq_t *iseq);
void rb_yjit_before_ractor_spawn(void);
void rb_yjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx);
void rb_yjit_tracing_invalidate_all(void);
void rb_yjit_show_usage(int help, int highlight, unsigned int width, int columns);
void rb_yjit_lazy_push_frame(const VALUE *pc);
void rb_yjit_invalidate_no_singleton_class(VALUE klass);
void rb_yjit_invalidate_ep_is_bp(const rb_iseq_t *iseq);
void rb_yjit_mark_all_writeable(void);
void rb_yjit_mark_all_executable(void);

#else
// !USE_YJIT
// In these builds, YJIT could never be turned on. Provide dummy implementations.

#define rb_yjit_enabled_p false
static inline void rb_yjit_incr_counter(const char *counter_name) {}
static inline void rb_yjit_invalidate_all_method_lookup_assumptions(void) {}
static inline void rb_yjit_cme_invalidate(rb_callable_method_entry_t *cme) {}
static inline void rb_yjit_collect_binding_alloc(void) {}
static inline void rb_yjit_collect_binding_set(void) {}
static inline void rb_yjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception) {}
static inline void rb_yjit_init_builtin_cmes(void) {}
static inline void rb_yjit_init(bool yjit_enabled) {}
static inline void rb_yjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop) {}
static inline void rb_yjit_constant_state_changed(ID id) {}
static inline void rb_yjit_iseq_mark(void *payload) {}
static inline void rb_yjit_iseq_update_references(const rb_iseq_t *iseq) {}
static inline void rb_yjit_iseq_free(const rb_iseq_t *iseq) {}
static inline void rb_yjit_before_ractor_spawn(void) {}
static inline void rb_yjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx) {}
static inline void rb_yjit_tracing_invalidate_all(void) {}
static inline void rb_yjit_lazy_push_frame(const VALUE *pc) {}
static inline void rb_yjit_invalidate_no_singleton_class(VALUE klass) {}
static inline void rb_yjit_invalidate_ep_is_bp(const rb_iseq_t *iseq) {}

#endif // #if USE_YJIT

#endif // #ifndef YJIT_H
