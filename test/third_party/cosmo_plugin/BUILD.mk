#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += TEST_THIRD_PARTY_COSMO_PLUGIN

TEST_THIRD_PARTY_COSMO_PLUGIN_ARTIFACTS += TEST_THIRD_PARTY_COSMO_PLUGIN_A
TEST_THIRD_PARTY_COSMO_PLUGIN = $(TEST_THIRD_PARTY_COSMO_PLUGIN_A_DEPS) $(TEST_THIRD_PARTY_COSMO_PLUGIN_A)
TEST_THIRD_PARTY_COSMO_PLUGIN_A = o/$(MODE)/test/third_party/cosmo_plugin/test_hello.a

TEST_THIRD_PARTY_COSMO_PLUGIN_A_SRCS =					\
	test/third_party/cosmo_plugin/test_hello.c

TEST_THIRD_PARTY_COSMO_PLUGIN_A_OBJS =					\
	$(TEST_THIRD_PARTY_COSMO_PLUGIN_A_SRCS:%.c=o/$(MODE)/%.o)

TEST_THIRD_PARTY_COSMO_PLUGIN_A_DIRECTDEPS =

TEST_THIRD_PARTY_COSMO_PLUGIN_A_DEPS :=					\
	$(call uniq,$(foreach x,$(TEST_THIRD_PARTY_COSMO_PLUGIN_A_DIRECTDEPS),$($(x))))

$(TEST_THIRD_PARTY_COSMO_PLUGIN_A_OBJS): private			\
	CFLAGS +=							\
		-Ithird_party/ruby/include				\
		-Ithird_party/ruby					\
		-fPIC

$(TEST_THIRD_PARTY_COSMO_PLUGIN_A):					\
	test/third_party/cosmo_plugin/					\
	$(TEST_THIRD_PARTY_COSMO_PLUGIN_A_OBJS)

# Skip .pkg generation for plugin tests - they have undefined symbols by design
# $(TEST_THIRD_PARTY_COSMO_PLUGIN_A).pkg:					\
# 	$(TEST_THIRD_PARTY_COSMO_PLUGIN_A_OBJS)				\
# 	$(foreach x,$(TEST_THIRD_PARTY_COSMO_PLUGIN_A_DIRECTDEPS),$($(x)_A).pkg)

TEST_THIRD_PARTY_COSMO_PLUGIN_LIBS = $(foreach x,$(TEST_THIRD_PARTY_COSMO_PLUGIN_ARTIFACTS),$($(x)))
TEST_THIRD_PARTY_COSMO_PLUGIN_SRCS = $(foreach x,$(TEST_THIRD_PARTY_COSMO_PLUGIN_ARTIFACTS),$($(x)_SRCS))
TEST_THIRD_PARTY_COSMO_PLUGIN_OBJS = $(foreach x,$(TEST_THIRD_PARTY_COSMO_PLUGIN_ARTIFACTS),$($(x)_OBJS))

$(TEST_THIRD_PARTY_COSMO_PLUGIN_OBJS): test/third_party/cosmo_plugin/BUILD.mk

.PHONY: o/$(MODE)/test/third_party/cosmo_plugin
o/$(MODE)/test/third_party/cosmo_plugin: $(TEST_THIRD_PARTY_COSMO_PLUGIN_A)
