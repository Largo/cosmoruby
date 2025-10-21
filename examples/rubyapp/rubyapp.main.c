/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:4;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=4 sts=4 sw=4 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Cosmopolitan Ruby Application - Embedded Example                             │
│                                                                              │
│ This demonstrates embedding Ruby in a Cosmopolitan application.              │
╚─────────────────────────────────────────────────────────────────────────────*/

#include "libc/stdio/stdio.h"
#undef RUBY_EXPORT
#include "ruby.h"

int main(int argc, char *argv[]) {
    int status;

    printf("Initializing embedded Ruby interpreter...\n");

    /* Initialize Ruby VM */
    RUBY_INIT_STACK;
    ruby_sysinit(&argc, &argv);
    ruby_init();

    printf("Ruby version: %s\n", ruby_version);
    printf("Ruby patchlevel: %d\n", ruby_patchlevel);
    printf("Ruby description: %s\n\n", ruby_description);

    /* Execute some Ruby code */
    printf("Evaluating Ruby code: puts 'Hello from embedded CosmoRuby!'\n");
    rb_eval_string("puts 'Hello from embedded CosmoRuby!'");

    printf("\nCalculating 2 + 2 in Ruby:\n");
    VALUE result = rb_eval_string("2 + 2");
    printf("Result: %ld\n", NUM2LONG(result));

    /* Clean up */
    status = ruby_cleanup(0);
    return status;
}
