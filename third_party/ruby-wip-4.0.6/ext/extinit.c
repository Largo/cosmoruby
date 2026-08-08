#include "ruby/ruby.h"
#include "ruby/config.h"

// Modular extension system using weak symbols
// Extensions are only initialized if their .a files are linked
#define init(func, name) {	\
    extern void func(void) __attribute__((weak));	\
    if (func) ruby_init_ext(name DLEXT, func); \
}

void ruby_init_ext(const char *name, void (*init)(void));

void Init_ext(void)
{
#if defined(EXTSTATIC) && EXTSTATIC
    init(Init_continuation, "continuation");
    init(Init_coverage, "coverage");
    init(Init_date_core, "date_core");
    init(Init_digest, "digest");
    init(Init_md5, "digest/md5");
    init(Init_sha1, "digest/sha1");
    init(Init_sha2, "digest/sha2");
    init(Init_etc, "etc");
    init(Init_fcntl, "fcntl");
    init(Init_console, "io/console");
    init(Init_nonblock, "io/nonblock");
    init(Init_wait, "io/wait");
    init(Init_generator, "json/ext/generator");
    init(Init_parser, "json/ext/parser");
    init(Init_mbedtls, "mbedtls");
    init(Init_monitor, "monitor");
    init(Init_psych, "psych");
    init(Init_sizeof, "rbconfig/sizeof");
    init(Init_ripper, "ripper");
    init(Init_socket, "socket");
    init(Init_sqlite3_native, "sqlite3/sqlite3_native");
    init(Init_stringio, "stringio");
    init(Init_strscan, "strscan");
    init(Init_zlib, "zlib");
    init(Init_objspace, "objspace");
#ifdef RUBY_TEST_EXTENSIONS
    init(Init_class, "-test-/class");
    init(Init_fatal, "-test-/fatal");
    init(Init_file, "-test-/file");
    init(Init_iter, "-test-/iter");
    init(Init_memory_view, "-test-/memory_view");
    init(Init_rb_call_super_kw, "-test-/rb_call_super_kw");
    init(Init_sanitizers, "-test-/sanitizers");
    init(Init_stack, "-test-/stack");
#endif
#endif
}
