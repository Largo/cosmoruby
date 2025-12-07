# Local project-specific BUILD.mk includes
# This file is not committed to the repository
# Add it to .git/info/exclude

# Mexican Toaster / Ruby development
include third_party/libyaml/BUILD.mk
include third_party/ruby/BUILD.mk
include examples/rubyapp/BUILD.mk
include third_party/mexican_toaster/BUILD.mk

# Prefer mtdeps for dependency generation when it's built; fall back to stock mkdeps otherwise.
ifneq ($(wildcard o/$(MODE)/third_party/mexican_toaster/mtdeps),)
MKDEPS := o/$(MODE)/third_party/mexican_toaster/mtdeps
endif

# Core Makefile computes SRCS/HDRS/INCS/BINS before loading this file, so
# append the local packages to those aggregates here.
LOCAL_PKGS :=							\
	THIRD_PARTY_LIBYAML					\
	THIRD_PARTY_RUBY					\
	RUBYAPP							\
	THIRD_PARTY_MEXICAN_TOASTER

OBJS   += $(foreach x,$(LOCAL_PKGS),$($(x)_OBJS))
SRCS   += $(foreach x,$(LOCAL_PKGS),$($(x)_SRCS))
HDRS   += $(foreach x,$(LOCAL_PKGS),$($(x)_HDRS))
INCS   += $(foreach x,$(LOCAL_PKGS),$($(x)_INCS))
BINS   += $(foreach x,$(LOCAL_PKGS),$($(x)_BINS))
TESTS  += $(foreach x,$(LOCAL_PKGS),$($(x)_TESTS))
CHECKS += $(foreach x,$(LOCAL_PKGS),$($(x)_CHECKS))
