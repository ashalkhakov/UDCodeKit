#
# UDCodeTests: the editor's tests, UDCode's windows among them, against the
# frameworks and grammar bundles built in the tree.
#
#   xvfb-run -a make run-tests    (the root GNUmakefile's make check runs it
#                                  too, under Xvfb when there is no display)
#
BUNDLE_NAME = UDCodeTests
UDCodeTests_STANDARD_INSTALL = no

include ../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

APP_DIR = ../Sources

# The app's objects are compiled in directly (there is no host app): all of
# UDCode but main.m, whose main() would collide with the test runner's.
UDCodeTests_OBJC_FILES = $(wildcard *.m) \
    $(filter-out $(APP_DIR)/main.m,$(shell find $(APP_DIR) -name '*.m' | sort))
# Its nibs, which it loads from the main bundle or its classes' bundle: this
# one, where those classes now live.
UDCodeTests_RESOURCE_FILES = $(filter-out %/MainMenu.xib,$(shell find $(APP_DIR) -name '*.xib' | sort))
UDCodeTests_NEEDS_GUI = yes

# CFamily's headers: its classes are reached by name (the bundle, UDCode.app's, is loaded)
UDCodeTests_INCLUDE_DIRS = -I$(UD_INCLUDE) -I$(UD_INCLUDE)/UDCodeKit -I$(APP_DIR) -I$(APP_DIR)/Model -I$(APP_DIR)/Debug \
    -I../tree-sitter/include -I../Plugins/CFamily/Sources
UD_LIBS = $(call UD_FRAMEWORK_LIB,UDCodeKit,UDCodeKit) \
          $(call UD_FRAMEWORK_LIB,UDPieceTable,UDPieceTable) \
          $(call UD_FRAMEWORK_LIB,LSPKit,LSPKit)
ADDITIONAL_LIB_DIRS += $(addprefix -L,$(UD_LIBS))
ADDITIONAL_LDFLAGS += -lUDCodeKit -lUDPieceTable -lLSPKit -lXCTest -ldispatch -lBlocksRuntime

# The grammars: UDCode.app's, built before this (the root GNUmakefile).
UD_PLUGINS = $(UD_BUILD)/Sources/UDCode.app/PlugIns

XCTEST ?= xctest
# Bounded: a modal waiting for an event that never comes would otherwise
# hang the run.
TEST_TIMEOUT ?= 900

include $(GNUSTEP_MAKEFILES)/bundle.make

.PHONY: run-tests
run-tests: all
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	LD_LIBRARY_PATH="$(subst $(space),:,$(UD_LIBS))$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	UD_PLUGINS_PATH="$(UD_PLUGINS)" \
	timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) "$(GNUSTEP_BUILD_DIR)/$(BUNDLE_NAME).bundle"
space := $(empty) $(empty)
