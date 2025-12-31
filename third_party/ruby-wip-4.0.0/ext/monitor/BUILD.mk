#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_MONITOR

THIRD_PARTY_RUBY_EXT_MONITOR_A = o/$(MODE)/third_party/ruby/ext/monitor/monitor.a
THIRD_PARTY_RUBY_EXT_MONITOR_SRCS = third_party/ruby/ext/monitor/monitor.c
THIRD_PARTY_RUBY_EXT_MONITOR_OBJS = $(THIRD_PARTY_RUBY_EXT_MONITOR_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_MONITOR_A):			\
		$(THIRD_PARTY_RUBY_EXT_MONITOR_OBJS)


o/$(MODE)/third_party/ruby/ext/monitor/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_MONITOR_OBJS): third_party/ruby/ext/monitor/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/monitor
o/$(MODE)/third_party/ruby/ext/monitor: $(THIRD_PARTY_RUBY_EXT_MONITOR_A)
