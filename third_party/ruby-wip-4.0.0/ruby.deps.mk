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

# Modular Ruby extensions - each has its own BUILD.mk
# To enable/disable extensions, comment/uncomment these includes
# and update ext/extinit.c accordingly
include third_party/cosmo_plugin/BUILD.mk
include third_party/ruby/ext/date/BUILD.mk
include third_party/ruby/ext/digest/BUILD.mk
include third_party/ruby/ext/etc/BUILD.mk
include third_party/ruby/ext/io/nonblock/BUILD.mk
include third_party/ruby/ext/io/console/BUILD.mk
include third_party/ruby/ext/io/wait/BUILD.mk
include third_party/ruby/ext/json/BUILD.mk
include third_party/ruby/ext/ripper/BUILD.mk
include third_party/ruby/ext/mbedtls/BUILD.mk
include third_party/ruby/ext/monitor/BUILD.mk
include third_party/ruby/ext/psych/BUILD.mk
include third_party/ruby/ext/socket/BUILD.mk
include third_party/ruby/ext/stringio/BUILD.mk
include third_party/ruby/ext/zlib/BUILD.mk

PKGS += THIRD_PARTY_RUBY

# Detect extension mode from config.h (EXTSTATIC=0 => plugin/dynamic extensions).
RUBY_EXTSTATIC := $(shell awk '/^#define[[:space:]]+EXTSTATIC[[:space:]]+/{print $$3; exit}' third_party/ruby/include/ruby/config.h)
RUBY_EXTSTATIC ?= 1
RUBY_SLIM_STATIC := $(shell awk '/^#define[[:space:]]+SLIM_STATIC[[:space:]]+/{print $$3; exit}' third_party/ruby/include/ruby/config.h)
RUBY_SLIM_STATIC ?= 0

# All C extensions bundled with this port.
RUBY_ALL_EXTENSIONS =				\
	THIRD_PARTY_RUBY_EXT_DATE			\
	THIRD_PARTY_RUBY_EXT_DIGEST			\
	THIRD_PARTY_RUBY_EXT_ETC			\
	THIRD_PARTY_RUBY_EXT_IO_NONBLOCK		\
	THIRD_PARTY_RUBY_EXT_IO_CONSOLE		\
	THIRD_PARTY_RUBY_EXT_IO_WAIT			\
	THIRD_PARTY_RUBY_EXT_JSON			\
	THIRD_PARTY_RUBY_EXT_RIPPER			\
	THIRD_PARTY_RUBY_EXT_MBEDTLS			\
	THIRD_PARTY_RUBY_EXT_MONITOR			\
	THIRD_PARTY_RUBY_EXT_PSYCH			\
	THIRD_PARTY_RUBY_EXT_SOCKET			\
	THIRD_PARTY_RUBY_EXT_STRINGIO			\
	THIRD_PARTY_RUBY_EXT_ZLIB

# Link statically when EXTSTATIC=1; otherwise stage for plugins.
ifeq ($(RUBY_EXTSTATIC),0)
THIRD_PARTY_RUBY_EXTENSIONS :=
else
THIRD_PARTY_RUBY_EXTENSIONS := $(RUBY_ALL_EXTENSIONS)
endif

# Miniruby uses a subset of extensions; avoid baking them when EXTSTATIC=0.
ifeq ($(RUBY_EXTSTATIC),0)
THIRD_PARTY_RUBY_MINIRUBY_EXTENSIONS :=
else
THIRD_PARTY_RUBY_MINIRUBY_EXTENSIONS :=		\
	THIRD_PARTY_RUBY_EXT_MONITOR			\
	THIRD_PARTY_RUBY_EXT_STRINGIO
endif

# Always stage all extensions as plugins (harmless in static builds).
RUBY_PLUGIN_EXTENSIONS := $(RUBY_ALL_EXTENSIONS)

include third_party/ruby/ruby.plugins.mk

THIRD_PARTY_RUBY_COMS =						\
    o/$(MODE)/third_party/ruby/miniruby.zipless			\
    o/$(MODE)/third_party/ruby/miniruby				\
    o/$(MODE)/third_party/ruby/ruby.zipless			\
    o/$(MODE)/third_party/ruby/ruby				\
    o/$(MODE)/third_party/ruby/irb.zipless			\
    o/$(MODE)/third_party/ruby/irb

THIRD_PARTY_RUBY_BINS =						\
    $(THIRD_PARTY_RUBY_COMS)					\
    $(THIRD_PARTY_RUBY_COMS:%=%.dbg)

THIRD_PARTY_RUBY_CHECKS =					\
    $(THIRD_PARTY_RUBY_A).pkg					\
    $(THIRD_PARTY_RUBY_HDRS:%=o/$(MODE)/%.ok)			\
    $(THIRD_PARTY_RUBY_INCS:%=o/$(MODE)/%.ok)			\
    o/$(MODE)/third_party/ruby/miniruby.zipless.pkg		\
    o/$(MODE)/third_party/ruby/miniruby.pkg			\
    o/$(MODE)/third_party/ruby/ruby.zipless.pkg			\
    o/$(MODE)/third_party/ruby/ruby.pkg				\
    o/$(MODE)/third_party/ruby/irb.zipless.pkg			\
    o/$(MODE)/third_party/ruby/irb.pkg

ifeq ($(RUBY_EXTSTATIC),0)
THIRD_PARTY_RUBY_CHECKS += ruby.plugins
else ifeq ($(RUBY_SLIM_STATIC),1)
THIRD_PARTY_RUBY_CHECKS += ruby.plugins
endif


################################################################################
# ruby.a

THIRD_PARTY_RUBY =						\
    $(THIRD_PARTY_RUBY_A_DEPS)					\
    $(THIRD_PARTY_RUBY_A)

$(THIRD_PARTY_RUBY_A): ruby.codegen

THIRD_PARTY_RUBY_ARTIFACTS +=					\
    THIRD_PARTY_RUBY_A

THIRD_PARTY_RUBY_A =						\
    o/$(MODE)/third_party/ruby/ruby.a

# Public API headers (full paths for external code to include)
# For Stage 2 of mkdeps dependency resolution
THIRD_PARTY_RUBY_A_HDRS =\
	third_party/ruby/debug_counter.h\
	third_party/ruby/id.h\
	third_party/ruby/internal.h\
	third_party/ruby/internal/array.h\
	third_party/ruby/internal/compar.h\
	third_party/ruby/internal/enum.h\
	third_party/ruby/internal/gc.h\
	third_party/ruby/internal/hash.h\
	third_party/ruby/internal/numeric.h\
	third_party/ruby/internal/object.h\
	third_party/ruby/internal/proc.h\
	third_party/ruby/internal/rational.h\
	third_party/ruby/internal/vm.h\
	third_party/ruby/probes.h\
	third_party/ruby/include/ruby/encoding.h\
	third_party/ruby/include/ruby/st.h\
	third_party/ruby/include/ruby/util.h\
	third_party/ruby/vm_core.h\
	third_party/ruby/builtin.h\
	third_party/ruby/ruby_assert.h\
	third_party/ruby/array.rbinc\
	third_party/ruby/internal/ruby_parser.h\
	third_party/ruby/internal/symbol.h\
	third_party/ruby/internal/warnings.h\
	third_party/ruby/iseq.h\
	third_party/ruby/node.h\
	third_party/ruby/ast.rbinc\
	third_party/ruby/include/ruby/internal/config.h\
	third_party/ruby/internal/bignum.h\
	third_party/ruby/internal/complex.h\
	third_party/ruby/internal/sanitizers.h\
	third_party/ruby/internal/variable.h\
	third_party/ruby/include/ruby/thread.h\
	third_party/ruby/builtin_binary.rbbin\
	third_party/ruby/mini_builtin.c\
	third_party/ruby/constant.h\
	third_party/ruby/id_table.h\
	third_party/ruby/internal/class.h\
	third_party/ruby/internal/eval.h\
	third_party/ruby/internal/string.h\
	third_party/ruby/yjit.h\
	third_party/ruby/internal/error.h\
	third_party/ruby/encindex.h\
	third_party/ruby/internal/compile.h\
	third_party/ruby/internal/encoding.h\
	third_party/ruby/internal/io.h\
	third_party/ruby/internal/re.h\
	third_party/ruby/internal/thread.h\
	third_party/ruby/include/ruby/ractor.h\
	third_party/ruby/include/ruby/re.h\
	third_party/ruby/vm_callinfo.h\
	third_party/ruby/vm_debug.h\
	third_party/ruby/insns.inc\
	third_party/ruby/insns_info.inc\
	third_party/ruby/optinsn.inc\
	third_party/ruby/optunifs.inc\
	third_party/ruby/prism_compile.c\
	third_party/ruby/internal/math.h\
	third_party/ruby/eval_intern.h\
	third_party/ruby/internal/cont.h\
	third_party/ruby/include/ruby/fiber/scheduler.h\
	third_party/ruby/vm_sync.h\
	third_party/ruby/ractor_core.h\
	third_party/ruby/internal/signal.h\
	third_party/ruby/include/ruby/io.h\
	third_party/ruby/symbol.h\
	third_party/ruby/include/ruby/thread_native.h\
	third_party/ruby/win32/dir.h\
	third_party/ruby/internal/dir.h\
	third_party/ruby/internal/file.h\
	third_party/ruby/internal/imemo.h\
	third_party/ruby/dir.rbinc\
	third_party/ruby/dln.h\
	third_party/ruby/internal/compilers.h\
	third_party/ruby/missing/file.h\
	third_party/ruby/include/ruby/internal/stdbool.h\
	third_party/ruby/internal/enc.h\
	third_party/ruby/internal/inits.h\
	third_party/ruby/internal/load.h\
	third_party/ruby/regenc.h\
	third_party/ruby/include/verconf.h\
	third_party/ruby/version.h\
	third_party/ruby/internal/enumerator.h\
	third_party/ruby/internal/range.h\
	third_party/ruby/internal/process.h\
	third_party/ruby/known_errors.inc\
	third_party/ruby/warning.rbinc\
	third_party/ruby/probes_helper.h\
	third_party/ruby/include/ruby/vm.h\
	third_party/ruby/eval_error.c\
	third_party/ruby/eval_jump.c\
	third_party/ruby/win32/file.h\
	third_party/ruby/wasm/setjmp.h\
	third_party/ruby/wasm/machine.h\
	third_party/ruby/darray.h\
	third_party/ruby/gc/gc.h\
	third_party/ruby/internal/struct.h\
	third_party/ruby/regint.h\
	third_party/ruby/include/ruby/debug.h\
	third_party/ruby/ruby_atomic.h\
	third_party/ruby/shape.h\
	third_party/ruby/gc/default/default.c\
	third_party/ruby/gc.rbinc\
	third_party/ruby/missing/crt_externs.h\
	third_party/ruby/internal/basic_operators.h\
	third_party/ruby/internal/st.h\
	third_party/ruby/internal/time.h\
	third_party/ruby/hash.rbinc\
	third_party/ruby/prelude.rbinc\
	third_party/ruby/include/ruby/io/buffer.h\
	third_party/ruby/ccan/list/list.h\
	third_party/ruby/internal/transcode.h\
	third_party/ruby/include/ruby/missing.h\
	third_party/ruby/io.rbinc\
	third_party/ruby/internal/bits.h\
	third_party/ruby/internal/util.h\
	third_party/ruby/include/ruby/internal/attr/nonstring.h\
	third_party/ruby/marshal.rbinc\
	third_party/ruby/include/ruby/memory_view.h\
	third_party/ruby/rubyparser.h\
	third_party/ruby/node_name.inc\
	third_party/ruby/numeric.rbinc\
	third_party/ruby/variable.h\
	third_party/ruby/include/ruby/assert.h\
	third_party/ruby/kernel.rbinc\
	third_party/ruby/nilclass.rbinc\
	third_party/ruby/pack.rbinc\
	third_party/ruby/parser_node.h\
	third_party/ruby/universal_parser.c\
	third_party/ruby/internal/parse.h\
	third_party/ruby/include/ruby/regex.h\
	third_party/ruby/parser_st.h\
	third_party/ruby/ext/ripper/ripper_init.h\
	third_party/ruby/parse.h\
	third_party/ruby/ext/ripper/eventids1.h\
	third_party/ruby/ext/ripper/eventids2.h\
	third_party/ruby/lex.c\
	third_party/ruby/parser_bits.h\
	third_party/ruby/method.h\
	third_party/ruby/hrtime.h\
	third_party/ruby/internal/ractor.h\
	third_party/ruby/ractor.rbinc\
	third_party/ruby/internal/random.h\
	third_party/ruby/include/ruby/random.h\
	third_party/ruby/missing/mt19937.c\
	third_party/ruby/siphash.c\
	third_party/ruby/regparse.h\
	third_party/ruby/internal/cmdlineopt.h\
	third_party/ruby/internal/loadpath.h\
	third_party/ruby/internal/missing.h\
	third_party/ruby/include/ruby/version.h\
	third_party/ruby/include/ruby/internal/error.h\
	third_party/ruby/vsnprintf.c\
	third_party/ruby/timev.h\
	third_party/ruby/missing/crypt.h\
	third_party/ruby/include/ruby/atomic.h\
	third_party/ruby/id.c\
	third_party/ruby/id_table.c\
	third_party/ruby/symbol.rbinc\
	third_party/ruby/thread_sync.c\
	third_party/ruby/timezoneapi.h\
	third_party/ruby/timev.rbinc\
	third_party/ruby/transcode_data.h\
	third_party/ruby/missing/dtoa.c\
	third_party/ruby/vm_exec.h\
	third_party/ruby/vm_insnhelper.h\
	third_party/ruby/vm_insnhelper.c\
	third_party/ruby/vm_exec.c\
	third_party/ruby/vm_method.c\
	third_party/ruby/vm_eval.c\
	third_party/ruby/yjit_hook.rbinc\
	third_party/ruby/vm_call_iseq_optimized.inc\
	third_party/ruby/addr2line.h\
	third_party/ruby/missing/procstat_vm.c\
	third_party/ruby/trace_point.rbinc\
	third_party/ruby/enc/encdb.h\
	third_party/ruby/enc/unicode/17.0.0/casefold.h\
	third_party/ruby/enc/unicode/17.0.0/name2ctype.h\
	third_party/ruby/enc/iso_8859.h\
	third_party/ruby/enc/transdb.h\
	third_party/ruby/prism/extension.h\
	third_party/ruby/prism/diagnostic.h\
	third_party/ruby/prism/encoding.h\
	third_party/ruby/prism/node.h\
	third_party/ruby/prism/options.h\
	third_party/ruby/prism/pack.h\
	third_party/ruby/prism/prettyprint.h\
	third_party/ruby/prism/prism.h\
	third_party/ruby/prism/regexp.h\
	third_party/ruby/prism/static_literals.h\
	third_party/ruby/prism/ast.h\
	third_party/ruby/prism/util/pm_buffer.h\
	third_party/ruby/prism/util/pm_char.h\
	third_party/ruby/prism/util/pm_constant_pool.h\
	third_party/ruby/prism/util/pm_integer.h\
	third_party/ruby/prism/util/pm_list.h\
	third_party/ruby/prism/util/pm_memchr.h\
	third_party/ruby/prism/util/pm_newline_list.h\
	third_party/ruby/prism/util/pm_string.h\
	third_party/ruby/prism/util/pm_strncasecmp.h\
	third_party/ruby/prism/util/pm_strpbrk.h\
	third_party/ruby/include/ruby/defines.h\
	third_party/ruby/internal/static_assert.h\
	third_party/ruby/ext/io/console/win32_vk.inc\
	third_party/ruby/ruby_cosmo_main.h\
	third_party/ruby/internal/fixnum.h\
	third_party/ruby/include/ruby/intern.h\
	third_party/ruby/internal/serial.h\
	third_party/ruby/probes.dmyh\
	third_party/ruby/include/ruby/internal/encoding/coderange.h\
	third_party/ruby/include/ruby/internal/encoding/ctype.h\
	third_party/ruby/include/ruby/internal/encoding/encoding.h\
	third_party/ruby/include/ruby/internal/encoding/pathname.h\
	third_party/ruby/include/ruby/internal/encoding/re.h\
	third_party/ruby/include/ruby/internal/encoding/sprintf.h\
	third_party/ruby/include/ruby/internal/encoding/string.h\
	third_party/ruby/include/ruby/internal/encoding/symbol.h\
	third_party/ruby/include/ruby/internal/encoding/transcode.h\
	third_party/ruby/include/ruby/internal/attr/noalias.h\
	third_party/ruby/include/ruby/internal/attr/nodiscard.h\
	third_party/ruby/include/ruby/internal/attr/nonnull.h\
	third_party/ruby/include/ruby/internal/attr/restrict.h\
	third_party/ruby/include/ruby/internal/attr/returns_nonnull.h\
	third_party/ruby/include/ruby/internal/dllexport.h\
	third_party/ruby/vm_opts.h\
	third_party/ruby/include/ruby/internal/warning_push.h\
	third_party/ruby/prism_compile.h\
	third_party/ruby/include/ruby/backward/2/attributes.h\
	third_party/ruby/include/ruby/config.h\
	third_party/ruby/include/ruby/internal/compiler_since.h\
	third_party/ruby/include/ruby/internal/value.h\
	third_party/ruby/include/ruby/internal/intern/thread.h\
	third_party/ruby/include/ruby/internal/fl_type.h\
	third_party/ruby/include/ruby/internal/special_consts.h\
	third_party/ruby/include/ruby/onigmo.h\
	third_party/ruby/include/ruby/internal/core/rmatch.h\
	third_party/ruby/include/ruby/internal/arithmetic.h\
	third_party/ruby/include/ruby/internal/attr/const.h\
	third_party/ruby/include/ruby/internal/attr/packed_struct.h\
	third_party/ruby/include/ruby/internal/attr/pure.h\
	third_party/ruby/include/ruby/internal/attr/noreturn.h\
	third_party/ruby/include/ruby/internal/has/attribute.h\
	third_party/ruby/include/ruby/internal/has/builtin.h\
	third_party/ruby/include/ruby/internal/has/c_attribute.h\
	third_party/ruby/include/ruby/internal/has/declspec_attribute.h\
	third_party/ruby/include/ruby/internal/has/extension.h\
	third_party/ruby/include/ruby/internal/has/feature.h\
	third_party/ruby/include/ruby/internal/has/warning.h\
	third_party/ruby/include/ruby/backward/2/gcc_version_since.h\
	third_party/ruby/include/ruby/internal/abi.h\
	third_party/ruby/revision.h\
	third_party/ruby/include/ruby/win32.h\
	third_party/ruby/include/ruby/internal/attr/deprecated.h\
	third_party/ruby/include/ruby/internal/event.h\
	third_party/ruby/gc/gc_impl.h\
	third_party/ruby/include/ruby/internal/attr/format.h\
	third_party/ruby/include/ruby/internal/core/rtypeddata.h\
	third_party/ruby/parser_value.h\
	third_party/ruby/include/ruby/internal/assume.h\
	third_party/ruby/include/ruby/internal/attr/cold.h\
	third_party/ruby/include/ruby/internal/cast.h\
	third_party/ruby/include/ruby/backward/2/assume.h\
	third_party/ruby/include/ruby/backward/2/inttypes.h\
	third_party/ruby/include/ruby/oniguruma.h\
	third_party/ruby/include/ruby/backward/2/long_long.h\
	third_party/ruby/siphash.h\
	third_party/ruby/include/ruby/backward/2/limits.h\
	third_party/ruby/include/ruby/internal/attr/artificial.h\
	third_party/ruby/include/ruby/internal/static_assert.h\
	third_party/ruby/thread_sync.rbinc\
	third_party/ruby/vm_args.c\
	third_party/ruby/vmtc.inc\
	third_party/ruby/vm.inc\
	third_party/ruby/prism/defines.h\
	third_party/ruby/prism/parser.h\
	third_party/ruby/prism/version.h\
	third_party/ruby/include/ruby/internal/xmalloc.h\
	third_party/ruby/include/ruby/backward/2/bool.h\
	third_party/ruby/include/ruby/backward/2/stdalign.h\
	third_party/ruby/include/ruby/backward/2/stdarg.h\
	third_party/ruby/include/ruby/internal/dosish.h\
	third_party/ruby/include/ruby/internal/intern/array.h\
	third_party/ruby/include/ruby/internal/intern/bignum.h\
	third_party/ruby/include/ruby/internal/intern/class.h\
	third_party/ruby/include/ruby/internal/intern/compar.h\
	third_party/ruby/include/ruby/internal/intern/complex.h\
	third_party/ruby/include/ruby/internal/intern/cont.h\
	third_party/ruby/include/ruby/internal/intern/dir.h\
	third_party/ruby/include/ruby/internal/intern/enum.h\
	third_party/ruby/include/ruby/internal/intern/enumerator.h\
	third_party/ruby/include/ruby/internal/intern/error.h\
	third_party/ruby/include/ruby/internal/intern/eval.h\
	third_party/ruby/include/ruby/internal/intern/file.h\
	third_party/ruby/include/ruby/internal/intern/hash.h\
	third_party/ruby/include/ruby/internal/intern/io.h\
	third_party/ruby/include/ruby/internal/intern/load.h\
	third_party/ruby/include/ruby/internal/intern/marshal.h\
	third_party/ruby/include/ruby/internal/intern/numeric.h\
	third_party/ruby/include/ruby/internal/intern/object.h\
	third_party/ruby/include/ruby/internal/intern/parse.h\
	third_party/ruby/include/ruby/internal/intern/proc.h\
	third_party/ruby/include/ruby/internal/intern/process.h\
	third_party/ruby/include/ruby/internal/intern/random.h\
	third_party/ruby/include/ruby/internal/intern/range.h\
	third_party/ruby/include/ruby/internal/intern/rational.h\
	third_party/ruby/include/ruby/internal/intern/re.h\
	third_party/ruby/include/ruby/internal/intern/ruby.h\
	third_party/ruby/include/ruby/internal/intern/select.h\
	third_party/ruby/include/ruby/internal/intern/signal.h\
	third_party/ruby/include/ruby/internal/intern/sprintf.h\
	third_party/ruby/include/ruby/internal/intern/string.h\
	third_party/ruby/include/ruby/internal/intern/struct.h\
	third_party/ruby/include/ruby/internal/intern/time.h\
	third_party/ruby/include/ruby/internal/intern/variable.h\
	third_party/ruby/include/ruby/internal/intern/vm.h\
	third_party/ruby/include/ruby/internal/core/rbasic.h\
	third_party/ruby/include/ruby/internal/has/cpp_attribute.h\
	third_party/ruby/include/ruby/internal/compiler_is.h\
	third_party/ruby/include/ruby/internal/attr/alloc_size.h\
	third_party/ruby/include/ruby/internal/attr/error.h\
	third_party/ruby/include/ruby/internal/attr/forceinline.h\
	third_party/ruby/include/ruby/internal/attr/maybe_unused.h\
	third_party/ruby/include/ruby/internal/attr/noinline.h\
	third_party/ruby/include/ruby/internal/attr/warning.h\
	third_party/ruby/include/errno_wrapper.h\
	third_party/ruby/include/ruby/internal/attr/flag_enum.h\
	third_party/ruby/include/ruby/internal/value_type.h\
	third_party/ruby/include/ruby/internal/attr/constexpr.h\
	third_party/ruby/include/ruby/internal/attr/enum_extensibility.h\
	third_party/ruby/include/ruby/internal/arithmetic/char.h\
	third_party/ruby/include/ruby/internal/arithmetic/double.h\
	third_party/ruby/include/ruby/internal/arithmetic/fixnum.h\
	third_party/ruby/include/ruby/internal/arithmetic/gid_t.h\
	third_party/ruby/include/ruby/internal/arithmetic/int.h\
	third_party/ruby/include/ruby/internal/arithmetic/intptr_t.h\
	third_party/ruby/include/ruby/internal/arithmetic/long.h\
	third_party/ruby/include/ruby/internal/arithmetic/long_long.h\
	third_party/ruby/include/ruby/internal/arithmetic/mode_t.h\
	third_party/ruby/include/ruby/internal/arithmetic/off_t.h\
	third_party/ruby/include/ruby/internal/arithmetic/pid_t.h\
	third_party/ruby/include/ruby/internal/arithmetic/short.h\
	third_party/ruby/include/ruby/internal/arithmetic/size_t.h\
	third_party/ruby/include/ruby/internal/arithmetic/st_data_t.h\
	third_party/ruby/include/ruby/internal/arithmetic/uid_t.h\
	third_party/ruby/include/ruby/internal/core/rdata.h\
	third_party/ruby/prism/prism_xallocator.h\
	third_party/ruby/include/ruby/internal/attr/noexcept.h\
	third_party/ruby/include/ruby/internal/stdalign.h\
	third_party/ruby/include/ruby/internal/iterator.h\
	third_party/ruby/include/ruby/internal/symbol.h\
	third_party/ruby/include/ruby/internal/intern/select/largesize.h\
	third_party/ruby/include/ruby/internal/intern/select/win32.h\
	third_party/ruby/include/ruby/internal/intern/select/posix.h\
	third_party/ruby/include/ruby/internal/constant_p.h\
	third_party/ruby/include/ruby/internal/variable.h\
	third_party/ruby/include/ruby/internal/compiler_is/apple.h\
	third_party/ruby/include/ruby/internal/compiler_is/clang.h\
	third_party/ruby/include/ruby/internal/compiler_is/gcc.h\
	third_party/ruby/include/ruby/internal/compiler_is/intel.h\
	third_party/ruby/include/ruby/internal/compiler_is/msvc.h\
	third_party/ruby/include/ruby/internal/compiler_is/sunpro.h\
	third_party/ruby/include/ruby/internal/core/rstring.h
# List Ruby core included files (relative paths as they appear in #include directives)
# For Stage 1 of mkdeps dependency resolution (trick it with shims)
THIRD_PARTY_RUBY_A_INCS =\
	ruby-4.0.0_shims/third_party+ruby+include+ruby.h\
	ruby-4.0.0_shims/debug_counter.h\
	ruby-4.0.0_shims/id.h\
	ruby-4.0.0_shims/internal.h\
	ruby-4.0.0_shims/internal+array.h\
	ruby-4.0.0_shims/internal+compar.h\
	ruby-4.0.0_shims/internal+enum.h\
	ruby-4.0.0_shims/internal+gc.h\
	ruby-4.0.0_shims/internal+hash.h\
	ruby-4.0.0_shims/internal+numeric.h\
	ruby-4.0.0_shims/internal+object.h\
	ruby-4.0.0_shims/internal+proc.h\
	ruby-4.0.0_shims/internal+rational.h\
	ruby-4.0.0_shims/internal+vm.h\
	ruby-4.0.0_shims/probes.h\
	ruby-4.0.0_shims/ruby+encoding.h\
	ruby-4.0.0_shims/ruby+st.h\
	ruby-4.0.0_shims/ruby+util.h\
	ruby-4.0.0_shims/vm_core.h\
	ruby-4.0.0_shims/builtin.h\
	ruby-4.0.0_shims/ruby_assert.h\
	ruby-4.0.0_shims/array.rbinc\
	ruby-4.0.0_shims/internal+ruby_parser.h\
	ruby-4.0.0_shims/internal+symbol.h\
	ruby-4.0.0_shims/internal+warnings.h\
	ruby-4.0.0_shims/iseq.h\
	ruby-4.0.0_shims/node.h\
	ruby-4.0.0_shims/ruby.h\
	ruby-4.0.0_shims/ast.rbinc\
	ruby-4.0.0_shims/ruby+internal+config.h\
	ruby-4.0.0_shims/internal+bignum.h\
	ruby-4.0.0_shims/internal+complex.h\
	ruby-4.0.0_shims/internal+sanitizers.h\
	ruby-4.0.0_shims/internal+variable.h\
	ruby-4.0.0_shims/ruby+thread.h\
	ruby-4.0.0_shims/builtin_binary.rbbin\
	ruby-4.0.0_shims/mini_builtin.c\
	ruby-4.0.0_shims/constant.h\
	ruby-4.0.0_shims/id_table.h\
	ruby-4.0.0_shims/internal+class.h\
	ruby-4.0.0_shims/internal+eval.h\
	ruby-4.0.0_shims/internal+string.h\
	ruby-4.0.0_shims/yjit.h\
	ruby-4.0.0_shims/internal+error.h\
	ruby-4.0.0_shims/ruby+ruby.h\
	ruby-4.0.0_shims/encindex.h\
	ruby-4.0.0_shims/internal+compile.h\
	ruby-4.0.0_shims/internal+encoding.h\
	ruby-4.0.0_shims/internal+io.h\
	ruby-4.0.0_shims/internal+re.h\
	ruby-4.0.0_shims/internal+thread.h\
	ruby-4.0.0_shims/ruby+ractor.h\
	ruby-4.0.0_shims/ruby+re.h\
	ruby-4.0.0_shims/vm_callinfo.h\
	ruby-4.0.0_shims/vm_debug.h\
	ruby-4.0.0_shims/insns.inc\
	ruby-4.0.0_shims/insns_info.inc\
	ruby-4.0.0_shims/optinsn.inc\
	ruby-4.0.0_shims/optunifs.inc\
	ruby-4.0.0_shims/prism_compile.c\
	ruby-4.0.0_shims/internal+math.h\
	ruby-4.0.0_shims/eval_intern.h\
	ruby-4.0.0_shims/internal+cont.h\
	ruby-4.0.0_shims/ruby+fiber+scheduler.h\
	ruby-4.0.0_shims/vm_sync.h\
	ruby-4.0.0_shims/ractor_core.h\
	ruby-4.0.0_shims/internal+signal.h\
	ruby-4.0.0_shims/ruby+io.h\
	ruby-4.0.0_shims/symbol.h\
	ruby-4.0.0_shims/ruby+thread_native.h\
	ruby-4.0.0_shims/win32+dir.h\
	ruby-4.0.0_shims/internal+dir.h\
	ruby-4.0.0_shims/internal+file.h\
	ruby-4.0.0_shims/internal+imemo.h\
	ruby-4.0.0_shims/dir.rbinc\
	ruby-4.0.0_shims/dln.h\
	ruby-4.0.0_shims/internal+compilers.h\
	ruby-4.0.0_shims/missing+file.h\
	ruby-4.0.0_shims/ruby+internal+stdbool.h\
	ruby-4.0.0_shims/third_party+ruby+include+ruby+ruby.h\
	ruby-4.0.0_shims/internal+enc.h\
	ruby-4.0.0_shims/internal+inits.h\
	ruby-4.0.0_shims/internal+load.h\
	ruby-4.0.0_shims/regenc.h\
	ruby-4.0.0_shims/verconf.h\
	ruby-4.0.0_shims/version.h\
	ruby-4.0.0_shims/internal+enumerator.h\
	ruby-4.0.0_shims/internal+range.h\
	ruby-4.0.0_shims/internal+process.h\
	ruby-4.0.0_shims/known_errors.inc\
	ruby-4.0.0_shims/warning.rbinc\
	ruby-4.0.0_shims/probes_helper.h\
	ruby-4.0.0_shims/ruby+vm.h\
	ruby-4.0.0_shims/eval_error.c\
	ruby-4.0.0_shims/eval_jump.c\
	ruby-4.0.0_shims/win32+file.h\
	ruby-4.0.0_shims/wasm+setjmp.h\
	ruby-4.0.0_shims/wasm+machine.h\
	ruby-4.0.0_shims/darray.h\
	ruby-4.0.0_shims/gc+gc.h\
	ruby-4.0.0_shims/internal+struct.h\
	ruby-4.0.0_shims/regint.h\
	ruby-4.0.0_shims/ruby+debug.h\
	ruby-4.0.0_shims/ruby_atomic.h\
	ruby-4.0.0_shims/shape.h\
	ruby-4.0.0_shims/gc+default+default.c\
	ruby-4.0.0_shims/gc.rbinc\
	ruby-4.0.0_shims/missing+crt_externs.h\
	ruby-4.0.0_shims/internal+basic_operators.h\
	ruby-4.0.0_shims/internal+st.h\
	ruby-4.0.0_shims/internal+time.h\
	ruby-4.0.0_shims/hash.rbinc\
	ruby-4.0.0_shims/prelude.rbinc\
	ruby-4.0.0_shims/ruby+io+buffer.h\
	ruby-4.0.0_shims/ccan+list+list.h\
	ruby-4.0.0_shims/internal+transcode.h\
	ruby-4.0.0_shims/ruby+missing.h\
	ruby-4.0.0_shims/io.rbinc\
	ruby-4.0.0_shims/internal+bits.h\
	ruby-4.0.0_shims/internal+util.h\
	ruby-4.0.0_shims/ruby+internal+attr+nonstring.h\
	ruby-4.0.0_shims/marshal.rbinc\
	ruby-4.0.0_shims/ruby+memory_view.h\
	ruby-4.0.0_shims/rubyparser.h\
	ruby-4.0.0_shims/node_name.inc\
	ruby-4.0.0_shims/numeric.rbinc\
	ruby-4.0.0_shims/variable.h\
	ruby-4.0.0_shims/ruby+assert.h\
	ruby-4.0.0_shims/kernel.rbinc\
	ruby-4.0.0_shims/nilclass.rbinc\
	ruby-4.0.0_shims/pack.rbinc\
	ruby-4.0.0_shims/parser_node.h\
	ruby-4.0.0_shims/universal_parser.c\
	ruby-4.0.0_shims/internal+parse.h\
	ruby-4.0.0_shims/ruby+regex.h\
	ruby-4.0.0_shims/parser_st.h\
	ruby-4.0.0_shims/ripper_init.h\
	ruby-4.0.0_shims/parse.h\
	ruby-4.0.0_shims/eventids1.h\
	ruby-4.0.0_shims/eventids2.h\
	ruby-4.0.0_shims/lex.c\
	ruby-4.0.0_shims/parser_bits.h\
	ruby-4.0.0_shims/method.h\
	ruby-4.0.0_shims/hrtime.h\
	ruby-4.0.0_shims/internal+ractor.h\
	ruby-4.0.0_shims/ractor.rbinc\
	ruby-4.0.0_shims/internal+random.h\
	ruby-4.0.0_shims/ruby+random.h\
	ruby-4.0.0_shims/missing+mt19937.c\
	ruby-4.0.0_shims/siphash.c\
	ruby-4.0.0_shims/regparse.h\
	ruby-4.0.0_shims/st.h\
	ruby-4.0.0_shims/internal+cmdlineopt.h\
	ruby-4.0.0_shims/internal+loadpath.h\
	ruby-4.0.0_shims/internal+missing.h\
	ruby-4.0.0_shims/ruby+version.h\
	ruby-4.0.0_shims/ruby+internal+error.h\
	ruby-4.0.0_shims/vsnprintf.c\
	ruby-4.0.0_shims/timev.h\
	ruby-4.0.0_shims/missing+crypt.h\
	ruby-4.0.0_shims/ruby+atomic.h\
	ruby-4.0.0_shims/id.c\
	ruby-4.0.0_shims/id_table.c\
	ruby-4.0.0_shims/symbol.rbinc\
	ruby-4.0.0_shims/thread_sync.c\
	ruby-4.0.0_shims/timezoneapi.h\
	ruby-4.0.0_shims/timev.rbinc\
	ruby-4.0.0_shims/transcode_data.h\
	ruby-4.0.0_shims/missing+dtoa.c\
	ruby-4.0.0_shims/vm_exec.h\
	ruby-4.0.0_shims/vm_insnhelper.h\
	ruby-4.0.0_shims/vm_insnhelper.c\
	ruby-4.0.0_shims/vm_exec.c\
	ruby-4.0.0_shims/vm_method.c\
	ruby-4.0.0_shims/vm_eval.c\
	ruby-4.0.0_shims/yjit_hook.rbinc\
	ruby-4.0.0_shims/vm_call_iseq_optimized.inc\
	ruby-4.0.0_shims/addr2line.h\
	ruby-4.0.0_shims/missing+procstat_vm.c\
	ruby-4.0.0_shims/trace_point.rbinc\
	ruby-4.0.0_shims/encdb.h\
	ruby-4.0.0_shims/casefold.h\
	ruby-4.0.0_shims/name2ctype.h\
	ruby-4.0.0_shims/iso_8859.h\
	ruby-4.0.0_shims/transdb.h\
	ruby-4.0.0_shims/prism+extension.h\
	ruby-4.0.0_shims/prism+diagnostic.h\
	ruby-4.0.0_shims/prism+encoding.h\
	ruby-4.0.0_shims/prism+node.h\
	ruby-4.0.0_shims/prism+options.h\
	ruby-4.0.0_shims/prism+pack.h\
	ruby-4.0.0_shims/prism+prettyprint.h\
	ruby-4.0.0_shims/prism.h\
	ruby-4.0.0_shims/prism+regexp.h\
	ruby-4.0.0_shims/prism+static_literals.h\
	ruby-4.0.0_shims/prism+ast.h\
	ruby-4.0.0_shims/prism+util+pm_buffer.h\
	ruby-4.0.0_shims/prism+util+pm_char.h\
	ruby-4.0.0_shims/prism+util+pm_constant_pool.h\
	ruby-4.0.0_shims/prism+util+pm_integer.h\
	ruby-4.0.0_shims/prism+util+pm_list.h\
	ruby-4.0.0_shims/prism+util+pm_memchr.h\
	ruby-4.0.0_shims/prism+util+pm_newline_list.h\
	ruby-4.0.0_shims/prism+util+pm_string.h\
	ruby-4.0.0_shims/prism+util+pm_strncasecmp.h\
	ruby-4.0.0_shims/prism+util+pm_strpbrk.h\
	ruby-4.0.0_shims/crt_externs.h\
	ruby-4.0.0_shims/dladdr.h\
	ruby-4.0.0_shims/ruby+defines.h\
	ruby-4.0.0_shims/missing+dladdr.h\
	ruby-4.0.0_shims/internal+static_assert.h\
	ruby-4.0.0_shims/win32_vk.inc\
	ruby-4.0.0_shims/ruby_cosmo_main.h\
	ruby-4.0.0_shims/internal+fixnum.h\
	ruby-4.0.0_shims/ruby+intern.h\
	ruby-4.0.0_shims/internal+serial.h\
	ruby-4.0.0_shims/probes.dmyh\
	ruby-4.0.0_shims/ruby+internal+encoding+coderange.h\
	ruby-4.0.0_shims/ruby+internal+encoding+ctype.h\
	ruby-4.0.0_shims/ruby+internal+encoding+encoding.h\
	ruby-4.0.0_shims/ruby+internal+encoding+pathname.h\
	ruby-4.0.0_shims/ruby+internal+encoding+re.h\
	ruby-4.0.0_shims/ruby+internal+encoding+sprintf.h\
	ruby-4.0.0_shims/ruby+internal+encoding+string.h\
	ruby-4.0.0_shims/ruby+internal+encoding+symbol.h\
	ruby-4.0.0_shims/ruby+internal+encoding+transcode.h\
	ruby-4.0.0_shims/ruby+internal+attr+noalias.h\
	ruby-4.0.0_shims/ruby+internal+attr+nodiscard.h\
	ruby-4.0.0_shims/ruby+internal+attr+nonnull.h\
	ruby-4.0.0_shims/ruby+internal+attr+restrict.h\
	ruby-4.0.0_shims/ruby+internal+attr+returns_nonnull.h\
	ruby-4.0.0_shims/ruby+internal+dllexport.h\
	ruby-4.0.0_shims/vm_opts.h\
	ruby-4.0.0_shims/ruby+internal+warning_push.h\
	ruby-4.0.0_shims/prism_compile.h\
	ruby-4.0.0_shims/ruby+backward+2+attributes.h\
	ruby-4.0.0_shims/ruby+config.h\
	ruby-4.0.0_shims/ruby+internal+compiler_since.h\
	ruby-4.0.0_shims/ruby+internal+value.h\
	ruby-4.0.0_shims/ruby+internal+intern+thread.h\
	ruby-4.0.0_shims/internal+dllexport.h\
	ruby-4.0.0_shims/internal+fl_type.h\
	ruby-4.0.0_shims/internal+special_consts.h\
	ruby-4.0.0_shims/internal+stdbool.h\
	ruby-4.0.0_shims/internal+value.h\
	ruby-4.0.0_shims/ruby+onigmo.h\
	ruby-4.0.0_shims/ruby+internal+core+rmatch.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic.h\
	ruby-4.0.0_shims/ruby+internal+attr+const.h\
	ruby-4.0.0_shims/ruby+internal+attr+packed_struct.h\
	ruby-4.0.0_shims/ruby+internal+attr+pure.h\
	ruby-4.0.0_shims/ruby+internal+attr+noreturn.h\
	ruby-4.0.0_shims/ruby+internal+has+attribute.h\
	ruby-4.0.0_shims/ruby+internal+has+builtin.h\
	ruby-4.0.0_shims/ruby+internal+has+c_attribute.h\
	ruby-4.0.0_shims/ruby+internal+has+declspec_attribute.h\
	ruby-4.0.0_shims/ruby+internal+has+extension.h\
	ruby-4.0.0_shims/ruby+internal+has+feature.h\
	ruby-4.0.0_shims/ruby+internal+has+warning.h\
	ruby-4.0.0_shims/ruby+backward+2+gcc_version_since.h\
	ruby-4.0.0_shims/onigmo.h\
	ruby-4.0.0_shims/ruby+internal+abi.h\
	ruby-4.0.0_shims/revision.h\
	ruby-4.0.0_shims/ruby+win32.h\
	ruby-4.0.0_shims/ruby+internal+attr+deprecated.h\
	ruby-4.0.0_shims/ruby+internal+event.h\
	ruby-4.0.0_shims/gc+gc_impl.h\
	ruby-4.0.0_shims/include+ruby+st.h\
	ruby-4.0.0_shims/third_party+ruby+ccan+str+str.h\
	ruby-4.0.0_shims/third_party+ruby+ccan+container_of+container_of.h\
	ruby-4.0.0_shims/third_party+ruby+ccan+check_type+check_type.h\
	ruby-4.0.0_shims/ruby+internal+attr+format.h\
	ruby-4.0.0_shims/ruby+internal+core+rtypeddata.h\
	ruby-4.0.0_shims/parser_value.h\
	ruby-4.0.0_shims/ruby+internal+assume.h\
	ruby-4.0.0_shims/ruby+internal+attr+cold.h\
	ruby-4.0.0_shims/ruby+internal+cast.h\
	ruby-4.0.0_shims/ruby+backward+2+assume.h\
	ruby-4.0.0_shims/ruby+backward+2+inttypes.h\
	ruby-4.0.0_shims/ruby+oniguruma.h\
	ruby-4.0.0_shims/oniguruma.h\
	ruby-4.0.0_shims/ruby+backward+2+long_long.h\
	ruby-4.0.0_shims/siphash.h\
	ruby-4.0.0_shims/ruby+backward+2+limits.h\
	ruby-4.0.0_shims/ruby+internal+attr+artificial.h\
	ruby-4.0.0_shims/ruby+internal+static_assert.h\
	ruby-4.0.0_shims/thread_sync.rbinc\
	ruby-4.0.0_shims/vm_args.c\
	ruby-4.0.0_shims/vmtc.inc\
	ruby-4.0.0_shims/vm.inc\
	ruby-4.0.0_shims/prism+defines.h\
	ruby-4.0.0_shims/prism+parser.h\
	ruby-4.0.0_shims/prism+version.h\
	ruby-4.0.0_shims/ruby+internal+xmalloc.h\
	ruby-4.0.0_shims/ruby+backward+2+bool.h\
	ruby-4.0.0_shims/ruby+backward+2+stdalign.h\
	ruby-4.0.0_shims/ruby+backward+2+stdarg.h\
	ruby-4.0.0_shims/ruby+internal+dosish.h\
	ruby-4.0.0_shims/ruby+internal+intern+array.h\
	ruby-4.0.0_shims/ruby+internal+intern+bignum.h\
	ruby-4.0.0_shims/ruby+internal+intern+class.h\
	ruby-4.0.0_shims/ruby+internal+intern+compar.h\
	ruby-4.0.0_shims/ruby+internal+intern+complex.h\
	ruby-4.0.0_shims/ruby+internal+intern+cont.h\
	ruby-4.0.0_shims/ruby+internal+intern+dir.h\
	ruby-4.0.0_shims/ruby+internal+intern+enum.h\
	ruby-4.0.0_shims/ruby+internal+intern+enumerator.h\
	ruby-4.0.0_shims/ruby+internal+intern+error.h\
	ruby-4.0.0_shims/ruby+internal+intern+eval.h\
	ruby-4.0.0_shims/ruby+internal+intern+file.h\
	ruby-4.0.0_shims/ruby+internal+intern+hash.h\
	ruby-4.0.0_shims/ruby+internal+intern+io.h\
	ruby-4.0.0_shims/ruby+internal+intern+load.h\
	ruby-4.0.0_shims/ruby+internal+intern+marshal.h\
	ruby-4.0.0_shims/ruby+internal+intern+numeric.h\
	ruby-4.0.0_shims/ruby+internal+intern+object.h\
	ruby-4.0.0_shims/ruby+internal+intern+parse.h\
	ruby-4.0.0_shims/ruby+internal+intern+proc.h\
	ruby-4.0.0_shims/ruby+internal+intern+process.h\
	ruby-4.0.0_shims/ruby+internal+intern+random.h\
	ruby-4.0.0_shims/ruby+internal+intern+range.h\
	ruby-4.0.0_shims/ruby+internal+intern+rational.h\
	ruby-4.0.0_shims/ruby+internal+intern+re.h\
	ruby-4.0.0_shims/ruby+internal+intern+ruby.h\
	ruby-4.0.0_shims/ruby+internal+intern+select.h\
	ruby-4.0.0_shims/ruby+internal+intern+signal.h\
	ruby-4.0.0_shims/ruby+internal+intern+sprintf.h\
	ruby-4.0.0_shims/ruby+internal+intern+string.h\
	ruby-4.0.0_shims/ruby+internal+intern+struct.h\
	ruby-4.0.0_shims/ruby+internal+intern+time.h\
	ruby-4.0.0_shims/ruby+internal+intern+variable.h\
	ruby-4.0.0_shims/ruby+internal+intern+vm.h\
	ruby-4.0.0_shims/ruby+internal+fl_type.h\
	ruby-4.0.0_shims/ruby+internal+core+rbasic.h\
	ruby-4.0.0_shims/ruby+internal+has+cpp_attribute.h\
	ruby-4.0.0_shims/ruby+internal+compiler_is.h\
	ruby-4.0.0_shims/prism+prism.h\
	ruby-4.0.0_shims/ruby+internal+attr+alloc_size.h\
	ruby-4.0.0_shims/ruby+internal+attr+error.h\
	ruby-4.0.0_shims/ruby+internal+attr+forceinline.h\
	ruby-4.0.0_shims/ruby+internal+attr+maybe_unused.h\
	ruby-4.0.0_shims/ruby+internal+attr+noinline.h\
	ruby-4.0.0_shims/ruby+internal+attr+warning.h\
	ruby-4.0.0_shims/errno_wrapper.h\
	ruby-4.0.0_shims/ruby+internal+attr+flag_enum.h\
	ruby-4.0.0_shims/ruby+internal+special_consts.h\
	ruby-4.0.0_shims/ruby+internal+value_type.h\
	ruby-4.0.0_shims/ruby+internal+attr+constexpr.h\
	ruby-4.0.0_shims/ruby+internal+attr+enum_extensibility.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+char.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+double.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+fixnum.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+gid_t.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+int.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+intptr_t.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+long.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+long_long.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+mode_t.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+off_t.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+pid_t.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+short.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+size_t.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+st_data_t.h\
	ruby-4.0.0_shims/ruby+internal+arithmetic+uid_t.h\
	ruby-4.0.0_shims/ruby+internal+core+rdata.h\
	ruby-4.0.0_shims/prism_xallocator.h\
	ruby-4.0.0_shims/ruby+internal+attr+noexcept.h\
	ruby-4.0.0_shims/ruby+internal+stdalign.h\
	ruby-4.0.0_shims/ruby+internal+iterator.h\
	ruby-4.0.0_shims/ruby+internal+symbol.h\
	ruby-4.0.0_shims/ruby+internal+intern+select+largesize.h\
	ruby-4.0.0_shims/ruby+internal+intern+select+win32.h\
	ruby-4.0.0_shims/ruby+internal+intern+select+posix.h\
	ruby-4.0.0_shims/ruby+internal+constant_p.h\
	ruby-4.0.0_shims/ruby+internal+variable.h\
	ruby-4.0.0_shims/ruby+internal+compiler_is+apple.h\
	ruby-4.0.0_shims/ruby+internal+compiler_is+clang.h\
	ruby-4.0.0_shims/ruby+internal+compiler_is+gcc.h\
	ruby-4.0.0_shims/ruby+internal+compiler_is+intel.h\
	ruby-4.0.0_shims/ruby+internal+compiler_is+msvc.h\
	ruby-4.0.0_shims/ruby+internal+compiler_is+sunpro.h\
	ruby-4.0.0_shims/ruby+internal+core+rstring.h
# Ruby core source files: VM, encodings, transcoders, prism parser, and portability shims
# NOTE: Extensions (ripper, io/*, pathname, stringio, monitor, socket) are built separately via BUILD.mk files
# Note: Some .c files are not listed here because they're included by other files (e.g., constdefs.c) or provided by Cosmopolitan (e.g., getaddrinfo.c)
THIRD_PARTY_RUBY_A_SRCS_C =					\
    third_party/ruby/array.c					\
    third_party/ruby/ast.c					\
    third_party/ruby/bignum.c					\
    third_party/ruby/box.c					\
    third_party/ruby/builtin.c					\
    third_party/ruby/class.c					\
    third_party/ruby/compar.c					\
    third_party/ruby/compile.c					\
    third_party/ruby/complex.c					\
    third_party/ruby/concurrent_set.c				\
    third_party/ruby/cont.c					\
    third_party/ruby/debug.c					\
    third_party/ruby/debug_counter.c				\
    third_party/ruby/dir.c					\
    third_party/ruby/ext/extinit.c				\
    third_party/ruby/dln.c					\
    third_party/ruby/dln_cosmo.c				\
    third_party/ruby/enc/enc/encinit.c				\
    third_party/ruby/dln_find.c					\
    third_party/ruby/encoding.c					\
    third_party/ruby/loadpath.c					\
    third_party/ruby/localeinit.c				\
    third_party/ruby/enum.c					\
    third_party/ruby/enumerator.c				\
    third_party/ruby/error.c					\
    third_party/ruby/eval.c					\
    third_party/ruby/file.c					\
    third_party/ruby/gc.c					\
    third_party/ruby/hash.c					\
    third_party/ruby/imemo.c					\
    third_party/ruby/inits.c					\
    third_party/ruby/io.c					\
    third_party/ruby/io_buffer.c				\
    third_party/ruby/iseq.c					\
    third_party/ruby/load.c					\
    third_party/ruby/marshal.c					\
    third_party/ruby/math.c					\
    third_party/ruby/memory_view.c				\
    third_party/ruby/miniprelude.c				\
    third_party/ruby/node.c					\
    third_party/ruby/node_dump.c				\
    third_party/ruby/numeric.c					\
    third_party/ruby/object.c					\
    third_party/ruby/pack.c					\
    third_party/ruby/pathname.c					\
    third_party/ruby/parse.c					\
    third_party/ruby/parser_st.c				\
    third_party/ruby/proc.c					\
    third_party/ruby/process.c					\
    third_party/ruby/ractor.c					\
    third_party/ruby/random.c					\
    third_party/ruby/range.c					\
    third_party/ruby/rational.c					\
    third_party/ruby/re.c					\
    third_party/ruby/regcomp.c					\
    third_party/ruby/regenc.c					\
    third_party/ruby/regerror.c					\
    third_party/ruby/regexec.c					\
    third_party/ruby/regparse.c					\
    third_party/ruby/regsyntax.c				\
    third_party/ruby/ruby.c					\
    third_party/ruby/ruby_parser.c				\
    third_party/ruby/scheduler.c				\
    third_party/ruby/set.c					\
    third_party/ruby/shape.c					\
    third_party/ruby/signal.c					\
    third_party/ruby/sprintf.c					\
    third_party/ruby/st.c					\
    third_party/ruby/strftime.c					\
    third_party/ruby/string.c					\
    third_party/ruby/struct.c					\
    third_party/ruby/symbol.c					\
    third_party/ruby/thread.c					\
    third_party/ruby/time.c					\
    third_party/ruby/transcode.c				\
    third_party/ruby/util.c					\
    third_party/ruby/variable.c					\
    third_party/ruby/version.c					\
    third_party/ruby/vm.c					\
    third_party/ruby/weakmap.c					\
    third_party/ruby/vm_backtrace.c				\
    third_party/ruby/vm_dump.c					\
    third_party/ruby/vm_sync.c					\
    third_party/ruby/vm_trace.c					\
    third_party/ruby/enc/ascii.c				\
    third_party/ruby/enc/big5.c					\
    third_party/ruby/enc/cesu_8.c				\
    third_party/ruby/enc/cp949.c				\
    third_party/ruby/enc/emacs_mule.c				\
    third_party/ruby/enc/encdb.c				\
    third_party/ruby/enc/euc_jp.c				\
    third_party/ruby/enc/euc_kr.c				\
    third_party/ruby/enc/euc_tw.c				\
    third_party/ruby/enc/gb18030.c				\
    third_party/ruby/enc/gb2312.c				\
    third_party/ruby/enc/gbk.c					\
    third_party/ruby/enc/iso_8859_1.c				\
    third_party/ruby/enc/iso_8859_2.c				\
    third_party/ruby/enc/iso_8859_3.c				\
    third_party/ruby/enc/iso_8859_4.c				\
    third_party/ruby/enc/iso_8859_5.c				\
    third_party/ruby/enc/iso_8859_6.c				\
    third_party/ruby/enc/iso_8859_7.c				\
    third_party/ruby/enc/iso_8859_8.c				\
    third_party/ruby/enc/iso_8859_9.c				\
    third_party/ruby/enc/iso_8859_10.c				\
    third_party/ruby/enc/iso_8859_11.c				\
    third_party/ruby/enc/iso_8859_13.c				\
    third_party/ruby/enc/iso_8859_14.c				\
    third_party/ruby/enc/iso_8859_15.c				\
    third_party/ruby/enc/iso_8859_16.c				\
    third_party/ruby/enc/koi8_r.c				\
    third_party/ruby/enc/koi8_u.c				\
    third_party/ruby/enc/shift_jis.c				\
    third_party/ruby/enc/unicode.c				\
    third_party/ruby/enc/us_ascii.c				\
    third_party/ruby/enc/utf_8.c				\
    third_party/ruby/enc/utf_16be.c				\
    third_party/ruby/enc/utf_16le.c				\
    third_party/ruby/enc/utf_32be.c				\
    third_party/ruby/enc/utf_32le.c				\
    third_party/ruby/enc/windows_31j.c				\
    third_party/ruby/enc/windows_1250.c				\
    third_party/ruby/enc/windows_1251.c				\
    third_party/ruby/enc/windows_1252.c				\
    third_party/ruby/enc/windows_1253.c				\
    third_party/ruby/enc/windows_1254.c				\
    third_party/ruby/enc/windows_1257.c				\
    third_party/ruby/enc/trans/big5.c				\
    third_party/ruby/enc/trans/cesu_8.c				\
    third_party/ruby/enc/trans/chinese.c			\
    third_party/ruby/enc/trans/ebcdic.c				\
    third_party/ruby/enc/trans/emoji.c				\
    third_party/ruby/enc/trans/emoji_iso2022_kddi.c		\
    third_party/ruby/enc/trans/emoji_sjis_docomo.c		\
    third_party/ruby/enc/trans/emoji_sjis_kddi.c		\
    third_party/ruby/enc/trans/emoji_sjis_softbank.c		\
    third_party/ruby/enc/trans/escape.c				\
    third_party/ruby/enc/trans/gb18030.c			\
    third_party/ruby/enc/trans/gbk.c				\
    third_party/ruby/enc/trans/iso2022.c			\
    third_party/ruby/enc/trans/japanese.c			\
    third_party/ruby/enc/trans/japanese_euc.c			\
    third_party/ruby/enc/trans/japanese_sjis.c			\
    third_party/ruby/enc/trans/korean.c				\
    third_party/ruby/enc/trans/newline.c			\
    third_party/ruby/enc/trans/single_byte.c			\
    third_party/ruby/enc/trans/transdb.c			\
    third_party/ruby/enc/trans/utf_16_32.c			\
    third_party/ruby/enc/trans/utf8_mac.c			\
    third_party/ruby/prism_init.c				\
    third_party/ruby/prism/api_node.c				\
    third_party/ruby/prism/api_pack.c				\
    third_party/ruby/prism/diagnostic.c				\
    third_party/ruby/prism/encoding.c				\
    third_party/ruby/prism/extension.c				\
    third_party/ruby/prism/node.c				\
    third_party/ruby/prism/options.c				\
    third_party/ruby/prism/pack.c				\
    third_party/ruby/prism/prettyprint.c			\
    third_party/ruby/prism/prism.c				\
    third_party/ruby/prism/regexp.c				\
    third_party/ruby/prism/serialize.c				\
    third_party/ruby/prism/static_literals.c			\
    third_party/ruby/prism/token_type.c				\
    third_party/ruby/prism/util/pm_buffer.c			\
    third_party/ruby/prism/util/pm_char.c			\
    third_party/ruby/prism/util/pm_constant_pool.c		\
    third_party/ruby/prism/util/pm_integer.c			\
    third_party/ruby/prism/util/pm_list.c			\
    third_party/ruby/prism/util/pm_memchr.c			\
    third_party/ruby/prism/util/pm_newline_list.c		\
    third_party/ruby/prism/util/pm_string.c			\
    third_party/ruby/prism/util/pm_strncasecmp.c		\
    third_party/ruby/prism/util/pm_strpbrk.c			\
    third_party/ruby/missing/setproctitle.c			\
    third_party/ruby/addr2line.c

# Modular extension system:
# - Extensions are built as separate .a libraries (ext/date/date.a, ext/psych/psych.a, etc.)
# - extinit.c uses weak symbols to only initialize extensions that are actually linked
# - To add/remove extensions: edit THIRD_PARTY_RUBY_EXTENSIONS list below and ext/extinit.c
# - Modifying an extension only rebuilds that .a + relink (~5 seconds)
# - Adding/removing an extension rebuilds extinit.o + relink (~5 seconds)

# Assembly files
THIRD_PARTY_RUBY_A_SRCS_S =					\
    third_party/ruby/coroutine/amd64/Context.S

THIRD_PARTY_RUBY_A_SRCS =					\
    $(THIRD_PARTY_RUBY_A_SRCS_C)				\
    $(THIRD_PARTY_RUBY_A_SRCS_S)

THIRD_PARTY_RUBY_A_OBJS =					\
    $(THIRD_PARTY_RUBY_A_SRCS_C:%.c=o/$(MODE)/%.o)		\
    $(THIRD_PARTY_RUBY_A_SRCS_S:%.S=o/$(MODE)/%.o)

THIRD_PARTY_RUBY_A_DIRECTDEPS =					\
    LIBC_CALLS							\
    LIBC_DLOPEN							\
    LIBC_FMT							\
    LIBC_INTRIN							\
    LIBC_LOG							\
    LIBC_MEM							\
    LIBC_NEXGEN32E						\
    LIBC_PROC							\
    LIBC_RUNTIME						\
    LIBC_SOCK							\
    LIBC_STDIO							\
    LIBC_STR							\
    LIBC_SYSTEM							\
    LIBC_SYSV							\
    LIBC_THREAD							\
    LIBC_TINYMATH						\
    LIBC_X							\
    NET_HTTP							\
    NET_HTTPS							\
    THIRD_PARTY_COMPILER_RT					\
    THIRD_PARTY_GDTOA						\
    THIRD_PARTY_MUSL						\
    THIRD_PARTY_TZ						\
    THIRD_PARTY_ZLIB					\
    THIRD_PARTY_LIBYAML					\
    THIRD_PARTY_COSMO_PLUGIN

# NOTE: Removed LIBC_NT - it's not a package itself but a directory.
# Windows NT functionality comes through LIBC_CALLS, LIBC_SOCK, etc.

THIRD_PARTY_RUBY_A_DEPS :=					\
    $(call uniq,$(foreach x,$(THIRD_PARTY_RUBY_A_DIRECTDEPS),$($(x))))

$(THIRD_PARTY_RUBY_A):						\
    third_party/ruby/					\
    $(THIRD_PARTY_RUBY_A).pkg				\
    $(THIRD_PARTY_RUBY_A_OBJS)

$(THIRD_PARTY_RUBY_A).pkg:					\
    $(THIRD_PARTY_RUBY_A_OBJS)				\
    $(foreach x,$(THIRD_PARTY_RUBY_A_DIRECTDEPS),$($(x)_A).pkg)

# extinit.c needs EXTSTATIC and SLIM_STATIC defined to match config.h
# This enables static extension initialization for static/slim_static builds,
# and disables it for dynamic builds (which use dmyext.c instead).
o/$(MODE)/third_party/ruby/ext/extinit.o:				\
		third_party/ruby/ext/extinit.c				\
		third_party/ruby/include/ruby/config.h
o/$(MODE)/third_party/ruby/ext/extinit.o: private		\
	CFLAGS +=						\
		-DEXTSTATIC=$(RUBY_EXTSTATIC)			\
		-DSLIM_STATIC=$(RUBY_SLIM_STATIC)
