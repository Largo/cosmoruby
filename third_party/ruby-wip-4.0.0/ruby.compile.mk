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
# -DRUBY_SEARCH_PATH=\"/zip/lib/ruby/4.0.0\"
# $(LIBC_MEM_ALLOCATOR_FLAGS) passes -DCOSMO_USE_MIMALLOC=1 when using mimalloc
$(THIRD_PARTY_RUBY_A_OBJS): private				\
    CFLAGS +=							\
            -Ithird_party/ruby/include				\
            -Ithird_party/ruby					\
            -Ithird_party/ruby/prism				\
	    -Ithird_party/ruby/enc/unicode/17.0.0		\
            -Ithird_party/zlib					\
            -DRUBY_EXPORT					\
            -DRUBY_COSMOPOLITAN					\
            -include third_party/ruby/include/ruby/cosmo.h	\
            -UHAVE_DLADDR					\
            $(LIBC_MEM_ALLOCATOR_FLAGS)				\
            -Wno-deprecated-declarations			\
            -Wno-unused-value					\
            -Wno-return-type					\
            -Wno-unused-variable				\
            -Wno-attributes
#            -ffunction-sections					\
#            -fdata-sections

# Force recompilation of all Ruby files when mode-specific config changes
# config.mode.h defines DLEXT, EXTSTATIC, SLIM_STATIC which affect compiled code
# behavior (especially rb_provide() calls). config.h is static and won't trigger rebuilds.
$(THIRD_PARTY_RUBY_A_OBJS): third_party/ruby/include/ruby/config.mode.h

# Extension object files also depend on config.mode.h
o/$(MODE)/third_party/ruby/ext/%.o: third_party/ruby/include/ruby/config.mode.h

# Encoding object files also depend on config.mode.h
o/$(MODE)/third_party/ruby/enc/%.o: third_party/ruby/include/ruby/config.mode.h

# All encoding files need -fPIC for plugin mode loading
o/$(MODE)/third_party/ruby/enc/%.o: private \
    CFLAGS += -fPIC

# All transcoder files need -fPIC for plugin mode loading
o/$(MODE)/third_party/ruby/enc/trans/%.o: private \
    CFLAGS += -fPIC

# Core encodings (ascii, utf_8, us_ascii) must export OnigEncoding* symbols
# for early initialization in encoding.c, so do NOT define ONIG_ENC_REGISTER
# (This rule intentionally left without CPPFLAGS override)

# Extended encoding files need ONIG_ENC_REGISTER to create Init_* functions
# Exclude core encodings (ascii, utf_8, us_ascii) from this rule
o/$(MODE)/third_party/ruby/enc/big5.o			\
o/$(MODE)/third_party/ruby/enc/cesu_8.o			\
o/$(MODE)/third_party/ruby/enc/cp949.o			\
o/$(MODE)/third_party/ruby/enc/emacs_mule.o		\
o/$(MODE)/third_party/ruby/enc/euc_jp.o			\
o/$(MODE)/third_party/ruby/enc/euc_kr.o			\
o/$(MODE)/third_party/ruby/enc/euc_tw.o			\
o/$(MODE)/third_party/ruby/enc/gb18030.o		\
o/$(MODE)/third_party/ruby/enc/gb2312.o			\
o/$(MODE)/third_party/ruby/enc/gbk.o			\
o/$(MODE)/third_party/ruby/enc/iso_8859_1.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_2.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_3.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_4.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_5.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_6.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_7.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_8.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_9.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_10.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_11.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_13.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_14.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_15.o		\
o/$(MODE)/third_party/ruby/enc/iso_8859_16.o		\
o/$(MODE)/third_party/ruby/enc/koi8_r.o			\
o/$(MODE)/third_party/ruby/enc/koi8_u.o			\
o/$(MODE)/third_party/ruby/enc/shift_jis.o		\
o/$(MODE)/third_party/ruby/enc/utf_16be.o		\
o/$(MODE)/third_party/ruby/enc/utf_16le.o		\
o/$(MODE)/third_party/ruby/enc/utf_32be.o		\
o/$(MODE)/third_party/ruby/enc/utf_32le.o		\
o/$(MODE)/third_party/ruby/enc/windows_31j.o		\
o/$(MODE)/third_party/ruby/enc/windows_1250.o		\
o/$(MODE)/third_party/ruby/enc/windows_1251.o		\
o/$(MODE)/third_party/ruby/enc/windows_1252.o		\
o/$(MODE)/third_party/ruby/enc/windows_1253.o		\
o/$(MODE)/third_party/ruby/enc/windows_1254.o		\
o/$(MODE)/third_party/ruby/enc/windows_1257.o: private	\
    CPPFLAGS +=						\
            -DONIG_ENC_REGISTER=rb_enc_register

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

# Transcoding files also need ONIG_ENC_REGISTER to create Init_trans_* functions
o/$(MODE)/third_party/ruby/enc/trans/%.o: private		\
    CPPFLAGS +=							\
            -DONIG_ENC_REGISTER=rb_enc_register

# Transcoder database needs access to generated transdb.h in enc/
o/$(MODE)/third_party/ruby/enc/trans/transdb.o: private	\
    CFLAGS +=							\
            -Ithird_party/ruby/enc

# Coroutine assembly: .S files are preprocessed, so define PREFIXED_SYMBOL
# On Linux/Cosmopolitan we don't need symbol prefixes (unlike macOS which uses _)
o/$(MODE)/third_party/ruby/coroutine/amd64/Context.o		\
o/$(MODE)/third_party/ruby/coroutine/arm64/Context.o: private	\
    CPPFLAGS +=							\
            -D'PREFIXED_SYMBOL(name)=name'

# On aarch64, build/rules.mk compiles ALL .S files from libc/empty.s
# (to prevent x86_64 assembly from leaking into aarch64 builds).
# Ruby's arm64 coroutine is genuine aarch64 assembly, so we need an
# explicit rule to override the empty stub — same pattern used by
# libc/intrin/BUILD.mk for Arm Optimized Routines.
o/$(MODE)/third_party/ruby/coroutine/arm64/Context.o:		\
		third_party/ruby/coroutine/arm64/Context.S
	@$(COMPILE) -AOBJECTIFY.S $(OBJECTIFY.S) $(OUTPUT_OPTION) -c $<

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
            -DRUBY_COSMO_LOADPATH_PREFIX=\"/zip\"
            # Dev paths removed to prevent duplicate constant warnings when using packaged ruby.com
            # -DRUBY_COSMO_DEV_LIB=\"$(abspath third_party/ruby/lib)\" \
            # -DRUBY_COSMO_DEV_MONITOR=\"$(abspath third_party/ruby/ext/monitor/lib)\"

# zipless variant: empty initial load paths (populated at runtime by
# rb_cosmo_configure_load_path() using -D defines on each main.*.zipless.o)
o/$(MODE)/third_party/ruby/loadpath.zipless.o: third_party/ruby/loadpath.c
	@$(COMPILE) -AOBJECTIFY.c $(OBJECTIFY.c) \
		-Ithird_party/ruby/include \
		-Ithird_party/ruby \
		-DNO_INITIAL_LOAD_PATH \
		$(OUTPUT_OPTION) $<
	@$(COMPILE) -AFIXUPOBJ -wT$@ $(FIXUPOBJ) $@

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

# Header dependencies for main entry points (ruby_cosmo_main.h is included by all)
o/$(MODE)/third_party/ruby/miniruby.main.o: third_party/ruby/ruby_cosmo_main.h
o/$(MODE)/third_party/ruby/miniruby.main.zipless.o: third_party/ruby/ruby_cosmo_main.h
o/$(MODE)/third_party/ruby/ruby.main.o: third_party/ruby/ruby_cosmo_main.h
o/$(MODE)/third_party/ruby/ruby.main.zipless.o: third_party/ruby/ruby_cosmo_main.h
o/$(MODE)/third_party/ruby/irb.main.o: third_party/ruby/ruby_cosmo_main.h
o/$(MODE)/third_party/ruby/irb.main.zipless.o: third_party/ruby/ruby_cosmo_main.h

# zipless entry points share filesystem load path definitions
o/$(MODE)/third_party/ruby/miniruby.main.zipless.o: private	\
    CFLAGS +=							\
            -DRUBY_COSMO_RESET_LOAD_PATH			\
            -DRUBY_COSMO_LOAD_PATH0=\"$(abspath third_party/ruby/lib)\" \
            -DRUBY_COSMO_LOAD_PATH1=\"$(abspath third_party/ruby/ext/monitor/lib)\"

# miniruby zip main.o: no RUBY_COSMO_RESET_LOAD_PATH needed — loadpath.o
# in ruby.a already provides /zip paths via ruby_initial_load_paths[].

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

# ruby/irb zip main.o: no RUBY_COSMO_RESET_LOAD_PATH needed — loadpath.o
# in ruby.a already provides /zip paths via ruby_initial_load_paths[].

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
    THIRD_PARTY_MIMALLOC					\
    THIRD_PARTY_RUBY						\
    TOOL_ARGS							\
    THIRD_PARTY_COSMO_PLUGIN

THIRD_PARTY_RUBY_RUBY_DEPS :=					\
    $(call uniq,$(foreach x,$(THIRD_PARTY_RUBY_RUBY_DIRECTDEPS),$($(x))))

o/$(MODE)/third_party/ruby/ruby.pkg:				\
    o/$(MODE)/third_party/ruby/ruby.main.o			\
    o/$(MODE)/third_party/ruby/ruby_exports.o			\
    $(foreach x,$(THIRD_PARTY_RUBY_RUBY_DIRECTDEPS),$($(x)_A).pkg)
