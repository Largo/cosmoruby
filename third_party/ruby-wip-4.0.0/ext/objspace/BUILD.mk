#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_OBJSPACE

THIRD_PARTY_RUBY_EXT_OBJSPACE_A = o/$(MODE)/third_party/ruby/ext/objspace/objspace.a
THIRD_PARTY_RUBY_EXT_OBJSPACE_SRCS =			\
	third_party/ruby/ext/objspace/object_tracing.c	\
	third_party/ruby/ext/objspace/objspace.c	\
	third_party/ruby/ext/objspace/objspace_dump.c
THIRD_PARTY_RUBY_EXT_OBJSPACE_OBJS = $(THIRD_PARTY_RUBY_EXT_OBJSPACE_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_OBJSPACE_A):				\
		$(THIRD_PARTY_RUBY_EXT_OBJSPACE_OBJS)



# Compiler flags for objspace extension
o/$(MODE)/third_party/ruby/ext/objspace/%.o: private		\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_OBJSPACE_OBJS): third_party/ruby/ext/objspace/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/objspace
o/$(MODE)/third_party/ruby/ext/objspace: $(THIRD_PARTY_RUBY_EXT_OBJSPACE_A)
