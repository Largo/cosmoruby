#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘
#
# OVERVIEW
#
#   bigdecimal 4.0.1 ruby gem (native extension), statically linked.
#
# NOTES
#
#   Sources come from the `bigdecimal` rubygem (see README.cosmo).  This is
#   the same version Ruby 4.0.6 bundles under .bundle/gems/bigdecimal-4.0.1,
#   byte for byte; bigdecimal stopped being a *default* gem in Ruby 3.4, so
#   without this extension `require "bigdecimal"` fails outright.  ActiveSupport,
#   ActiveRecord's decimal columns and Rails' JSON encoder all need it.
#
#   No external C library: bigdecimal is self-contained.
#
#   The -D flags below stand in for extconf.rb's probe results:
#
#     HAVE_BUILTIN___BUILTIN_CLZ{,L,LL}  gcc/clang -> yes.  bits.h prefers
#                                        these over the x86 LZCNT intrinsics.
#     HAVE_FLOAT_H / HAVE_MATH_H /       cosmopolitan libc -> yes
#     HAVE_STDBOOL_H / HAVE_STDLIB_H
#     HAVE_RUBY_ATOMIC_H                 ruby >= 3.0 -> yes
#     HAVE_RUBY_INTERNAL_HAS_BUILTIN_H   ruby >= 3.0 -> yes
#     HAVE_RUBY_INTERNAL_STATIC_ASSERT_H ruby >= 3.0 -> yes
#     HAVE_RB_COMPLEX_REAL / _IMAG       include/ruby/internal/intern/complex.h
#     HAVE_RB_OPTS_EXCEPTION_P           object.c defines it (not in a public
#                                        header, but it is a global symbol and
#                                        bigdecimal.c declares it itself)
#     HAVE_RB_CATEGORY_WARN              include/ruby/internal/error.h
#     HAVE_CONST_RB_WARN_CATEGORY_DEPRECATED  same header
#
#   Deliberately NOT defined:
#
#     HAVE_X86INTRIN_H / HAVE__LZCNT_U32 / HAVE__LZCNT_U64
#     HAVE_INTRIN_H / HAVE___LZCNT / HAVE__BITSCANREVERSE
#                                        x86-only (and MSVC-only) paths.  This
#                                        tree is also built for aarch64 from
#                                        the same flag set, and bits.h's
#                                        __builtin_clz path is both portable
#                                        and what upstream falls back to.
#
#   HAVE_UINT128_T and HAVE_INT64_T come from third_party/ruby/include/ruby
#   /config.h, which bigdecimal.h pulls in via <ruby/ruby.h>; they are not
#   repeated here.
#
#   missing/dtoa.c is #included by missing.c (upstream does the same), so it
#   is a header dependency here, not a source.

PKGS += THIRD_PARTY_RUBY_EXT_BIGDECIMAL

THIRD_PARTY_RUBY_EXT_BIGDECIMAL_A =					\
	o/$(MODE)/third_party/ruby/ext/bigdecimal/bigdecimal.a
THIRD_PARTY_RUBY_EXT_BIGDECIMAL_FILES :=				\
	$(wildcard third_party/ruby/ext/bigdecimal/*)			\
	$(wildcard third_party/ruby/ext/bigdecimal/missing/*)
THIRD_PARTY_RUBY_EXT_BIGDECIMAL_HDRS =					\
	$(filter %.h,$(THIRD_PARTY_RUBY_EXT_BIGDECIMAL_FILES))		\
	third_party/ruby/ext/bigdecimal/missing/dtoa.c

THIRD_PARTY_RUBY_EXT_BIGDECIMAL_SRCS =					\
	third_party/ruby/ext/bigdecimal/bigdecimal.c			\
	third_party/ruby/ext/bigdecimal/missing.c

THIRD_PARTY_RUBY_EXT_BIGDECIMAL_OBJS =					\
	$(THIRD_PARTY_RUBY_EXT_BIGDECIMAL_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_BIGDECIMAL_A):					\
		$(THIRD_PARTY_RUBY_EXT_BIGDECIMAL_OBJS)

o/$(MODE)/third_party/ruby/ext/bigdecimal/%.o: private			\
	CFLAGS +=							\
		-Ithird_party/ruby/include				\
		-Ithird_party/ruby					\
		-Ithird_party/ruby/ext/bigdecimal			\
		-DRUBY_EXPORT						\
		-DRUBY_COSMOPOLITAN					\
		-DHAVE_BUILTIN___BUILTIN_CLZ				\
		-DHAVE_BUILTIN___BUILTIN_CLZL				\
		-DHAVE_BUILTIN___BUILTIN_CLZLL				\
		-DHAVE_FLOAT_H						\
		-DHAVE_MATH_H						\
		-DHAVE_STDBOOL_H					\
		-DHAVE_STDLIB_H						\
		-DHAVE_RUBY_ATOMIC_H					\
		-DHAVE_RUBY_INTERNAL_HAS_BUILTIN_H			\
		-DHAVE_RUBY_INTERNAL_STATIC_ASSERT_H			\
		-DHAVE_RB_COMPLEX_REAL					\
		-DHAVE_RB_COMPLEX_IMAG					\
		-DHAVE_RB_OPTS_EXCEPTION_P				\
		-DHAVE_RB_CATEGORY_WARN					\
		-DHAVE_CONST_RB_WARN_CATEGORY_DEPRECATED

$(THIRD_PARTY_RUBY_EXT_BIGDECIMAL_OBJS):				\
	$(THIRD_PARTY_RUBY_EXT_BIGDECIMAL_HDRS)				\
	third_party/ruby/ext/bigdecimal/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/bigdecimal
o/$(MODE)/third_party/ruby/ext/bigdecimal: $(THIRD_PARTY_RUBY_EXT_BIGDECIMAL_A)
