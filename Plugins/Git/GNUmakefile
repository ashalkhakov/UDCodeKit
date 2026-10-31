#
# Git.bundle on GNUstep: UDCode's source control over git (VS Code's git
# extension; see Sources/UDGitPlugin.h), in UDCode.app's PlugIns. Its
# references to UDCodeKit, LSPKit and UDPieceTable are left for the
# application, which links them, to resolve when it loads the bundle (on
# Windows a DLL is linked against them: UD_PLUGIN_LIBS).
#
BUNDLE_NAME = Git
BUNDLE_EXTENSION = .bundle

include ../../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

Git_OBJC_FILES = $(wildcard Sources/*.m)
Git_PRINCIPAL_CLASS = UDGitPlugin
# its dialogs and Repositories view: AppKit's
Git_NEEDS_GUI = yes
Git_RESOURCE_FILES = Resources/LanguageInfo.plist $(wildcard Resources/*.xib)
Git_INCLUDE_DIRS = -I$(UD_INCLUDE) -I$(UD_INCLUDE)/UDCodeKit -ISources
Git_STANDARD_INSTALL = no
Git_BUNDLE_LIBS += $(UD_PLUGIN_LIBS)

include $(GNUSTEP_MAKEFILES)/bundle.make
