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
ADDITIONAL_LDFLAGS += -lUDPieceTable -lXCTest -ldispatch -lBlocksRuntime

XCTEST ?= xctest
TEST_TIMEOUT ?= 900

include $(GNUSTEP_MAKEFILES)/bundle.make

.PHONY: run-tests
run-tests: all
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	LD_LIBRARY_PATH="$(UD_LIBS)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) "$(GNUSTEP_BUILD_DIR)/$(BUNDLE_NAME).bundle"
