#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘


# Common CFLAGS for all Ruby files
# -DRUBY_SEARCH_PATH=\"/zip/lib/ruby/3.4.0\"
$(THIRD_PARTY_RUBY_A_OBJS): private				\
    CFLAGS +=							\
            -Ithird_party/ruby/include				\
            -Ithird_party/ruby					\
            -Ithird_party/ruby/prism				\
	    -Ithird_party/ruby/enc/unicode/15.0.0		\
            -Ithird_party/zlib					\
            -DRUBY_EXPORT					\
            -DRUBY_COSMOPOLITAN					\
            -Wno-deprecated-declarations			\
            -Wno-unused-value					\
            -Wno-return-type					\
            -Wno-unused-variable				\
            -Wno-attributes
#            -ffunction-sections					\
#            -fdata-sections					\

# Optimize GC for performance
o/$(MODE)/third_party/ruby/gc.o: private			\
    CFLAGS +=							\
            -O2

# Compile Ripper extension files with RIPPER defined
# This enables Ripper-specific macros (dispatch0-7, get_value, etc.)
o/$(MODE)/third_party/ruby/ext/ripper/ripper.o: private	\
    CFLAGS +=							\
            -DRIPPER

o/$(MODE)/third_party/ruby/ext/ripper/ripper_init.o: private	\
    CFLAGS +=							\
            -DRIPPER

o/$(MODE)/third_party/ruby/ext/ripper/eventids1.o: private	\
    CFLAGS +=							\
            -DRIPPER

o/$(MODE)/third_party/ruby/ext/ripper/eventids2.o: private	\
    CFLAGS +=							\
            -DRIPPER

o/$(MODE)/third_party/ruby/ext/ripper/eventids2table.o: private \
    CFLAGS +=							\
            -DRIPPER

# Suppress false positive warnings in Prism parser
o/$(MODE)/third_party/ruby/prism/prism.o: private		\
    CFLAGS +=							\
            -Wno-stringop-overread

o/$(MODE)/third_party/ruby/prism/diagnostic.o: private		\
    CFLAGS +=							\
            -Wno-array-bounds

# Transcoder database needs access to generated transdb.h in enc/
o/$(MODE)/third_party/ruby/enc/trans/transdb.o: private	\
    CFLAGS +=							\
            -Ithird_party/ruby/enc

# Coroutine assembly: .S files are preprocessed, so define PREFIXED_SYMBOL
# On Linux/Cosmopolitan we don't need symbol prefixes (unlike macOS which uses _)
o/$(MODE)/third_party/ruby/coroutine/amd64/Context.o: private	\
    CPPFLAGS +=							\
            -D'PREFIXED_SYMBOL(name)=name'

# Extension-specific compiler flags are now in ext/*/BUILD.mk

# Main entry point files need Ruby includes
o/$(MODE)/third_party/ruby/ruby.main.o				\
o/$(MODE)/third_party/ruby/irb.main.o				\
o/$(MODE)/third_party/ruby/miniruby.main.o: private		\
    CFLAGS +=							\
            -Ithird_party/ruby/include				\
            -Ithird_party/ruby

################################################################################
# ruby

THIRD_PARTY_RUBY_RUBY_DIRECTDEPS =				\
    LIBC_CALLS							\
    LIBC_FMT							\
    LIBC_INTRIN							\
    LIBC_NEXGEN32E						\
    LIBC_STDIO							\
    LIBC_LOG							\
    LIBC_MEM							\
    LIBC_STR							\
    LIBC_SYSV							\
    LIBC_THREAD							\
    THIRD_PARTY_RUBY						\
    TOOL_ARGS

THIRD_PARTY_RUBY_RUBY_DEPS :=					\
    $(call uniq,$(foreach x,$(THIRD_PARTY_RUBY_RUBY_DIRECTDEPS),$($(x))))

o/$(MODE)/third_party/ruby/ruby.pkg:				\
    o/$(MODE)/third_party/ruby/ruby.main.o			\
    $(foreach x,$(THIRD_PARTY_RUBY_RUBY_DIRECTDEPS),$($(x)_A).pkg)

