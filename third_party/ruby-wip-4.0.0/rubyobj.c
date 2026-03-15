/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:4;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=4 sts=4 sw=4 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Ruby Objectifier for Cosmopolitan                                           │
│                                                                              │
│ Compiles Ruby source files into ELF object files containing ISEQ             │
│ bytecode embedded in ZIP entries, suitable for static linking into            │
│ Cosmopolitan APE binaries.                                                   │
│                                                                              │
│ Modelled after third_party/python/pyobj.c                                    │
╚─────────────────────────────────────────────────────────────────────────────*/
/* Cosmo headers first — order matters to avoid redefinition conflicts */
#include "libc/calls/calls.h"
#include "libc/calls/struct/stat.h"
#include "libc/elf/def.h"
#include "libc/fmt/conv.h"
#include "libc/log/check.h"
#include "libc/log/log.h"
#include "libc/mem/gc.h"
#include "libc/mem/mem.h"
#include "libc/runtime/runtime.h"
#include "libc/stdio/stdio.h"
#include "libc/sysv/consts/o.h"
#include "libc/x/x.h"
#include "libc/zip.h"
#include "tool/build/lib/elfwriter.h"
#include "tool/build/lib/interner.h"
#include "libc/serialize.h"
#include "tool/build/lib/stripcomponents.h"

/* Resolve macro conflicts between libc/x/x.h and Ruby's xmalloc.h */
#undef xmalloc
#undef xcalloc
#undef xrealloc

/* Ruby's headers pull in getopt_long via unistd.h, which clashes with
 * Cosmo's getopt.internal.h. We use getopt() from unistd.h instead. */
#undef RUBY_EXPORT
#include "ruby.h"

#define MANUAL "\
SYNOPSIS\n\
\n\
  rubyobj [FLAGS] SOURCE\n\
\n\
OVERVIEW\n\
\n\
  Ruby Objectifier\n\
\n\
  Compiles Ruby source files (.rb) into ELF object files containing\n\
  ISEQ bytecode. The resulting .o can be statically linked with\n\
  cosmopolitan-ruby.a to produce an APE binary.\n\
\n\
FLAGS\n\
\n\
  -o PATH      output elf object file\n\
  -P STR       prefix fake zip directory (default .ruby)\n\
  -C INT       strip directory components from src in zip\n\
  -m           insert executable launcher main\n\
  -B           binary only (don't include .rb source)\n\
  -0           zip uncompressed\n\
  -n           do nothing\n\
  -h           help\n\
\n"

static bool binonly;
static bool nocompress;
static bool insertlauncher;
static int strip_components;
static char *rbfile;
static char *outpath;
static struct stat st;
static struct ElfWriter *elf;
static const char *path_prefix;
static struct timespec timestamp;

static void
GetOpts(int argc, char *argv[])
{
    int opt;
    path_prefix = ".ruby";
    while ((opt = getopt(argc, argv, "hnm0Bo:C:P:")) != -1) {
        switch (opt) {
        case 'B':
            binonly = true;
            break;
        case '0':
            nocompress = true;
            break;
        case 'm':
            insertlauncher = true;
            break;
        case 'o':
            outpath = optarg;
            break;
        case 'P':
            path_prefix = optarg;
            break;
        case 'C':
            strip_components = atoi(optarg);
            break;
        case 'n':
            exit(0);
        case 'h':
            fputs(MANUAL, stdout);
            exit(0);
        default:
            fputs(MANUAL, stderr);
            exit(1);
        }
    }
    if (argc - optind != 1) {
        fputs("error: need one input file\n", stderr);
        exit(1);
    }
    rbfile = argv[optind];
    if (stat(rbfile, &st)) {
        perror(rbfile);
        exit(1);
    }
    if (!outpath) {
        outpath = xstrcat(rbfile, ".o");
    }
}

static char *
GetZipFile(void)
{
    const char *zipfile;
    zipfile = rbfile;
    zipfile = StripComponents(zipfile, strip_components);
    if (*path_prefix) {
        zipfile = gc(xjoinpaths(path_prefix, zipfile));
    }
    return xstrdup(zipfile);
}

static char *
GetZipDir(void)
{
    return xstrcat(gc(xdirname(gc(GetZipFile()))), '/');
}

static char *
GetSynFile(void)
{
    return xstrcat("/zip/", gc(GetZipFile()));
}

/* Derive a module name from the file path, stripping components and
 * the extension but preserving / separators. The ZIP filesystem uses
 * paths, not dotted module names. E.g. "examples/rubyapps/hello.rb"
 * with strip_components=2 becomes "hello". */
static char *
GetModName(void)
{
    char *mod, *p;
    mod = xstrdup(StripComponents(rbfile, strip_components));
    p = strrchr(mod, '.');
    if (p) *p = '\0';
    return mod;
}

static VALUE
CompileRubySource(const char *rbdata, size_t rbsize, const char *synfile)
{
    VALUE rb_cISeq, rbstr, fnamestr;
    rb_cISeq = rb_const_get(
        rb_const_get(rb_cObject, rb_intern("RubyVM")),
        rb_intern("InstructionSequence"));
    rbstr = rb_str_new(rbdata, rbsize);
    fnamestr = rb_str_new_cstr(synfile);
    return rb_funcall(rb_cISeq, rb_intern("compile"), 2, rbstr, fnamestr);
}

static int
Objectify(void)
{
    size_t rbsize, iseqsize;
    char *rbdata, *iseqdata, *zipfile, *zipdir, *synfile, *modname;
    VALUE iseqval, iseqbin;

    zipdir = gc(GetZipDir());
    zipfile = gc(GetZipFile());
    synfile = gc(GetSynFile());
    modname = gc(GetModName());

    CHECK_NOTNULL((rbdata = gc(xslurp(rbfile, &rbsize))));

    /* Compile Ruby source to ISEQ via RubyVM::InstructionSequence.compile */
    iseqval = CompileRubySource(rbdata, rbsize, synfile);
    if (NIL_P(iseqval)) {
        fprintf(stderr, "rubyobj: failed to compile %s\n", rbfile);
        return -1;
    }

    /* Serialise ISEQ to binary (IBF format) */
    iseqbin = rb_funcall(iseqval, rb_intern("to_binary"), 0);
    if (NIL_P(iseqbin)) {
        fprintf(stderr, "rubyobj: failed to serialise ISEQ for %s\n", rbfile);
        return -1;
    }
    iseqdata = RSTRING_PTR(iseqbin);
    iseqsize = RSTRING_LEN(iseqbin);

    /* Create ELF object with embedded ZIP entries */
    elf = elfwriter_open(outpath, 0644, 0);
    elfwriter_cargoculting(elf);

    /* Embed directory entry */
    elfwriter_zip(elf, zipdir, zipdir, strlen(zipdir),
                  rbdata, 0, 040755, timestamp, timestamp,
                  timestamp, nocompress);

    /* Embed original .rb source (unless -B) */
    if (!binonly) {
        elfwriter_zip(elf, gc(xstrcat("rb:", modname)), zipfile,
                      strlen(zipfile), rbdata, rbsize, st.st_mode, timestamp,
                      timestamp, timestamp, nocompress);
    }

    /* Embed compiled ISEQ binary as .rbc */
    elfwriter_zip(elf, gc(xstrcat("rbc:", modname)),
                  gc(xstrcat(zipfile, 'c')),
                  strlen(zipfile) + 1, iseqdata, iseqsize, st.st_mode,
                  timestamp, timestamp, timestamp, nocompress);

    /* Yoink section for linker tree-shaking */
    elfwriter_align(elf, 1, 0);
    elfwriter_startsection(elf, ".yoink", SHT_PROGBITS, 0);
    if (insertlauncher) {
        elfwriter_yoink(elf, "LaunchRubyModule", STB_GLOBAL);
    }
    elfwriter_finishsection(elf);

    /* If -m, emit the module name and zip prefix as global symbols so
     * the launcher knows which ISEQ to load from the ZIP filesystem */
    if (insertlauncher) {
        size_t n;

        n = strlen(modname) + 1;
        elfwriter_align(elf, 1, 0);
        elfwriter_startsection(elf, ".rodata.str1.1", SHT_PROGBITS,
                               SHF_ALLOC | SHF_MERGE | SHF_STRINGS);
        memcpy(elfwriter_reserve(elf, n), modname, n);
        elfwriter_appendsym(elf, "kLaunchRubyModuleName",
                            ELF64_ST_INFO(STB_GLOBAL, STT_OBJECT),
                            STV_DEFAULT, 0, n);
        elfwriter_commit(elf, n);
        elfwriter_finishsection(elf);

        n = strlen(path_prefix) + 1;
        elfwriter_align(elf, 1, 0);
        elfwriter_startsection(elf, ".rodata.str1.1", SHT_PROGBITS,
                               SHF_ALLOC | SHF_MERGE | SHF_STRINGS);
        memcpy(elfwriter_reserve(elf, n), path_prefix, n);
        elfwriter_appendsym(elf, "kLaunchRubyZipPrefix",
                            ELF64_ST_INFO(STB_GLOBAL, STT_OBJECT),
                            STV_DEFAULT, 0, n);
        elfwriter_commit(elf, n);
        elfwriter_finishsection(elf);
    }

    elfwriter_close(elf);
    return 0;
}

int
main(int argc, char *argv[])
{
    int ec;
    ShowCrashReports();
    timestamp.tv_sec = 1647414000; /* determinism */
    GetOpts(argc, argv);

    /* Initialise Ruby VM */
    RUBY_INIT_STACK;
    ruby_sysinit(&argc, &argv);
    ruby_init();

    if (!Objectify()) {
        ec = 0;
    } else {
        ec = 1;
    }

    ruby_cleanup(0);
    return ec;
}
