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
include third_party/ruby/ext/pathname/BUILD.mk
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
	THIRD_PARTY_RUBY_EXT_PATHNAME			\
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
	THIRD_PARTY_RUBY_EXT_STRINGIO			\
	THIRD_PARTY_RUBY_EXT_PATHNAME
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
	third_party/ruby/builtin_binary.inc\
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
	third_party/ruby/rjit.h\
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
	third_party/ruby/enc/unicode/15.0.0/casefold.h\
	third_party/ruby/enc/unicode/15.0.0/name2ctype.h\
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
	third_party/ruby/missing/dladdr.h\
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
	ruby_shims/third_party+ruby+include+ruby.h\
	ruby_shims/debug_counter.h\
	ruby_shims/id.h\
	ruby_shims/internal.h\
	ruby_shims/internal+array.h\
	ruby_shims/internal+compar.h\
	ruby_shims/internal+enum.h\
	ruby_shims/internal+gc.h\
	ruby_shims/internal+hash.h\
	ruby_shims/internal+numeric.h\
	ruby_shims/internal+object.h\
	ruby_shims/internal+proc.h\
	ruby_shims/internal+rational.h\
	ruby_shims/internal+vm.h\
	ruby_shims/probes.h\
	ruby_shims/ruby+encoding.h\
	ruby_shims/ruby+st.h\
	ruby_shims/ruby+util.h\
	ruby_shims/vm_core.h\
	ruby_shims/builtin.h\
	ruby_shims/ruby_assert.h\
	ruby_shims/array.rbinc\
	ruby_shims/internal+ruby_parser.h\
	ruby_shims/internal+symbol.h\
	ruby_shims/internal+warnings.h\
	ruby_shims/iseq.h\
	ruby_shims/node.h\
	ruby_shims/ruby.h\
	ruby_shims/ast.rbinc\
	ruby_shims/ruby+internal+config.h\
	ruby_shims/internal+bignum.h\
	ruby_shims/internal+complex.h\
	ruby_shims/internal+sanitizers.h\
	ruby_shims/internal+variable.h\
	ruby_shims/ruby+thread.h\
	ruby_shims/builtin_binary.inc\
	ruby_shims/mini_builtin.c\
	ruby_shims/constant.h\
	ruby_shims/id_table.h\
	ruby_shims/internal+class.h\
	ruby_shims/internal+eval.h\
	ruby_shims/internal+string.h\
	ruby_shims/yjit.h\
	ruby_shims/internal+error.h\
	ruby_shims/ruby+ruby.h\
	ruby_shims/encindex.h\
	ruby_shims/internal+compile.h\
	ruby_shims/internal+encoding.h\
	ruby_shims/internal+io.h\
	ruby_shims/internal+re.h\
	ruby_shims/internal+thread.h\
	ruby_shims/ruby+ractor.h\
	ruby_shims/ruby+re.h\
	ruby_shims/vm_callinfo.h\
	ruby_shims/vm_debug.h\
	ruby_shims/insns.inc\
	ruby_shims/insns_info.inc\
	ruby_shims/optinsn.inc\
	ruby_shims/optunifs.inc\
	ruby_shims/prism_compile.c\
	ruby_shims/internal+math.h\
	ruby_shims/eval_intern.h\
	ruby_shims/internal+cont.h\
	ruby_shims/ruby+fiber+scheduler.h\
	ruby_shims/rjit.h\
	ruby_shims/vm_sync.h\
	ruby_shims/ractor_core.h\
	ruby_shims/internal+signal.h\
	ruby_shims/ruby+io.h\
	ruby_shims/symbol.h\
	ruby_shims/ruby+thread_native.h\
	ruby_shims/win32+dir.h\
	ruby_shims/internal+dir.h\
	ruby_shims/internal+file.h\
	ruby_shims/internal+imemo.h\
	ruby_shims/dir.rbinc\
	ruby_shims/dln.h\
	ruby_shims/internal+compilers.h\
	ruby_shims/missing+file.h\
	ruby_shims/ruby+internal+stdbool.h\
	ruby_shims/third_party+ruby+include+ruby+ruby.h\
	ruby_shims/internal+enc.h\
	ruby_shims/internal+inits.h\
	ruby_shims/internal+load.h\
	ruby_shims/regenc.h\
	ruby_shims/verconf.h\
	ruby_shims/version.h\
	ruby_shims/internal+enumerator.h\
	ruby_shims/internal+range.h\
	ruby_shims/internal+process.h\
	ruby_shims/known_errors.inc\
	ruby_shims/warning.rbinc\
	ruby_shims/probes_helper.h\
	ruby_shims/ruby+vm.h\
	ruby_shims/eval_error.c\
	ruby_shims/eval_jump.c\
	ruby_shims/win32+file.h\
	ruby_shims/wasm+setjmp.h\
	ruby_shims/wasm+machine.h\
	ruby_shims/darray.h\
	ruby_shims/gc+gc.h\
	ruby_shims/internal+struct.h\
	ruby_shims/regint.h\
	ruby_shims/ruby+debug.h\
	ruby_shims/ruby_atomic.h\
	ruby_shims/shape.h\
	ruby_shims/gc+default+default.c\
	ruby_shims/gc.rbinc\
	ruby_shims/missing+crt_externs.h\
	ruby_shims/internal+basic_operators.h\
	ruby_shims/internal+st.h\
	ruby_shims/internal+time.h\
	ruby_shims/hash.rbinc\
	ruby_shims/prelude.rbinc\
	ruby_shims/ruby+io+buffer.h\
	ruby_shims/ccan+list+list.h\
	ruby_shims/internal+transcode.h\
	ruby_shims/ruby+missing.h\
	ruby_shims/io.rbinc\
	ruby_shims/internal+bits.h\
	ruby_shims/internal+util.h\
	ruby_shims/ruby+internal+attr+nonstring.h\
	ruby_shims/marshal.rbinc\
	ruby_shims/ruby+memory_view.h\
	ruby_shims/rubyparser.h\
	ruby_shims/node_name.inc\
	ruby_shims/numeric.rbinc\
	ruby_shims/variable.h\
	ruby_shims/ruby+assert.h\
	ruby_shims/kernel.rbinc\
	ruby_shims/nilclass.rbinc\
	ruby_shims/pack.rbinc\
	ruby_shims/parser_node.h\
	ruby_shims/universal_parser.c\
	ruby_shims/internal+parse.h\
	ruby_shims/ruby+regex.h\
	ruby_shims/parser_st.h\
	ruby_shims/ripper_init.h\
	ruby_shims/parse.h\
	ruby_shims/eventids1.h\
	ruby_shims/eventids2.h\
	ruby_shims/lex.c\
	ruby_shims/parser_bits.h\
	ruby_shims/method.h\
	ruby_shims/hrtime.h\
	ruby_shims/internal+ractor.h\
	ruby_shims/ractor.rbinc\
	ruby_shims/internal+random.h\
	ruby_shims/ruby+random.h\
	ruby_shims/missing+mt19937.c\
	ruby_shims/siphash.c\
	ruby_shims/regparse.h\
	ruby_shims/st.h\
	ruby_shims/internal+cmdlineopt.h\
	ruby_shims/internal+loadpath.h\
	ruby_shims/internal+missing.h\
	ruby_shims/ruby+version.h\
	ruby_shims/ruby+internal+error.h\
	ruby_shims/vsnprintf.c\
	ruby_shims/timev.h\
	ruby_shims/missing+crypt.h\
	ruby_shims/ruby+atomic.h\
	ruby_shims/id.c\
	ruby_shims/id_table.c\
	ruby_shims/symbol.rbinc\
	ruby_shims/thread_sync.c\
	ruby_shims/timezoneapi.h\
	ruby_shims/timev.rbinc\
	ruby_shims/transcode_data.h\
	ruby_shims/missing+dtoa.c\
	ruby_shims/vm_exec.h\
	ruby_shims/vm_insnhelper.h\
	ruby_shims/vm_insnhelper.c\
	ruby_shims/vm_exec.c\
	ruby_shims/vm_method.c\
	ruby_shims/vm_eval.c\
	ruby_shims/yjit_hook.rbinc\
	ruby_shims/vm_call_iseq_optimized.inc\
	ruby_shims/addr2line.h\
	ruby_shims/missing+procstat_vm.c\
	ruby_shims/trace_point.rbinc\
	ruby_shims/encdb.h\
	ruby_shims/casefold.h\
	ruby_shims/name2ctype.h\
	ruby_shims/iso_8859.h\
	ruby_shims/transdb.h\
	ruby_shims/prism+extension.h\
	ruby_shims/prism+diagnostic.h\
	ruby_shims/prism+encoding.h\
	ruby_shims/prism+node.h\
	ruby_shims/prism+options.h\
	ruby_shims/prism+pack.h\
	ruby_shims/prism+prettyprint.h\
	ruby_shims/prism.h\
	ruby_shims/prism+regexp.h\
	ruby_shims/prism+static_literals.h\
	ruby_shims/prism+ast.h\
	ruby_shims/prism+util+pm_buffer.h\
	ruby_shims/prism+util+pm_char.h\
	ruby_shims/prism+util+pm_constant_pool.h\
	ruby_shims/prism+util+pm_integer.h\
	ruby_shims/prism+util+pm_list.h\
	ruby_shims/prism+util+pm_memchr.h\
	ruby_shims/prism+util+pm_newline_list.h\
	ruby_shims/prism+util+pm_string.h\
	ruby_shims/prism+util+pm_strncasecmp.h\
	ruby_shims/prism+util+pm_strpbrk.h\
	ruby_shims/crt_externs.h\
	ruby_shims/dladdr.h\
	ruby_shims/ruby+defines.h\
	ruby_shims/missing+dladdr.h\
	ruby_shims/internal+static_assert.h\
	ruby_shims/win32_vk.inc\
	ruby_shims/ruby_cosmo_main.h\
	ruby_shims/internal+fixnum.h\
	ruby_shims/ruby+intern.h\
	ruby_shims/internal+serial.h\
	ruby_shims/probes.dmyh\
	ruby_shims/ruby+internal+encoding+coderange.h\
	ruby_shims/ruby+internal+encoding+ctype.h\
	ruby_shims/ruby+internal+encoding+encoding.h\
	ruby_shims/ruby+internal+encoding+pathname.h\
	ruby_shims/ruby+internal+encoding+re.h\
	ruby_shims/ruby+internal+encoding+sprintf.h\
	ruby_shims/ruby+internal+encoding+string.h\
	ruby_shims/ruby+internal+encoding+symbol.h\
	ruby_shims/ruby+internal+encoding+transcode.h\
	ruby_shims/ruby+internal+attr+noalias.h\
	ruby_shims/ruby+internal+attr+nodiscard.h\
	ruby_shims/ruby+internal+attr+nonnull.h\
	ruby_shims/ruby+internal+attr+restrict.h\
	ruby_shims/ruby+internal+attr+returns_nonnull.h\
	ruby_shims/ruby+internal+dllexport.h\
	ruby_shims/vm_opts.h\
	ruby_shims/ruby+internal+warning_push.h\
	ruby_shims/prism_compile.h\
	ruby_shims/ruby+backward+2+attributes.h\
	ruby_shims/ruby+config.h\
	ruby_shims/ruby+internal+compiler_since.h\
	ruby_shims/ruby+internal+value.h\
	ruby_shims/ruby+internal+intern+thread.h\
	ruby_shims/internal+dllexport.h\
	ruby_shims/internal+fl_type.h\
	ruby_shims/internal+special_consts.h\
	ruby_shims/internal+stdbool.h\
	ruby_shims/internal+value.h\
	ruby_shims/ruby+onigmo.h\
	ruby_shims/ruby+internal+core+rmatch.h\
	ruby_shims/ruby+internal+arithmetic.h\
	ruby_shims/ruby+internal+attr+const.h\
	ruby_shims/ruby+internal+attr+packed_struct.h\
	ruby_shims/ruby+internal+attr+pure.h\
	ruby_shims/ruby+internal+attr+noreturn.h\
	ruby_shims/ruby+internal+has+attribute.h\
	ruby_shims/ruby+internal+has+builtin.h\
	ruby_shims/ruby+internal+has+c_attribute.h\
	ruby_shims/ruby+internal+has+declspec_attribute.h\
	ruby_shims/ruby+internal+has+extension.h\
	ruby_shims/ruby+internal+has+feature.h\
	ruby_shims/ruby+internal+has+warning.h\
	ruby_shims/ruby+backward+2+gcc_version_since.h\
	ruby_shims/onigmo.h\
	ruby_shims/ruby+internal+abi.h\
	ruby_shims/revision.h\
	ruby_shims/ruby+win32.h\
	ruby_shims/ruby+internal+attr+deprecated.h\
	ruby_shims/ruby+internal+event.h\
	ruby_shims/gc+gc_impl.h\
	ruby_shims/include+ruby+st.h\
	ruby_shims/third_party+ruby+ccan+str+str.h\
	ruby_shims/third_party+ruby+ccan+container_of+container_of.h\
	ruby_shims/third_party+ruby+ccan+check_type+check_type.h\
	ruby_shims/ruby+internal+attr+format.h\
	ruby_shims/ruby+internal+core+rtypeddata.h\
	ruby_shims/parser_value.h\
	ruby_shims/ruby+internal+assume.h\
	ruby_shims/ruby+internal+attr+cold.h\
	ruby_shims/ruby+internal+cast.h\
	ruby_shims/ruby+backward+2+assume.h\
	ruby_shims/ruby+backward+2+inttypes.h\
	ruby_shims/ruby+oniguruma.h\
	ruby_shims/oniguruma.h\
	ruby_shims/ruby+backward+2+long_long.h\
	ruby_shims/siphash.h\
	ruby_shims/ruby+backward+2+limits.h\
	ruby_shims/ruby+internal+attr+artificial.h\
	ruby_shims/ruby+internal+static_assert.h\
	ruby_shims/thread_sync.rbinc\
	ruby_shims/vm_args.c\
	ruby_shims/vmtc.inc\
	ruby_shims/vm.inc\
	ruby_shims/prism+defines.h\
	ruby_shims/prism+parser.h\
	ruby_shims/prism+version.h\
	ruby_shims/ruby+internal+xmalloc.h\
	ruby_shims/ruby+backward+2+bool.h\
	ruby_shims/ruby+backward+2+stdalign.h\
	ruby_shims/ruby+backward+2+stdarg.h\
	ruby_shims/ruby+internal+dosish.h\
	ruby_shims/ruby+internal+intern+array.h\
	ruby_shims/ruby+internal+intern+bignum.h\
	ruby_shims/ruby+internal+intern+class.h\
	ruby_shims/ruby+internal+intern+compar.h\
	ruby_shims/ruby+internal+intern+complex.h\
	ruby_shims/ruby+internal+intern+cont.h\
	ruby_shims/ruby+internal+intern+dir.h\
	ruby_shims/ruby+internal+intern+enum.h\
	ruby_shims/ruby+internal+intern+enumerator.h\
	ruby_shims/ruby+internal+intern+error.h\
	ruby_shims/ruby+internal+intern+eval.h\
	ruby_shims/ruby+internal+intern+file.h\
	ruby_shims/ruby+internal+intern+hash.h\
	ruby_shims/ruby+internal+intern+io.h\
	ruby_shims/ruby+internal+intern+load.h\
	ruby_shims/ruby+internal+intern+marshal.h\
	ruby_shims/ruby+internal+intern+numeric.h\
	ruby_shims/ruby+internal+intern+object.h\
	ruby_shims/ruby+internal+intern+parse.h\
	ruby_shims/ruby+internal+intern+proc.h\
	ruby_shims/ruby+internal+intern+process.h\
	ruby_shims/ruby+internal+intern+random.h\
	ruby_shims/ruby+internal+intern+range.h\
	ruby_shims/ruby+internal+intern+rational.h\
	ruby_shims/ruby+internal+intern+re.h\
	ruby_shims/ruby+internal+intern+ruby.h\
	ruby_shims/ruby+internal+intern+select.h\
	ruby_shims/ruby+internal+intern+signal.h\
	ruby_shims/ruby+internal+intern+sprintf.h\
	ruby_shims/ruby+internal+intern+string.h\
	ruby_shims/ruby+internal+intern+struct.h\
	ruby_shims/ruby+internal+intern+time.h\
	ruby_shims/ruby+internal+intern+variable.h\
	ruby_shims/ruby+internal+intern+vm.h\
	ruby_shims/ruby+internal+fl_type.h\
	ruby_shims/ruby+internal+core+rbasic.h\
	ruby_shims/ruby+internal+has+cpp_attribute.h\
	ruby_shims/ruby+internal+compiler_is.h\
	ruby_shims/prism+prism.h\
	ruby_shims/ruby+internal+attr+alloc_size.h\
	ruby_shims/ruby+internal+attr+error.h\
	ruby_shims/ruby+internal+attr+forceinline.h\
	ruby_shims/ruby+internal+attr+maybe_unused.h\
	ruby_shims/ruby+internal+attr+noinline.h\
	ruby_shims/ruby+internal+attr+warning.h\
	ruby_shims/errno_wrapper.h\
	ruby_shims/ruby+internal+attr+flag_enum.h\
	ruby_shims/ruby+internal+special_consts.h\
	ruby_shims/ruby+internal+value_type.h\
	ruby_shims/ruby+internal+attr+constexpr.h\
	ruby_shims/ruby+internal+attr+enum_extensibility.h\
	ruby_shims/ruby+internal+arithmetic+char.h\
	ruby_shims/ruby+internal+arithmetic+double.h\
	ruby_shims/ruby+internal+arithmetic+fixnum.h\
	ruby_shims/ruby+internal+arithmetic+gid_t.h\
	ruby_shims/ruby+internal+arithmetic+int.h\
	ruby_shims/ruby+internal+arithmetic+intptr_t.h\
	ruby_shims/ruby+internal+arithmetic+long.h\
	ruby_shims/ruby+internal+arithmetic+long_long.h\
	ruby_shims/ruby+internal+arithmetic+mode_t.h\
	ruby_shims/ruby+internal+arithmetic+off_t.h\
	ruby_shims/ruby+internal+arithmetic+pid_t.h\
	ruby_shims/ruby+internal+arithmetic+short.h\
	ruby_shims/ruby+internal+arithmetic+size_t.h\
	ruby_shims/ruby+internal+arithmetic+st_data_t.h\
	ruby_shims/ruby+internal+arithmetic+uid_t.h\
	ruby_shims/ruby+internal+core+rdata.h\
	ruby_shims/prism_xallocator.h\
	ruby_shims/ruby+internal+attr+noexcept.h\
	ruby_shims/ruby+internal+stdalign.h\
	ruby_shims/ruby+internal+iterator.h\
	ruby_shims/ruby+internal+symbol.h\
	ruby_shims/ruby+internal+intern+select+largesize.h\
	ruby_shims/ruby+internal+intern+select+win32.h\
	ruby_shims/ruby+internal+intern+select+posix.h\
	ruby_shims/ruby+internal+constant_p.h\
	ruby_shims/ruby+internal+variable.h\
	ruby_shims/ruby+internal+compiler_is+apple.h\
	ruby_shims/ruby+internal+compiler_is+clang.h\
	ruby_shims/ruby+internal+compiler_is+gcc.h\
	ruby_shims/ruby+internal+compiler_is+intel.h\
	ruby_shims/ruby+internal+compiler_is+msvc.h\
	ruby_shims/ruby+internal+compiler_is+sunpro.h\
	ruby_shims/ruby+internal+core+rstring.h
# Ruby core source files: VM, encodings, transcoders, prism parser, and portability shims
# NOTE: Extensions (ripper, io/*, pathname, stringio, monitor, socket) are built separately via BUILD.mk files
# Note: Some .c files are not listed here because they're included by other files (e.g., constdefs.c) or provided by Cosmopolitan (e.g., getaddrinfo.c)
THIRD_PARTY_RUBY_A_SRCS_C =					\
    third_party/ruby/array.c					\
    third_party/ruby/ast.c					\
    third_party/ruby/bignum.c					\
    third_party/ruby/builtin.c					\
    third_party/ruby/class.c					\
    third_party/ruby/compar.c					\
    third_party/ruby/compile.c					\
    third_party/ruby/complex.c					\
    third_party/ruby/cont.c					\
    third_party/ruby/debug.c					\
    third_party/ruby/debug_counter.c				\
    third_party/ruby/dir.c					\
    third_party/ruby/ext/extinit.c				\
    third_party/ruby/dln.c					\
    third_party/ruby/dln_cosmo.c				\
    third_party/ruby/encinit.c					\
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
    third_party/ruby/enc/encdb.c				\
    third_party/ruby/enc/unicode.c				\
    third_party/ruby/enc/us_ascii.c				\
    third_party/ruby/enc/utf_8.c				\
    third_party/ruby/enc/utf_16be.c				\
    third_party/ruby/enc/utf_16le.c				\
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
    third_party/ruby/missing/dladdr.c				\
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
