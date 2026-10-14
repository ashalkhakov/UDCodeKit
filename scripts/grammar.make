#
# A grammar bundle on GNUstep: each tree-sitter-<lang>/GNUmakefile sets
# UD_GRAMMAR (Json, Xml, ...) and includes this.
#
# The bundle holds the principal class TreeSitter<Grammar>Plugin, the
# generated parser (and scanner), LanguageInfo.plist and the queries. Its
# references to UDCodeKit and UDPieceTable are left for the application,
# which links both, to resolve when it loads the bundle.
#
BUNDLE_NAME = TreeSitter$(UD_GRAMMAR)
BUNDLE_EXTENSION = .bundle

include ../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

# UD_GRAMMAR_EXCLUDE: sources this platform goes without.
$(BUNDLE_NAME)_OBJC_FILES = $(filter-out $(UD_GRAMMAR_EXCLUDE),$(wildcard Sources/*.m))
$(BUNDLE_NAME)_C_FILES = $(wildcard src/*.c)
# A scanner in C++ (Markdown's) brings the C++ library with it.
$(BUNDLE_NAME)_CC_FILES = $(wildcard src/*.cc)
ifneq ($($(BUNDLE_NAME)_CC_FILES),)
$(BUNDLE_NAME)_BUNDLE_LIBS += -lstdc++
endif
$(BUNDLE_NAME)_PRINCIPAL_CLASS = TreeSitter$(UD_GRAMMAR)Plugin
$(BUNDLE_NAME)_RESOURCE_FILES = Resources/LanguageInfo.plist $(wildcard Resources/*.scm)
$(BUNDLE_NAME)_INCLUDE_DIRS = -I$(UD_INCLUDE) -I$(UD_INCLUDE)/UDCodeKit -ISources -Isrc \
    -I../tree-sitter/include
# Installed for what embeds UDCodeKit (UDCode carries its own copy, in its
# PlugIns folder): Library/Bundles/UDCodeKit/.
BUNDLE_INSTALL_DIR = $(GNUSTEP_BUNDLES)/UDCodeKit
# Generated code: its warnings are not ours.
ADDITIONAL_CFLAGS += -w

include $(GNUSTEP_MAKEFILES)/bundle.make
