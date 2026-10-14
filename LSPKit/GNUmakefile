#
# LSPKit.framework on GNUstep: the Language Server Protocol client.
#
FRAMEWORK_NAME = LSPKit

include ../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

LSPKit_OBJC_FILES = $(wildcard *.m)
LSPKit_HEADER_FILES = $(wildcard *.h)
LSPKit_INCLUDE_DIRS = -I$(UD_INCLUDE) -I.

include $(GNUSTEP_MAKEFILES)/framework.make

before-all::
	@$(call UD_LINK_HEADERS,LSPKit,$(CURDIR))
