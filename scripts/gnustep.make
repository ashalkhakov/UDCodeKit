#
# What the GNUstep makefiles share; each includes it before common.make.
#
# Everything is built under build/gnustep/, out of the source tree: Xcode's
# synchronized folders would otherwise pick up the objects and dependency
# files as sources.
#
# <Framework/X.h> must reach the very file a quoted "X.h" does, or #import
# sees two headers (gnustep-make copies a framework's headers). So
# build/gnustep/include/<Framework> links to the framework's source
# folder, and everything that includes a framework from the tree puts
# $(UD_INCLUDE) first.
#
UD_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
UD_BUILD := $(UD_ROOT)/build/gnustep
UD_INCLUDE := $(UD_BUILD)/include

# This makefile's own build folder: build/gnustep/<path from the root>.
override GNUSTEP_BUILD_DIR := $(UD_BUILD)/$(patsubst $(UD_ROOT)/%,%,$(abspath $(CURDIR)))

# Where a framework built in the tree keeps its library: $(call UD_FRAMEWORK_LIB,<dir>,<Name>).
UD_FRAMEWORK_LIB = $(UD_BUILD)/$(1)/$(2).framework/Versions/Current

# The include link for a framework: $(call UD_LINK_HEADERS,<Name>,<source folder>).
# On Windows a directory junction: MSYS2's ln -s copies the folder, and the
# copy's headers are other files to #import. A junction needs no privilege,
# and rmdir takes one (or an old copy) away without touching its folder.
ifeq ($(OS),Windows_NT)
UD_LINK_HEADERS = mkdir -p $(UD_INCLUDE) \
  && { [ ! -e $(UD_INCLUDE)/$(1) ] || cmd //c "rmdir /s /q $$(cygpath -w $(UD_INCLUDE)/$(1))"; } \
  && cmd //c "mklink /J $$(cygpath -w $(UD_INCLUDE)/$(1)) $$(cygpath -w $(2))" > /dev/null
else
UD_LINK_HEADERS = mkdir -p $(UD_INCLUDE) && ln -sfn $(2) $(UD_INCLUDE)/$(1)
endif

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1
