#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘
#
# OVERVIEW
#
#   libxslt 1.1.43 + libexslt 0.8.24 — XSLT 1.0 and EXSLT for libxml2
#
# NOTES
#
#   One archive holds both libxslt and libexslt, because nothing here
#   ever wants one without the other. Call exsltRegisterAll() to get
#   the EXSLT namespaces.
#
#   Pre-generated (cosmopolitan never runs ./configure):
#     config.h, libxslt/xsltconfig.h, libexslt/exsltconfig.h
#   with WITH_XSLT_DEBUG=0, WITH_DEBUGGER=0, WITH_PROFILER=0,
#   WITH_MODULES=0 (no dlopen plugins) and EXSLT_CRYPTO_ENABLED=0
#   (no libgcrypt). See PORTING-NOTES.md.

PKGS += THIRD_PARTY_LIBXSLT

THIRD_PARTY_LIBXSLT_ARTIFACTS += THIRD_PARTY_LIBXSLT_A
THIRD_PARTY_LIBXSLT = $(THIRD_PARTY_LIBXSLT_A_DEPS) $(THIRD_PARTY_LIBXSLT_A)
THIRD_PARTY_LIBXSLT_A = o/$(MODE)/third_party/libxslt/libxslt.a

THIRD_PARTY_LIBXSLT_A_FILES :=					\
	$(wildcard third_party/libxslt/libxslt/*.c)		\
	$(wildcard third_party/libxslt/libxslt/*.h)		\
	$(wildcard third_party/libxslt/libexslt/*.c)		\
	$(wildcard third_party/libxslt/libexslt/*.h)		\
	third_party/libxslt/config.h

THIRD_PARTY_LIBXSLT_A_HDRS = $(filter %.h,$(THIRD_PARTY_LIBXSLT_A_FILES))
THIRD_PARTY_LIBXSLT_A_SRCS = $(filter %.c,$(THIRD_PARTY_LIBXSLT_A_FILES))
THIRD_PARTY_LIBXSLT_A_OBJS = $(THIRD_PARTY_LIBXSLT_A_SRCS:%.c=o/$(MODE)/%.o)

# See the note in third_party/libxml2/BUILD.mk: these headers are only
# compilable with the package's own -I flags, so no %.h.ok checks.
THIRD_PARTY_LIBXSLT_A_CHECKS =					\
	$(THIRD_PARTY_LIBXSLT_A).pkg

THIRD_PARTY_LIBXSLT_A_DIRECTDEPS =				\
	LIBC_CALLS						\
	LIBC_FMT						\
	LIBC_INTRIN						\
	LIBC_MEM						\
	LIBC_NEXGEN32E						\
	LIBC_RUNTIME						\
	LIBC_STDIO						\
	LIBC_STR						\
	LIBC_SYSV						\
	LIBC_THREAD						\
	LIBC_TINYMATH						\
	THIRD_PARTY_COMPILER_RT					\
	THIRD_PARTY_LIBXML2					\
	THIRD_PARTY_MUSL					\
	THIRD_PARTY_TZ

THIRD_PARTY_LIBXSLT_A_DEPS :=					\
	$(call uniq,$(foreach x,$(THIRD_PARTY_LIBXSLT_A_DIRECTDEPS),$($(x))))

$(THIRD_PARTY_LIBXSLT_A):					\
		third_party/libxslt/				\
		$(THIRD_PARTY_LIBXSLT_A).pkg			\
		$(THIRD_PARTY_LIBXSLT_A_OBJS)

$(THIRD_PARTY_LIBXSLT_A).pkg:					\
		$(THIRD_PARTY_LIBXSLT_A_OBJS)			\
		$(foreach x,$(THIRD_PARTY_LIBXSLT_A_DIRECTDEPS),$($(x)_A).pkg)

THIRD_PARTY_LIBXSLT_CFLAGS =					\
	-DHAVE_CONFIG_H						\
	-D_REENTRANT						\
	-Ithird_party/libxslt					\
	$(THIRD_PARTY_LIBXML2_CFLAGS)

$(THIRD_PARTY_LIBXSLT_A_OBJS): private				\
		CFLAGS +=					\
			$(THIRD_PARTY_LIBXSLT_CFLAGS)		\
			-ffunction-sections			\
			-fdata-sections				\

################################################################################
# the repeatable end-to-end check for both libraries
#   make -j8 o//third_party/libxslt/test/xmlxslt_test
#   o/third_party/libxslt/test/xmlxslt_test

THIRD_PARTY_LIBXSLT_TEST_SRCS =					\
	third_party/libxslt/test/xmlxslt_test.c

THIRD_PARTY_LIBXSLT_TEST_OBJS =					\
	$(THIRD_PARTY_LIBXSLT_TEST_SRCS:%.c=o/$(MODE)/%.o)

THIRD_PARTY_LIBXSLT_COMS =					\
	o/$(MODE)/third_party/libxslt/test/xmlxslt_test

THIRD_PARTY_LIBXSLT_BINS =					\
	$(THIRD_PARTY_LIBXSLT_COMS)				\
	$(THIRD_PARTY_LIBXSLT_COMS:%=%.dbg)

$(THIRD_PARTY_LIBXSLT_TEST_OBJS): private			\
		CFLAGS +=					\
			$(THIRD_PARTY_LIBXSLT_CFLAGS)

o/$(MODE)/third_party/libxslt/test/xmlxslt_test.dbg:		\
		$(THIRD_PARTY_LIBXSLT)				\
		$(THIRD_PARTY_LIBXSLT_TEST_OBJS)		\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

THIRD_PARTY_LIBXSLT_LIBS = $(foreach x,$(THIRD_PARTY_LIBXSLT_ARTIFACTS),$($(x)))
THIRD_PARTY_LIBXSLT_SRCS = $(foreach x,$(THIRD_PARTY_LIBXSLT_ARTIFACTS),$($(x)_SRCS))
THIRD_PARTY_LIBXSLT_HDRS = $(foreach x,$(THIRD_PARTY_LIBXSLT_ARTIFACTS),$($(x)_HDRS))
THIRD_PARTY_LIBXSLT_CHECKS = $(foreach x,$(THIRD_PARTY_LIBXSLT_ARTIFACTS),$($(x)_CHECKS))
THIRD_PARTY_LIBXSLT_OBJS = $(foreach x,$(THIRD_PARTY_LIBXSLT_ARTIFACTS),$($(x)_OBJS))
$(THIRD_PARTY_LIBXSLT_OBJS): third_party/libxslt/BUILD.mk
$(THIRD_PARTY_LIBXSLT_TEST_OBJS): third_party/libxslt/BUILD.mk

.PHONY: o/$(MODE)/third_party/libxslt
o/$(MODE)/third_party/libxslt:					\
		$(THIRD_PARTY_LIBXSLT_A)			\
		$(THIRD_PARTY_LIBXSLT_BINS)			\
		$(THIRD_PARTY_LIBXSLT_CHECKS)
