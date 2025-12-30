/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:4;tab-width:8;coding:utf-8 -*- */
/* vi: set et ft=c ts=4 sts=4 sw=4 fenc=utf-8                               :vi */
/*+----------------------------------------------------------------------------+*/
/*| IRB (Interactive Ruby) Cosmopolitan Entry Point                            |*/
/*+----------------------------------------------------------------------------+*/

#include "ruby_cosmo_main.h"

static int
rb_main(int argc, char **argv)
{
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
