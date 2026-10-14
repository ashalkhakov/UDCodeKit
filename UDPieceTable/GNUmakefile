#
# UDPieceTable.framework on GNUstep: the text model (Foundation only).
#
FRAMEWORK_NAME = UDPieceTable

include ../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

UDPieceTable_OBJC_FILES = $(wildcard Sources/*.m)
UDPieceTable_HEADER_FILES_DIR = Sources
UDPieceTable_HEADER_FILES = $(notdir $(wildcard Sources/*.h))
UDPieceTable_INCLUDE_DIRS = -I$(UD_INCLUDE) -ISources

include $(GNUSTEP_MAKEFILES)/framework.make

before-all::
	@$(call UD_LINK_HEADERS,UDPieceTable,$(CURDIR)/Sources)
