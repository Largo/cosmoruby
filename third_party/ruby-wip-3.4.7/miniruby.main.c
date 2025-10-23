/*
 * miniruby.main.c - Minimal Ruby entry point for Cosmopolitan
 *
 * This is a lean Ruby interpreter for basic scripting and testing.
 * Unlike the full ruby binary, this skips some initialization
 * to provide a faster startup time.
 */

#include "ruby.h"

int
main(int argc, char **argv)
{
    ruby_sysinit(&argc, &argv);
    RUBY_INIT_STACK;
    ruby_init();
    return ruby_run_node(ruby_options(argc, argv));
}
