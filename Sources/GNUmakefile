#
# UDCode on GNUstep: the editor application, on UDCodeKit, with the
# grammar bundles in its PlugIns folder.
#
APP_NAME = UDCode
# Stamped by gnustep-release-actions from the tag.
VERSION = 0.0.0

include ../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

UDCode_OBJC_FILES = $(shell find . -name '*.m' | sort)
UDCode_RESOURCE_FILES = $(shell find . -name '*.xib' | sort) ../scripts/appimage/udcode.png
UDCode_MAIN_MODEL_FILE = MainMenu

UDCode_INCLUDE_DIRS = -I$(UD_INCLUDE) -I. -IModel
UD_LIBS = $(call UD_FRAMEWORK_LIB,UDCodeKit,UDCodeKit) \
          $(call UD_FRAMEWORK_LIB,UDPieceTable,UDPieceTable) \
          $(call UD_FRAMEWORK_LIB,LSPKit,LSPKit)
ADDITIONAL_LIB_DIRS += $(addprefix -L,$(UD_LIBS))
# Found beside it, relative to the executable: in the tree (build/gnustep/)
# and installed (Local/Applications beside Local/Library/Libraries).
ADDITIONAL_LDFLAGS += -lUDCodeKit -lUDPieceTable -lLSPKit -ldispatch -lBlocksRuntime \
    $(foreach f,UDCodeKit UDPieceTable LSPKit,-Wl,-rpath,\$$ORIGIN/../../$(f)/$(f).framework/Versions/Current) \
    -Wl,-rpath,\$$ORIGIN/../../Library/Libraries

# The grammar bundles, built beside it, go in its PlugIns folder.
UD_GRAMMARS = $(wildcard $(UD_BUILD)/tree-sitter-*/*.bundle)

include $(GNUSTEP_MAKEFILES)/application.make

after-all::
	@mkdir -p $(GNUSTEP_BUILD_DIR)/UDCode.app/PlugIns
	@for b in $(UD_GRAMMARS); do rm -rf $(GNUSTEP_BUILD_DIR)/UDCode.app/PlugIns/`basename $$b`; \
	    cp -R $$b $(GNUSTEP_BUILD_DIR)/UDCode.app/PlugIns/; done
