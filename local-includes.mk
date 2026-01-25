# Local project-specific BUILD.mk includes
# This file is not committed to the repository
# Add it to .git/info/exclude

# Mexican Toaster / Ruby development
include third_party/libyaml/BUILD.mk
include third_party/ruby/BUILD.mk
include examples/rubyapp/BUILD.mk
include third_party/mexican_toaster/BUILD.mk
# Cosmo plugin loader + tests
include third_party/cosmo_plugin/BUILD.mk
include test/third_party/cosmo_plugin/BUILD.mk

# Require bootstrap mtdeps for dependency generation.
ifeq ($(wildcard build/bootstrap/mtdeps),)
$(error Missing build/bootstrap/mtdeps. Run third_party/ruby/cosmo_configure.sh --bootstrap)
else
MKDEPS := build/bootstrap/mtdeps -P ruby_shims/
endif

# Core Makefile computes SRCS/HDRS/INCS/BINS before loading this file, so
# append the local packages to those aggregates here.
LOCAL_PKGS :=							\
	THIRD_PARTY_LIBYAML					\
	THIRD_PARTY_RUBY					\
	RUBYAPP							\
	THIRD_PARTY_MEXICAN_TOASTER				\
	THIRD_PARTY_COSMO_PLUGIN				\
	TEST_THIRD_PARTY_COSMO_PLUGIN

OBJS   += $(foreach x,$(LOCAL_PKGS),$($(x)_OBJS))
SRCS   += $(foreach x,$(LOCAL_PKGS),$($(x)_SRCS))
HDRS   += $(foreach x,$(LOCAL_PKGS),$($(x)_HDRS))
INCS   += $(foreach x,$(LOCAL_PKGS),$($(x)_INCS))
BINS   += $(foreach x,$(LOCAL_PKGS),$($(x)_BINS))
TESTS  += $(foreach x,$(LOCAL_PKGS),$($(x)_TESTS))
CHECKS += $(foreach x,$(LOCAL_PKGS),$($(x)_CHECKS))
