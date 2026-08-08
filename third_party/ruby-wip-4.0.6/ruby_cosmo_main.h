/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:4;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=4 sts=4 sw=4 fenc=utf-8                               :vi│
╚──────────────────────────────────────────────────────────────────────────────╝
│ Ruby Cosmopolitan Shared Main Entry Point Helper                            │
│ This file provides common initialization code for Ruby binaries             │
╚─────────────────────────────────────────────────────────────────────────────*/

#ifndef RUBY_COSMO_MAIN_H
#define RUBY_COSMO_MAIN_H

#undef RUBY_EXPORT
#include "ruby.h"
#include "vm_debug.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <cosmo.h>

/* Register ShowBacktrace with mimalloc for proper debugging in dbg mode.
 * mimalloc can't use _weaken() because it's in a static library that's linked
 * before LIBC_LOG, so weak references resolve to NULL. Instead, we set a
 * global function pointer that mimalloc checks.
 *
 * We use a constructor with priority 1 (earliest) to run before mimalloc's
 * constructor (priority 50). */
#include "libc/log/backtrace.internal.h"
#include "libc/nexgen32e/stackframe.h"

/* Declare the function pointer defined in mimalloc/cosmo_prim.c */
extern void (*mi_cosmo_show_backtrace)(int, const struct StackFrame *);

__attribute__((__constructor__(1)))
static textstartup void rb_cosmo_init_backtrace(void) {
    /* v8: Set the function pointer for mimalloc symbolic backtraces */
    mi_cosmo_show_backtrace = ShowBacktrace;
}

static inline size_t
rb_cosmo_collect_paths(const char **paths, size_t max)
{
	size_t count = 0;
#ifdef RUBY_COSMO_LOAD_PATH0
	if (count < max) paths[count++] = RUBY_COSMO_LOAD_PATH0;
#endif
#ifdef RUBY_COSMO_LOAD_PATH1
	if (count < max) paths[count++] = RUBY_COSMO_LOAD_PATH1;
#endif
#ifdef RUBY_COSMO_LOAD_PATH2
	if (count < max) paths[count++] = RUBY_COSMO_LOAD_PATH2;
#endif
#ifdef RUBY_COSMO_LOAD_PATH3
	if (count < max) paths[count++] = RUBY_COSMO_LOAD_PATH3;
#endif
#ifdef RUBY_COSMO_LOAD_PATH4
	if (count < max) paths[count++] = RUBY_COSMO_LOAD_PATH4;
#endif
	return count;
}

static inline void
rb_cosmo_seed_rubylib_env(void)
{
#if defined(RUBY_COSMO_RESET_LOAD_PATH)
    const char *paths[5];
    size_t count = rb_cosmo_collect_paths(paths, sizeof(paths) / sizeof(paths[0]));
    const char *existing = getenv("RUBYLIB");
    size_t existing_len = (existing && existing[0]) ? strlen(existing) : 0;
    size_t total = existing_len ? existing_len + 1 : 0; /* separator */
    size_t i;

    for (i = 0; i < count; ++i) {
        total += strlen(paths[i]) + (i ? 1 : 0);
    }

	if (!total) {
		return;
	}
	char *combined = malloc(total + 1);
	if (!combined) {
		return;
	}
	char *cursor = combined;
	for (i = 0; i < count; ++i) {
		size_t len = strlen(paths[i]);
		if (i) {
			*cursor++ = PATH_SEP_CHAR;
		}
		memcpy(cursor, paths[i], len);
		cursor += len;
	}
	if (existing_len) {
		if (cursor != combined) {
			*cursor++ = PATH_SEP_CHAR;
		}
		memcpy(cursor, existing, existing_len);
		cursor += existing_len;
	}
	*cursor = '\0';
	setenv("RUBYLIB", combined, 1);
	free(combined);
#endif
}

static inline char **
rb_cosmo_inject_include_paths(int *argc, char ***argv)
{
#if defined(RUBY_COSMO_RESET_LOAD_PATH)
	const char *paths[5];
	size_t count = rb_cosmo_collect_paths(paths, sizeof(paths) / sizeof(paths[0]));
	if (!count) {
		return NULL;
	}
	int original_argc = *argc;
	char **original_argv = *argv;
	int extra = (int)(count * 2);
	int new_argc = original_argc + extra;
	char **new_argv = malloc(sizeof(char *) * (new_argc + 1));
	if (!new_argv) {
		return NULL;
	}
	int idx = 0;
	new_argv[idx++] = original_argv[0];
	for (size_t i = 0; i < count; ++i) {
		new_argv[idx++] = "-I";
		new_argv[idx++] = (char *)paths[i];
	}
	for (int i = 1; i < original_argc; ++i) {
		new_argv[idx++] = original_argv[i];
	}
	new_argv[idx] = NULL;
	*argc = new_argc;
	*argv = new_argv;
	return new_argv;
#else
	(void)argc;
	(void)argv;
	return NULL;
#endif
}

/* Cosmopolitan doesn't implement setlocale, but Ruby doesn't strictly need it */

static inline void
rb_cosmo_configure_load_path(void)
{
#if defined(RUBY_COSMO_RESET_LOAD_PATH)
	VALUE load_path = rb_gv_get("$LOAD_PATH");

	/* If loadpath.c provided initial paths (zip variant), nothing to do */
	if (RARRAY_LEN(load_path) > 0) return;

	/* Zipless variant: loadpath.c used NO_INITIAL_LOAD_PATH so paths are
	 * empty. Populate from compile-time -D defines on this main.o. */
	{
		const char *paths[5];
		size_t count = rb_cosmo_collect_paths(paths, sizeof(paths)/sizeof(paths[0]));
		for (size_t i = 0; i < count; i++) {
			rb_ary_push(load_path, rb_str_new_cstr(paths[i]));
		}
	}

	/* Also honour RUBYLIB env var for user-specified additional paths */
	{
		const char *rubylib = getenv("RUBYLIB");
		if (rubylib && *rubylib) {
			const char *segment = rubylib;
			const char *cursor = rubylib;
			while (1) {
				if (*cursor == PATH_SEP_CHAR || *cursor == '\0') {
					if (cursor > segment) {
						rb_ary_push(load_path, rb_str_new(segment, cursor - segment));
					}
					if (*cursor == '\0') break;
					cursor++;
					segment = cursor;
					continue;
				}
				cursor++;
			}
		}
	}
#endif
}

/**
 * Define RUBY_COSMO_PACKAGED constant based on runtime detection.
 * Returns true if this binary has Ruby stdlib embedded in /zip/.
 *
 * /zip/ is a per-process virtual filesystem embedded in this APE binary.
 * We check for both:
 *   1. /zip/.cosmo_ruby_packaged - explicit marker created by package_ruby.sh
 *   2. /zip/lib/ruby - the actual stdlib directory
 * Both must exist for the binary to be considered "packaged".
 */
static inline void
rb_cosmo_define_packaged_constant(void)
{
    int has_marker = (access("/zip/.cosmo_ruby_packaged", F_OK) == 0);
    int has_stdlib = (access("/zip/lib/ruby", F_OK) == 0);

    if (has_marker && has_stdlib) {
        rb_define_global_const("RUBY_COSMO_PACKAGED", Qtrue);
    } else {
        rb_define_global_const("RUBY_COSMO_PACKAGED", Qfalse);
    }
}

/**
 * Define RUBY_COSMO_EXECUTABLE constant with the actual path to the running
 * Ruby interpreter. This uses Cosmopolitan's GetProgramExecutableName() which
 * works cross-platform (Linux, macOS, Windows, BSDs).
 *
 * This is used by RbConfig.ruby to return the real executable path instead of
 * the incorrect /zip/bin/ruby.com path that would be constructed from bindir.
 */
static inline void
rb_cosmo_define_executable_constant(void)
{
    char *exe_path = GetProgramExecutableName();
    if (exe_path && exe_path[0]) {
        rb_define_global_const("RUBY_COSMO_EXECUTABLE",
                               rb_str_new_cstr(exe_path));
    }
}

/**
 * Common Ruby VM initialization and execution.
 * Takes argc/argv and runs the Ruby code.
 */
static int
rb_main_run(int argc, char **argv)
{
    RUBY_INIT_STACK;
    ruby_init();
    rb_cosmo_define_packaged_constant();
    rb_cosmo_define_executable_constant();
    rb_cosmo_configure_load_path();
    void *node = ruby_options(argc, argv);
    rb_cosmo_configure_load_path();
    return ruby_run_node(node);
}

/**
 * Standard main() entry point for Ruby binaries on Cosmopolitan.
 * Calls rb_main_run with properly initialized arguments.
 */
static int
rb_cosmo_main(int argc, char **argv, int (*rb_main)(int, char **))
{
    /* setlocale(LC_CTYPE, ""); - skipped on Cosmopolitan */
    /* NOTE: We intentionally do NOT call rb_cosmo_seed_rubylib_env() or
     * rb_cosmo_inject_include_paths() here. The core load paths are already
     * defined in loadpath.c via -DRUBY_COSMO_LOADPATH_PREFIX. Adding them
     * via RUBYLIB and -I flags would create duplicates.
     * The extensions path is added separately by rb_cosmo_configure_load_path(). */
    ruby_sysinit(&argc, &argv);
    return rb_main(argc, argv);
}

#endif /* RUBY_COSMO_MAIN_H */
