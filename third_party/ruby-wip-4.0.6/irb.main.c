/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:4;tab-width:8;coding:utf-8 -*- */
/* vi: set et ft=c ts=4 sts=4 sw=4 fenc=utf-8                               :vi */
/*+----------------------------------------------------------------------------+*/
/*| IRB (Interactive Ruby) Cosmopolitan Entry Point                            |*/
/*+----------------------------------------------------------------------------+*/

#include "ruby_cosmo_main.h"

/* Defined in ruby.c.  Keeps an appended /zip/main.rb from replacing the
 * program this main() names below: irb is a REPL, not an application
 * launcher, and its immunity to an appended main.rb is documented.  It used
 * to be structural (the -e below was parsed first); the hook now runs before
 * Ruby's option parser, so it has to be stated. */
void rb_cosmo_disable_zip_main(void);

static int
rb_main(int argc, char **argv)
{
    rb_cosmo_disable_zip_main();

    /* Create argv for ruby_options to properly initialize the VM */
    /* This mimics: ruby -e "require 'rubygems'; require 'irb'; IRB.start" */
    int new_argc = 3;
    char *new_argv[] = {
        argv[0],  /* program name */
        "-e",
        "require 'rubygems'; require 'irb'; IRB.start",
        NULL
    };

    /* Use shared initialization with custom argv */
    return rb_main_run(new_argc, new_argv);
}

int
main(int argc, char **argv)
{
    return rb_cosmo_main(argc, argv, rb_main);
}
