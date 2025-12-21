/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:4;tab-width:8;coding:utf-8 -*- */
/* vi: set et ft=c ts=4 sts=4 sw=4 fenc=utf-8                               :vi */
/*+----------------------------------------------------------------------------+*/
/*| Ruby Cosmopolitan Entry Point                                              |*/
/*| Based on Ruby's main.c                                                     |*/
/*+----------------------------------------------------------------------------+*/

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
