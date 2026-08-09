#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘
#
# OVERVIEW
#
#   libxml2 2.13.9 — the GNOME XML/HTML parser and toolkit
#
# NOTES
#
#   Cosmopolitan never runs ./configure, so config.h and
#   include/libxml/xmlversion.h are pre-generated and committed. The
#   feature set they encode is documented in PORTING-NOTES.md; the
#   short version is "everything nokogiri uses, nothing that needs a
#   network or a shared object":
#
#     ON   tree output push reader pattern writer sax1 valid html
#          legacy c14n catalog xpath xptr xinclude regexp automata
#          schemas (XSD + RelaxNG) unicode threads iconv iso8859x zlib
#     OFF  http ftp modules(dlopen) icu lzma python readline history
#          debug schematron thread-alloc tls xptr-locs
#
#   zlib comes from cosmopolitan's own third_party/zlib(+gz), not from
#   a second vendored copy. iconv is cosmopolitan's musl-derived
#   implementation in third_party/musl/iconv.c.

PKGS += THIRD_PARTY_LIBXML2

THIRD_PARTY_LIBXML2_ARTIFACTS += THIRD_PARTY_LIBXML2_A
THIRD_PARTY_LIBXML2 = $(THIRD_PARTY_LIBXML2_A_DEPS) $(THIRD_PARTY_LIBXML2_A)
THIRD_PARTY_LIBXML2_A = o/$(MODE)/third_party/libxml2/libxml2.a

THIRD_PARTY_LIBXML2_A_FILES :=					\
	$(wildcard third_party/libxml2/*.c)			\
	$(wildcard third_party/libxml2/*.h)			\
	$(wildcard third_party/libxml2/include/libxml/*.h)	\
	$(wildcard third_party/libxml2/include/private/*.h)

THIRD_PARTY_LIBXML2_A_HDRS = $(filter %.h,$(THIRD_PARTY_LIBXML2_A_FILES))
THIRD_PARTY_LIBXML2_A_SRCS = $(filter %.c,$(THIRD_PARTY_LIBXML2_A_FILES))
THIRD_PARTY_LIBXML2_A_OBJS = $(THIRD_PARTY_LIBXML2_A_SRCS:%.c=o/$(MODE)/%.o)

# NOTE: no o/$(MODE)/%.h.ok strict-header checks here. libxml2's public
# headers only compile after -Ithird_party/libxml2/include, and its
# include/private/*.h headers are documented as "include libxml.h
# first" internals, so a standalone compile of each header is not a
# meaningful test for this package.
THIRD_PARTY_LIBXML2_A_CHECKS =					\
	$(THIRD_PARTY_LIBXML2_A).pkg

THIRD_PARTY_LIBXML2_A_DIRECTDEPS =				\
	LIBC_CALLS						\
	LIBC_FMT						\
	LIBC_INTRIN						\
	LIBC_MEM						\
	LIBC_NEXGEN32E						\
	LIBC_RUNTIME						\
	LIBC_STDIO						\
	LIBC_STR						\
	LIBC_SYSV						\
	LIBC_SYSV_CALLS						\
	LIBC_THREAD						\
	LIBC_TINYMATH						\
	THIRD_PARTY_COMPILER_RT					\
	THIRD_PARTY_MUSL					\
	THIRD_PARTY_TZ						\
	THIRD_PARTY_ZLIB					\
	THIRD_PARTY_ZLIB_GZ

THIRD_PARTY_LIBXML2_A_DEPS :=					\
	$(call uniq,$(foreach x,$(THIRD_PARTY_LIBXML2_A_DIRECTDEPS),$($(x))))

$(THIRD_PARTY_LIBXML2_A):					\
		third_party/libxml2/				\
		$(THIRD_PARTY_LIBXML2_A).pkg			\
		$(THIRD_PARTY_LIBXML2_A_OBJS)

$(THIRD_PARTY_LIBXML2_A).pkg:					\
		$(THIRD_PARTY_LIBXML2_A_OBJS)			\
		$(foreach x,$(THIRD_PARTY_LIBXML2_A_DIRECTDEPS),$($(x)_A).pkg)

# Consumers (libxslt, ruby's nokogiri ext, the tests) need these too.
THIRD_PARTY_LIBXML2_CFLAGS =					\
	-DHAVE_CONFIG_H						\
	-D_REENTRANT						\
	-Ithird_party/libxml2					\
	-Ithird_party/libxml2/include				\
	-Ithird_party/zlib

$(THIRD_PARTY_LIBXML2_A_OBJS): private				\
		CFLAGS +=					\
			$(THIRD_PARTY_LIBXML2_CFLAGS)		\
			-ffunction-sections			\
			-fdata-sections				\

THIRD_PARTY_LIBXML2_LIBS = $(foreach x,$(THIRD_PARTY_LIBXML2_ARTIFACTS),$($(x)))
THIRD_PARTY_LIBXML2_SRCS = $(foreach x,$(THIRD_PARTY_LIBXML2_ARTIFACTS),$($(x)_SRCS))
THIRD_PARTY_LIBXML2_HDRS = $(foreach x,$(THIRD_PARTY_LIBXML2_ARTIFACTS),$($(x)_HDRS))
THIRD_PARTY_LIBXML2_CHECKS = $(foreach x,$(THIRD_PARTY_LIBXML2_ARTIFACTS),$($(x)_CHECKS))
THIRD_PARTY_LIBXML2_OBJS = $(foreach x,$(THIRD_PARTY_LIBXML2_ARTIFACTS),$($(x)_OBJS))
$(THIRD_PARTY_LIBXML2_OBJS): third_party/libxml2/BUILD.mk

.PHONY: o/$(MODE)/third_party/libxml2
o/$(MODE)/third_party/libxml2:					\
		$(THIRD_PARTY_LIBXML2_A)			\
		$(THIRD_PARTY_LIBXML2_CHECKS)
