/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:4;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=4 sts=4 sw=4 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Ruby Module Launcher for Cosmopolitan                                        │
│                                                                              │
│ This file provides the main() entry point for Ruby apps compiled with        │
│ rubyobj -m. It loads the ISEQ bytecode from the embedded ZIP filesystem      │
│ and executes it.                                                             │
│                                                                              │
│ The rubyobj tool embeds two symbols into the generated .o:                   │
│   kLaunchRubyModuleName - the module name (e.g. "hello")                     │
│   kLaunchRubyZipPrefix  - the zip prefix (e.g. ".ruby")                      │
│ These are used to construct the path /zip/<prefix>/<name>.rbc                │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "libc/mem/gc.h"
#include "libc/stdio/stdio.h"
#include "libc/x/x.h"

/* Resolve macro conflicts between libc/x/x.h and Ruby's xmalloc.h */
#undef xmalloc
#undef xcalloc
#undef xrealloc

#undef RUBY_EXPORT
#include "ruby.h"

/* Provided by rubyobj-generated .o via .rodata symbols */
extern const char kLaunchRubyModuleName[];
extern const char kLaunchRubyZipPrefix[];

void
LaunchRubyModule(void)
{
    char rbcpath[512];
    size_t rbcsize;
    char *rbcdata;
    VALUE binary, iseq, rb_cISeq;

    /* Construct the path to the .rbc file in the ZIP filesystem */
    snprintf(rbcpath, sizeof(rbcpath), "/zip/%s/%s.rbc",
             kLaunchRubyZipPrefix, kLaunchRubyModuleName);

    /* Read the ISEQ binary from the embedded ZIP */
    rbcdata = xslurp(rbcpath, &rbcsize);
    if (!rbcdata) {
        fprintf(stderr, "rubyobj: cannot open %s\n", rbcpath);
        return;
    }

    /* Load and execute the ISEQ */
    rb_cISeq = rb_const_get(
        rb_const_get(rb_cObject, rb_intern("RubyVM")),
        rb_intern("InstructionSequence"));
    binary = rb_str_new(rbcdata, rbcsize);
    free(rbcdata);
    iseq = rb_funcall(rb_cISeq, rb_intern("load_from_binary"), 1, binary);
    rb_funcall(iseq, rb_intern("eval"), 0);
}

int
main(int argc, char *argv[])
{
    int status;

    RUBY_INIT_STACK;
    ruby_sysinit(&argc, &argv);
    ruby_init();

    LaunchRubyModule();

    status = ruby_cleanup(0);
    return status;
}
