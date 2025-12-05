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
	const char *rubylib;
	const char *segment;
	const char *cursor;

	rb_ary_clear(load_path);

	rubylib = getenv("RUBYLIB");
	if (rubylib && *rubylib) {
		segment = rubylib;
		cursor = rubylib;
		while (1) {
			if (*cursor == PATH_SEP_CHAR || *cursor == '\0') {
				if (cursor > segment) {
					rb_ary_push(load_path, rb_str_new(segment, cursor - segment));
				}
				if (*cursor == '\0') {
					break;
				}
				cursor++;
				segment = cursor;
				continue;
			}
			cursor++;
		}
	}

#endif
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
    rb_cosmo_seed_rubylib_env();
    char **argv_alloc = rb_cosmo_inject_include_paths(&argc, &argv);
    ruby_sysinit(&argc, &argv);
    int rc = rb_main(argc, argv);
    free(argv_alloc);
    return rc;
}

#endif /* RUBY_COSMO_MAIN_H */
