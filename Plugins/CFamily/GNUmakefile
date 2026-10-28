#
# CFamily.bundle on GNUstep: UDCode's C family (build systems, test runners,
# debuggers; see Sources/UDCFamilyPlugin.h), in UDCode.app's PlugIns. Its
# references to UDCodeKit, LSPKit and UDPieceTable are left for the
# application, which links them, to resolve when it loads the bundle (on
# Windows a DLL is linked against them: UD_PLUGIN_LIBS).
#
BUNDLE_NAME = CFamily
BUNDLE_EXTENSION = .bundle

include ../../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

CFamily_OBJC_FILES = $(wildcard Sources/*.m)
CFamily_PRINCIPAL_CLASS = UDCFamilyPlugin
CFamily_RESOURCE_FILES = Resources/LanguageInfo.plist
CFamily_INCLUDE_DIRS = -I$(UD_INCLUDE) -I$(UD_INCLUDE)/UDCodeKit -ISources
CFamily_STANDARD_INSTALL = no
CFamily_BUNDLE_LIBS += $(UD_PLUGIN_LIBS)

include $(GNUSTEP_MAKEFILES)/bundle.make
