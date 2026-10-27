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
# Windows lays a framework out flat: its DLL and import library at its top.
#
# What differs between systems is in folders of their own beside the
# shared sources, the build taking its system's and leaving the others':
# posix/ (Linux, and macOS through Xcode), linux/, apple/ (Xcode) and
# windows/. UD_SYSTEM_DIRS are this system's; $(call UD_SOURCES,<list>)
# drops the others' from a list of sources.
#
# Linux: forkpty is libutil's, and a program finds the tree's libraries by
# its rpath. Windows: a DLL is found on PATH, and there is no forkpty.
ifeq ($(OS),Windows_NT)
UD_FRAMEWORK_LIB = $(UD_BUILD)/$(1)/$(2).framework
UD_SYSTEM = windows
UD_SYSTEM_DIRS = windows
UD_OTHER_DIRS = posix linux apple
UD_PTY_LIBS =
UD_WINDOWS = yes
else
UD_FRAMEWORK_LIB = $(UD_BUILD)/$(1)/$(2).framework/Versions/Current
UD_SYSTEM = posix
UD_SYSTEM_DIRS = posix linux
UD_OTHER_DIRS = windows apple
UD_PTY_LIBS = -lutil
UD_WINDOWS =
endif
UD_SOURCES = $(filter-out $(foreach d,$(UD_OTHER_DIRS),%/$(d)/%),$(1))
# A plugin bundle's references to the frameworks: left for the application
# that loads it on Linux; a Windows DLL is linked against all it uses. C++'s
# library: libstdc++ there, LLVM's libc++ in MSYS2's CLANG64.
ifneq ($(UD_WINDOWS),)
UD_PLUGIN_LIBS = $(foreach f,UDCodeKit UDPieceTable LSPKit,-L$(call UD_FRAMEWORK_LIB,$(f),$(f))) \
    -lUDCodeKit -lUDPieceTable -lLSPKit -ldispatch -lBlocksRuntime
UD_CXX_LIB = -lc++
else
UD_PLUGIN_LIBS =
UD_CXX_LIB = -lstdc++
endif
# A test run with the tree's libraries found: $(call UD_RUN_WITH,<dirs, :-separated>).
UD_RUN_WITH = LD_LIBRARY_PATH="$(1)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" PATH="$(1):$$PATH"

# The include link for a framework, made as its makefile is read (before
# make -j compiles anything that needs it):
#   UD_LINKED := $(shell $(call UD_LINK_HEADERS,<Name>,<source folder>))
# On Windows a directory junction, made when it is not there yet: MSYS2's
# ln -s copies the folder, and the copy's headers are other files to
# #import. A junction needs no privilege.
ifeq ($(OS),Windows_NT)
UD_LINK_HEADERS = mkdir -p $(UD_INCLUDE) && { [ -e $(UD_INCLUDE)/$(1) ] \
  || cmd //c "mklink /J $$(cygpath -w $(UD_INCLUDE)/$(1)) $$(cygpath -w $(2))" > /dev/null; }
else
UD_LINK_HEADERS = mkdir -p $(UD_INCLUDE) && ln -sfn $(2) $(UD_INCLUDE)/$(1)
endif

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1
