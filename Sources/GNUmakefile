#
# UDCode on GNUstep: the editor application, on UDCodeKit, with the
# grammar bundles and its own plugins (CFamily) in its PlugIns folder.
#
APP_NAME = UDCode
# Stamped by gnustep-release-actions from the tag.
VERSION = 0.0.0

include ../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

# this system's (gnustep.make's UD_SOURCES): apple/ is Xcode's, linux/ and windows/ each theirs
UDCode_OBJC_FILES = $(call UD_SOURCES,$(shell find . -name '*.m' | sort))
# the toolbar's and navigator's images: SF Symbols on macOS, ours here
UDCode_RESOURCE_FILES = $(shell find . -name '*.xib' | sort) ../scripts/appimage/udcode.png $(wildcard ../Images/GNUstep/*.png)
UDCode_MAIN_MODEL_FILE = MainMenu

UDCode_INCLUDE_DIRS = -I$(UD_INCLUDE) -I. -IModel -IDebug
UD_LIBS = $(call UD_FRAMEWORK_LIB,UDCodeKit,UDCodeKit) \
          $(call UD_FRAMEWORK_LIB,UDPieceTable,UDPieceTable) \
          $(call UD_FRAMEWORK_LIB,LSPKit,LSPKit)
ADDITIONAL_LIB_DIRS += $(addprefix -L,$(UD_LIBS))
# Libraries, not linker flags: on Windows the flags are linked whole, and
# import libraries linked whole collide.
UDCode_GUI_LIBS += -lUDCodeKit -lUDPieceTable -lLSPKit -ldispatch $(UD_BLOCKS_LIBS)
# Found beside it, relative to the executable: in the tree (build/gnustep/)
# and installed (Local/Applications beside Local/Library/Libraries). Windows
# finds DLLs on PATH instead.
ifeq ($(UD_WINDOWS),)
ADDITIONAL_LDFLAGS += $(foreach f,UDCodeKit UDPieceTable LSPKit,-Wl,-rpath,\$$ORIGIN/../../$(f)/$(f).framework/Versions/Current) \
    -Wl,-rpath,\$$ORIGIN/../../Library/Libraries
endif

# The grammar bundles and its own (Plugins/: CFamily), built beside it, go
# in its PlugIns folder.
UD_GRAMMARS = $(wildcard $(UD_BUILD)/tree-sitter-*/*.bundle) $(wildcard $(UD_BUILD)/Plugins/*/*.bundle)

include $(GNUSTEP_MAKEFILES)/application.make

after-all::
	@mkdir -p $(GNUSTEP_BUILD_DIR)/UDCode.app/PlugIns
	@for b in $(UD_GRAMMARS); do rm -rf $(GNUSTEP_BUILD_DIR)/UDCode.app/PlugIns/`basename $$b`; \
	    cp -R $$b $(GNUSTEP_BUILD_DIR)/UDCode.app/PlugIns/; done
