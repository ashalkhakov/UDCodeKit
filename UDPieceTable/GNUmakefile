#
# UDPieceTable.framework on GNUstep: the text model (Foundation only).
#
FRAMEWORK_NAME = UDPieceTable

include ../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

# <UDPieceTable/X.h> from the tree (gnustep.make's UD_LINK_HEADERS).
UD_LINKED := $(shell $(call UD_LINK_HEADERS,UDPieceTable,$(CURDIR)/Sources))

UDPieceTable_OBJC_FILES = $(wildcard Sources/*.m)
UDPieceTable_HEADER_FILES_DIR = Sources
UDPieceTable_HEADER_FILES = $(notdir $(wildcard Sources/*.h))
UDPieceTable_INCLUDE_DIRS = -I$(UD_INCLUDE) -ISources

# Windows: a DLL exports what it marks, and once the runtime marks its
# classes, its C constants and functions must be marked too: UDPIECETABLE_EXPORT
# (in its headers) is "export" while it is built, an import elsewhere.
ifneq ($(UD_WINDOWS),)
UDPieceTable_CPPFLAGS += "-DUDPIECETABLE_EXPORT=__declspec(dllexport) extern"
endif

include $(GNUSTEP_MAKEFILES)/framework.make
