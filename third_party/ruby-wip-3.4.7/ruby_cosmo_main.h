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

/* Cosmopolitan doesn't implement setlocale, but Ruby doesn't strictly need it */

/**
 * Common Ruby VM initialization and execution.
 * Takes argc/argv and runs the Ruby code.
 */
static int
rb_main_run(int argc, char **argv)
{
    RUBY_INIT_STACK;
    ruby_init();
    return ruby_run_node(ruby_options(argc, argv));
}

/**
 * Standard main() entry point for Ruby binaries on Cosmopolitan.
 * Calls rb_main_run with properly initialized arguments.
 */
static int
rb_cosmo_main(int argc, char **argv, int (*rb_main)(int, char **))
{
    /* setlocale(LC_CTYPE, ""); - skipped on Cosmopolitan */
    ruby_sysinit(&argc, &argv);
    return rb_main(argc, argv);
}

#endif /* RUBY_COSMO_MAIN_H */
