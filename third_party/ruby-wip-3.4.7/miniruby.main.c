/* miniruby.main.c - Lean Ruby entry point for Cosmopolitan */

#include "ruby_cosmo_main.h"

static int
rb_main(int argc, char **argv)
{
    return rb_main_run(argc, argv);
}

int
main(int argc, char **argv)
{
    return rb_cosmo_main(argc, argv, rb_main);
}
