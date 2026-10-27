#
# UDPieceTableTests: the text model's tests, against the framework built in
# the tree.
#
#   make run-tests
#
BUNDLE_NAME = UDPieceTableTests
UDPieceTableTests_STANDARD_INSTALL = no

include ../../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

UDPieceTableTests_OBJC_FILES = $(wildcard *.m)

UD_LIBS = $(call UD_FRAMEWORK_LIB,UDPieceTable,UDPieceTable)
UDPieceTableTests_INCLUDE_DIRS = -I$(UD_INCLUDE) -I../Sources
ADDITIONAL_LIB_DIRS += -L$(UD_LIBS)
# Libraries, not linker flags: on Windows the flags are linked whole.
UDPieceTableTests_BUNDLE_LIBS += -lUDPieceTable -lXCTest -ldispatch -lBlocksRuntime

XCTEST ?= xctest
TEST_TIMEOUT ?= 900

include $(GNUSTEP_MAKEFILES)/bundle.make

.PHONY: run-tests
run-tests: all
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	$(call UD_RUN_WITH,$(UD_LIBS)) \
	timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) "$(GNUSTEP_BUILD_DIR)/$(BUNDLE_NAME).bundle"
