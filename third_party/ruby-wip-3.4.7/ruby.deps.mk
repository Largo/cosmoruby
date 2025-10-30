#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

# Modular Ruby extensions - each has its own BUILD.mk
# To enable/disable extensions, comment/uncomment these includes
# and update ext/extinit.c accordingly
include third_party/ruby/ext/date/BUILD.mk
include third_party/ruby/ext/digest/BUILD.mk
include third_party/ruby/ext/etc/BUILD.mk
include third_party/ruby/ext/io/nonblock/BUILD.mk
include third_party/ruby/ext/json/BUILD.mk
include third_party/ruby/ext/mbedtls/BUILD.mk
include third_party/ruby/ext/monitor/BUILD.mk
include third_party/ruby/ext/pathname/BUILD.mk
include third_party/ruby/ext/psych/BUILD.mk
include third_party/ruby/ext/socket/BUILD.mk
include third_party/ruby/ext/stringio/BUILD.mk
include third_party/ruby/ext/zlib/BUILD.mk

PKGS += THIRD_PARTY_RUBY

# List of enabled extensions (used for dependencies)
THIRD_PARTY_RUBY_EXTENSIONS =				\
	THIRD_PARTY_RUBY_EXT_DATE			\
	THIRD_PARTY_RUBY_EXT_DIGEST			\
	THIRD_PARTY_RUBY_EXT_ETC			\
	THIRD_PARTY_RUBY_EXT_IO_NONBLOCK		\
	THIRD_PARTY_RUBY_EXT_JSON			\
	THIRD_PARTY_RUBY_EXT_MBEDTLS			\
	THIRD_PARTY_RUBY_EXT_MONITOR			\
	THIRD_PARTY_RUBY_EXT_PATHNAME			\
	THIRD_PARTY_RUBY_EXT_PSYCH			\
	THIRD_PARTY_RUBY_EXT_SOCKET			\
	THIRD_PARTY_RUBY_EXT_STRINGIO			\
	THIRD_PARTY_RUBY_EXT_ZLIB

THIRD_PARTY_RUBY_COMS =						\
    o/$(MODE)/third_party/ruby/miniruby				\
    o/$(MODE)/third_party/ruby/ruby				\
    o/$(MODE)/third_party/ruby/irb

THIRD_PARTY_RUBY_BINS =						\
    $(THIRD_PARTY_RUBY_COMS)					\
    $(THIRD_PARTY_RUBY_COMS:%=%.dbg)

THIRD_PARTY_RUBY_CHECKS =					\
    $(THIRD_PARTY_RUBY_A).pkg					\
    $(THIRD_PARTY_RUBY_HDRS:%=o/$(MODE)/%.ok)			\
    $(THIRD_PARTY_RUBY_INCS:%=o/$(MODE)/%.ok)			\
    o/$(MODE)/third_party/ruby/miniruby.pkg			\
    o/$(MODE)/third_party/ruby/ruby.pkg				\
    o/$(MODE)/third_party/ruby/irb.pkg


################################################################################
# ruby.a

THIRD_PARTY_RUBY =						\
    $(THIRD_PARTY_RUBY_A_DEPS)					\
    $(THIRD_PARTY_RUBY_A)

THIRD_PARTY_RUBY_ARTIFACTS +=					\
    THIRD_PARTY_RUBY_A

THIRD_PARTY_RUBY_A =						\
    o/$(MODE)/third_party/ruby/ruby.a

# Public API headers (full paths for external code to include)
THIRD_PARTY_RUBY_A_HDRS =

# List Ruby core include files (relative paths as they appear in #include directives)
THIRD_PARTY_RUBY_A_INCS =\
    third_party/ruby/debug_counter.h\
    third_party/ruby/id.h\
    third_party/ruby/internal.h\
    internal/array.h\
    internal/compar.h\
    internal/enum.h\
    internal/gc.h\
    internal/hash.h\
    internal/numeric.h\
    internal/object.h\
    internal/proc.h\
    internal/rational.h\
    internal/vm.h\
    third_party/ruby/probes.h\
    ruby/encoding.h\
    ruby/st.h\
    ruby/util.h\
    third_party/ruby/vm_core.h\
    third_party/ruby/builtin.h\
    third_party/ruby/ruby_assert.h\
    third_party/ruby/array.rbinc\
    internal/ruby_parser.h\
    internal/symbol.h\
    internal/warnings.h\
    third_party/ruby/iseq.h\
    third_party/ruby/node.h\
    third_party/ruby/ruby.h\
    third_party/ruby/ast.rbinc\
    ruby/internal/config.h\
    internal/bignum.h\
    internal/complex.h\
    internal/sanitizers.h\
    internal/variable.h\
    ruby/thread.h\
    third_party/ruby/builtin_binary.inc\
    third_party/ruby/mini_builtin.c\
    third_party/ruby/constant.h\
    third_party/ruby/id_table.h\
    internal/class.h\
    internal/eval.h\
    internal/string.h\
    third_party/ruby/yjit.h\
    internal/error.h\
    ruby/ruby.h\
    third_party/ruby/encindex.h\
    internal/compile.h\
    internal/encoding.h\
    internal/io.h\
    internal/re.h\
    internal/thread.h\
    ruby/ractor.h\
    ruby/re.h\
    third_party/ruby/vm_callinfo.h\
    third_party/ruby/vm_debug.h\
    third_party/ruby/insns.inc\
    third_party/ruby/insns_info.inc\
    third_party/ruby/optinsn.inc\
    third_party/ruby/optunifs.inc\
    third_party/ruby/prism_compile.c\
    internal/math.h\
    third_party/ruby/eval_intern.h\
    internal/cont.h\
    ruby/fiber/scheduler.h\
    third_party/ruby/rjit.h\
    third_party/ruby/vm_sync.h\
    third_party/ruby/ractor_core.h\
    internal/signal.h\
    ruby/io.h\
    third_party/ruby/symbol.h\
    ruby/thread_native.h\
    win32/dir.h\
    internal/dir.h\
    internal/file.h\
    internal/imemo.h\
    third_party/ruby/dir.rbinc\
    third_party/ruby/dln.h\
    internal/compilers.h\
    missing/file.h\
    ruby/internal/stdbool.h\
    internal/enc.h\
    internal/inits.h\
    internal/load.h\
    third_party/ruby/regenc.h\
    third_party/ruby/verconf.h\
    third_party/ruby/version.h\
    internal/enumerator.h\
    internal/range.h\
    internal/process.h\
    third_party/ruby/known_errors.inc\
    third_party/ruby/warning.rbinc\
    third_party/ruby/probes_helper.h\
    ruby/vm.h\
    third_party/ruby/eval_error.c\
    third_party/ruby/eval_jump.c\
    win32/file.h\
    wasm/setjmp.h\
    wasm/machine.h\
    third_party/ruby/darray.h\
    gc/gc.h\
    internal/struct.h\
    third_party/ruby/regint.h\
    ruby/debug.h\
    third_party/ruby/ruby_atomic.h\
    third_party/ruby/shape.h\
    gc/default/default.c\
    third_party/ruby/gc.rbinc\
    missing/crt_externs.h\
    internal/basic_operators.h\
    internal/st.h\
    internal/time.h\
    third_party/ruby/hash.rbinc\
    third_party/ruby/prelude.rbinc\
    ruby/io/buffer.h\
    ccan/list/list.h\
    internal/transcode.h\
    ruby/missing.h\
    third_party/ruby/io.rbinc\
    internal/bits.h\
    internal/util.h\
    ruby/internal/attr/nonstring.h\
    third_party/ruby/marshal.rbinc\
    ruby/memory_view.h\
    third_party/ruby/rubyparser.h\
    third_party/ruby/node_name.inc\
    third_party/ruby/numeric.rbinc\
    third_party/ruby/variable.h\
    ruby/assert.h\
    third_party/ruby/kernel.rbinc\
    third_party/ruby/nilclass.rbinc\
    third_party/ruby/pack.rbinc\
    third_party/ruby/parser_node.h\
    third_party/ruby/universal_parser.c\
    internal/parse.h\
    ruby/regex.h\
    third_party/ruby/parser_st.h\
    third_party/ruby/ripper_init.h\
    third_party/ruby/parse.h\
    third_party/ruby/eventids1.h\
    third_party/ruby/eventids2.h\
    third_party/ruby/lex.c\
    third_party/ruby/parser_bits.h\
    third_party/ruby/method.h\
    third_party/ruby/hrtime.h\
    internal/ractor.h\
    third_party/ruby/ractor.rbinc\
    internal/random.h\
    ruby/random.h\
    missing/mt19937.c\
    third_party/ruby/siphash.c\
    third_party/ruby/regparse.h\
    third_party/ruby/st.h\
    internal/cmdlineopt.h\
    internal/loadpath.h\
    internal/missing.h\
    ruby/version.h\
    ruby/internal/error.h\
    third_party/ruby/vsnprintf.c\
    third_party/ruby/timev.h\
    missing/crypt.h\
    ruby/atomic.h\
    third_party/ruby/id.c\
    third_party/ruby/id_table.c\
    third_party/ruby/symbol.rbinc\
    third_party/ruby/thread_sync.c\
    third_party/ruby/timezoneapi.h\
    third_party/ruby/timev.rbinc\
    third_party/ruby/transcode_data.h\
    missing/dtoa.c\
    third_party/ruby/vm_exec.h\
    third_party/ruby/vm_insnhelper.h\
    third_party/ruby/vm_insnhelper.c\
    third_party/ruby/vm_exec.c\
    third_party/ruby/vm_method.c\
    third_party/ruby/vm_eval.c\
    third_party/ruby/yjit_hook.rbinc\
    third_party/ruby/vm_call_iseq_optimized.inc\
    third_party/ruby/addr2line.h\
    missing/procstat_vm.c\
    third_party/ruby/trace_point.rbinc\

# Ruby core source files: VM, encodings, transcoders, prism parser, extensions (ripper, io/*, pathname, stringio, monitor, socket), and portability shims
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
    third_party/ruby/addr2line.c				\
    third_party/ruby/ext/ripper/ripper.c			\
    third_party/ruby/ext/ripper/ripper_init.c			\
    third_party/ruby/ext/ripper/eventids1.c			\
    third_party/ruby/ext/ripper/eventids2.c			\
    third_party/ruby/ext/ripper/eventids2table.c		\
    third_party/ruby/ext/io/console/console.c			\
    third_party/ruby/ext/io/wait/wait.c

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
    THIRD_PARTY_LIBYAML

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

