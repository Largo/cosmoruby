#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_IO_CONSOLE

THIRD_PARTY_RUBY_EXT_IO_CONSOLE_A = o/$(MODE)/third_party/ruby/ext/io/console/console.a
THIRD_PARTY_RUBY_EXT_IO_CONSOLE_SRCS = third_party/ruby/ext/io/console/console.c
THIRD_PARTY_RUBY_EXT_IO_CONSOLE_OBJS = $(THIRD_PARTY_RUBY_EXT_IO_CONSOLE_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_IO_CONSOLE_A):			\
		third_party/ruby/ext/io/console/	\
		$(THIRD_PARTY_RUBY_EXT_IO_CONSOLE_OBJS)

o/$(MODE)/third_party/ruby/ext/io/console/%.o: private	\
	CFLAGS +=						\
		-Ithird_party/ruby/include			\
		-Ithird_party/ruby				\
		-DRUBY_EXPORT					\
		-DRUBY_COSMOPOLITAN				\
		-DHAVE_TERMIOS_H				\
		-DHAVE_UNISTD_H					\
		-DHAVE_FCNTL_H					\
		-DHAVE_SYS_IOCTL_H				\
		-DHAVE_RB_IO_DESCRIPTOR				\
		-DHAVE_RB_IO_CLOSED_P				\
		-Wno-deprecated-declarations

$(THIRD_PARTY_RUBY_EXT_IO_CONSOLE_OBJS): third_party/ruby/ext/io/console/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/io/console
o/$(MODE)/third_party/ruby/ext/io/console: $(THIRD_PARTY_RUBY_EXT_IO_CONSOLE_A)
