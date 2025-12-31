#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_RIPPER

THIRD_PARTY_RUBY_EXT_RIPPER_SRCS =				\
	third_party/ruby/ext/ripper/ripper.c			\
	third_party/ruby/ext/ripper/ripper_init.c		\
	third_party/ruby/ext/ripper/eventids1.c		\
	third_party/ruby/ext/ripper/eventids2.c

THIRD_PARTY_RUBY_EXT_RIPPER_OBJS = $(THIRD_PARTY_RUBY_EXT_RIPPER_SRCS:%.c=o/$(MODE)/%.o)

THIRD_PARTY_RUBY_EXT_RIPPER_A = o/$(MODE)/third_party/ruby/ext/ripper/ripper.a

$(THIRD_PARTY_RUBY_EXT_RIPPER_A):				\
		$(THIRD_PARTY_RUBY_EXT_RIPPER_OBJS)

o/$(MODE)/third_party/ruby/ext/ripper/%.o: private		\
	CFLAGS +=						\
		-Ithird_party/ruby/include			\
		-Ithird_party/ruby				\
		-Ithird_party/ruby/ext/ripper			\
		-DRUBY_EXPORT					\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_RIPPER_OBJS): third_party/ruby/ext/ripper/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/ripper
o/$(MODE)/third_party/ruby/ext/ripper: $(THIRD_PARTY_RUBY_EXT_RIPPER_A)
