#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

################################################################################
# COSMOPOLITAN BUILD CONSTRAINTS
#
# Hermetic Build:
#   - Cosmopolitan downloads its own toolchain to .cosmocc/
#   - Cannot rely on system Ruby or tools during build
#   - Use HOST_RUBY or COSMO_RUBY variables for Ruby interpreter
#   - All build artifacts go to o/$(MODE)/ directory tree
#
# cocmd Shell Limitations:
#   - Make recipes use cocmd (Cosmopolitan's embedded shell)
#   - Supported: ':', '#' comments, subshells '()', cmd substitution '$()'
#   - Limited: Complex '&& ||' chains with redirects may fail
#   - Workaround: Break into multiple rules or simplify command logic
################################################################################

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
o/$(MODE)/third_party/ruby/ext/%.o: private			\
    CFLAGS +=							\
            -fPIC

# Main entry point files need Ruby includes
o/$(MODE)/third_party/ruby/ruby.main.o				\
o/$(MODE)/third_party/ruby/ruby.main.zipless.o			\
o/$(MODE)/third_party/ruby/irb.main.o				\
o/$(MODE)/third_party/ruby/irb.main.zipless.o			\
o/$(MODE)/third_party/ruby/miniruby.main.o			\
o/$(MODE)/third_party/ruby/miniruby.main.zipless.o: private	\
    CFLAGS +=							\
            -Ithird_party/ruby/include				\
            -Ithird_party/ruby

o/$(MODE)/third_party/ruby/loadpath.o: private			\
    CFLAGS +=							\
            -DRUBY_COSMO_LOADPATH_PREFIX=\"/zip\"		\
            -DRUBY_COSMO_DEV_LIB=\"$(abspath third_party/ruby/lib)\" \
            -DRUBY_COSMO_DEV_MONITOR=\"$(abspath third_party/ruby/ext/monitor/lib)\"

# miniruby.zipless - uses filesystem paths only
o/$(MODE)/third_party/ruby/miniruby.main.zipless.o: third_party/ruby/miniruby.main.c
	@$(COMPILE) -AOBJECTIFY.c $(OBJECTIFY.c) $(OUTPUT_OPTION) $<
	@$(COMPILE) -AFIXUPOBJ -wT$@ $(FIXUPOBJ) $@

o/$(MODE)/third_party/ruby/ruby.main.zipless.o: third_party/ruby/ruby.main.c
	@$(COMPILE) -AOBJECTIFY.c $(OBJECTIFY.c) $(OUTPUT_OPTION) $<
	@$(COMPILE) -AFIXUPOBJ -wT$@ $(FIXUPOBJ) $@

o/$(MODE)/third_party/ruby/irb.main.zipless.o: third_party/ruby/irb.main.c
	@$(COMPILE) -AOBJECTIFY.c $(OBJECTIFY.c) $(OUTPUT_OPTION) $<
	@$(COMPILE) -AFIXUPOBJ -wT$@ $(FIXUPOBJ) $@

# zipless entry points share filesystem load path definitions
o/$(MODE)/third_party/ruby/miniruby.main.zipless.o: private	\
    CFLAGS +=							\
            -DRUBY_COSMO_RESET_LOAD_PATH			\
            -DRUBY_COSMO_LOAD_PATH0=\"$(abspath third_party/ruby/lib)\" \
            -DRUBY_COSMO_LOAD_PATH1=\"$(abspath third_party/ruby/ext/monitor/lib)\" \
            -DRUBY_MINI_LIBDIR=\"$(abspath third_party/ruby/lib)\" \
            -DRUBY_MINI_MONITOR_LIBDIR=\"$(abspath third_party/ruby/ext/monitor/lib)\"

# miniruby - uses ZIP paths only
o/$(MODE)/third_party/ruby/miniruby.main.o: private		\
    CFLAGS +=							\
            -DRUBY_COSMO_RESET_LOAD_PATH			\
            -DRUBY_COSMO_LOAD_PATH0=\"/zip/lib/ruby/3.4.0\" \
            -DRUBY_COSMO_LOAD_PATH1=\"/zip/lib/ruby/3.4.0/x86_64-cosmo\" \
            -DRUBY_MINI_LIBDIR=\"/zip/lib/ruby/3.4.0\" \
            -DRUBY_MINI_MONITOR_LIBDIR=\"/zip/lib/ruby/3.4.0/x86_64-cosmo\"

# ruby - filesystem paths (zipless)
o/$(MODE)/third_party/ruby/ruby.main.zipless.o: private		\
    CFLAGS +=							\
            -DRUBY_COSMO_RESET_LOAD_PATH			\
            -DRUBY_COSMO_LOAD_PATH0=\"$(abspath third_party/ruby/lib)\" \
            -DRUBY_COSMO_LOAD_PATH1=\"$(abspath third_party/ruby/ext/monitor/lib)\"

# irb - filesystem paths (zipless)
o/$(MODE)/third_party/ruby/irb.main.zipless.o: private		\
    CFLAGS +=							\
            -DRUBY_COSMO_RESET_LOAD_PATH			\
            -DRUBY_COSMO_LOAD_PATH0=\"$(abspath third_party/ruby/lib)\" \
            -DRUBY_COSMO_LOAD_PATH1=\"$(abspath third_party/ruby/ext/monitor/lib)\"

# Host export table generated from linked ruby.pre.dbg (phase 1 binary without exports)
# This breaks the circular dependency: pre.dbg → exports.pre.c → exports.pre.o → stage1.dbg
o/$(MODE)/third_party/ruby/ruby_exports.pre.c: o/$(MODE)/third_party/ruby/ruby.pre.dbg
	@bash third_party/ruby/generate_exports.sh $< $@

o/$(MODE)/third_party/ruby/ruby_exports.pre.o: o/$(MODE)/third_party/ruby/ruby_exports.pre.c

# Stage1 export table generated from stage1 binary (phase 2)
o/$(MODE)/third_party/ruby/ruby_exports.stage1.c: o/$(MODE)/third_party/ruby/ruby.stage1.dbg
	@bash third_party/ruby/generate_exports.sh $< $@

o/$(MODE)/third_party/ruby/ruby_exports.stage1.o: o/$(MODE)/third_party/ruby/ruby_exports.stage1.c

# Final export table generated from stage2 binary (phase 3) for final link
o/$(MODE)/third_party/ruby/ruby_exports.c: o/$(MODE)/third_party/ruby/ruby.stage2.dbg
	@bash third_party/ruby/generate_exports.sh $< $@

o/$(MODE)/third_party/ruby/ruby_exports.o: o/$(MODE)/third_party/ruby/ruby_exports.c

# Host export table generated from linked irb.pre.dbg
o/$(MODE)/third_party/ruby/irb_exports.pre.c: o/$(MODE)/third_party/ruby/irb.pre.dbg
	@bash third_party/ruby/generate_exports.sh $< $@

o/$(MODE)/third_party/ruby/irb_exports.pre.o: o/$(MODE)/third_party/ruby/irb_exports.pre.c

# Stage1 export table generated from stage1 binary (phase 2)
o/$(MODE)/third_party/ruby/irb_exports.stage1.c: o/$(MODE)/third_party/ruby/irb.stage1.dbg
	@bash third_party/ruby/generate_exports.sh $< $@

o/$(MODE)/third_party/ruby/irb_exports.stage1.o: o/$(MODE)/third_party/ruby/irb_exports.stage1.c

# Final export table generated from stage2 binary (phase 3) for final link
o/$(MODE)/third_party/ruby/irb_exports.c: o/$(MODE)/third_party/ruby/irb.stage2.dbg
	@bash third_party/ruby/generate_exports.sh $< $@

o/$(MODE)/third_party/ruby/irb_exports.o: o/$(MODE)/third_party/ruby/irb_exports.c

# Host export table generated from linked miniruby.pre.dbg
# Note: miniruby and miniruby.zipless produce identical exports (same Ruby core)
o/$(MODE)/third_party/ruby/miniruby_exports.pre.c: o/$(MODE)/third_party/ruby/miniruby.pre.dbg
	@bash third_party/ruby/generate_exports.sh $< $@

o/$(MODE)/third_party/ruby/miniruby_exports.pre.o: o/$(MODE)/third_party/ruby/miniruby_exports.pre.c

# Stage1 export table generated from stage1 binary (phase 2)
o/$(MODE)/third_party/ruby/miniruby_exports.stage1.c: o/$(MODE)/third_party/ruby/miniruby.stage1.dbg
	@bash third_party/ruby/generate_exports.sh $< $@

o/$(MODE)/third_party/ruby/miniruby_exports.stage1.o: o/$(MODE)/third_party/ruby/miniruby_exports.stage1.c

# Final export table generated from stage2 binary (phase 3) for final link
o/$(MODE)/third_party/ruby/miniruby_exports.c: o/$(MODE)/third_party/ruby/miniruby.stage2.dbg
	@bash third_party/ruby/generate_exports.sh $< $@

o/$(MODE)/third_party/ruby/miniruby_exports.o: o/$(MODE)/third_party/ruby/miniruby_exports.c

# ruby/irb/miniruby - ZIP paths
o/$(MODE)/third_party/ruby/ruby.main.o: private			\
    CFLAGS +=							\
            -DRUBY_COSMO_RESET_LOAD_PATH			\
            -DRUBY_COSMO_LOAD_PATH0=\"/zip/lib/ruby/3.4.0\" \
            -DRUBY_COSMO_LOAD_PATH1=\"/zip/lib/ruby/3.4.0/x86_64-cosmo\"

o/$(MODE)/third_party/ruby/irb.main.o: private			\
    CFLAGS +=							\
            -DRUBY_COSMO_RESET_LOAD_PATH			\
            -DRUBY_COSMO_LOAD_PATH0=\"/zip/lib/ruby/3.4.0\" \
            -DRUBY_COSMO_LOAD_PATH1=\"/zip/lib/ruby/3.4.0/x86_64-cosmo\"

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
    TOOL_ARGS							\
    THIRD_PARTY_COSMO_PLUGIN

THIRD_PARTY_RUBY_RUBY_DEPS :=					\
    $(call uniq,$(foreach x,$(THIRD_PARTY_RUBY_RUBY_DIRECTDEPS),$($(x))))

o/$(MODE)/third_party/ruby/ruby.pkg:				\
    o/$(MODE)/third_party/ruby/ruby.main.o			\
    o/$(MODE)/third_party/ruby/ruby_exports.o			\
    $(foreach x,$(THIRD_PARTY_RUBY_RUBY_DIRECTDEPS),$($(x)_A).pkg)
