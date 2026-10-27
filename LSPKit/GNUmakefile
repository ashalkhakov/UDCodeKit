#
# LSPKit.framework on GNUstep: the Language Server Protocol client.
#
FRAMEWORK_NAME = LSPKit

include ../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

# The system's half (LSPSystem.h): posix/ or windows/, as gnustep.make says.
LSPKit_OBJC_FILES = $(wildcard *.m) $(wildcard $(UD_SYSTEM)/*.m)
LSPKit_HEADER_FILES = $(filter-out LSPSystem.h,$(wildcard *.h))
LSPKit_INCLUDE_DIRS = -I$(UD_INCLUDE) -I.

# Windows: a DLL exports what it marks, and once the runtime marks its
# classes, its C constants and functions must be marked too: LSPKIT_EXPORT
# (in its headers) is "export" while it is built, an import elsewhere.
ifneq ($(UD_WINDOWS),)
LSPKit_CPPFLAGS += "-DLSPKIT_EXPORT=__declspec(dllexport) extern"
endif

include $(GNUSTEP_MAKEFILES)/framework.make

before-all::
	@$(call UD_LINK_HEADERS,LSPKit,$(CURDIR))
