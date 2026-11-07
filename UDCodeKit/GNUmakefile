#
# UDCodeKit.framework on GNUstep: the editor. Links UDPieceTable and LSPKit
# (built first, in the tree) and compiles the tree-sitter runtime in.
#
FRAMEWORK_NAME = UDCodeKit

include ../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

# This system's sources, not another's (gnustep.make's UD_SOURCES).
UDCodeKit_OBJC_FILES = $(call UD_SOURCES,$(shell find Sources -name '*.m' | sort))
UDCodeKit_C_FILES = ../tree-sitter/src/lib.c $(wildcard ../libvterm/src/*.c)

# The headers sit in subfolders; <UDCodeKit/X.h> needs them in one:
# build/gnustep/include/UDCodeKit holds a link to each (see gnustep.make).
# Made as the makefile is read: gnustep-make copies the headers before any
# before-all rule runs.
# On Windows hard links: MSYS2's ln -s copies, and a copy is another file
# to #import; a hard link is the same one.
UD_HEADER_LINK = $(if $(UD_WINDOWS),ln -f,ln -sfn)
UD_HEADER_LINKS := $(shell mkdir -p $(UD_INCLUDE)/UDCodeKit && \
    for h in `find $(CURDIR)/Sources -name '*.h'`; do $(UD_HEADER_LINK) $$h $(UD_INCLUDE)/UDCodeKit/; done)
UDCodeKit_HEADER_FILES_DIR = $(UD_INCLUDE)/UDCodeKit
UDCodeKit_HEADER_FILES = \
    TreeSitterTheme.h \
    UDAuthorsView.h \
    UDAutoIndenter.h \
    UDBadgeTextFieldCell.h \
    UDBracketMatchHighlighter.h \
    UDBreakpointEditorViewController.h \
    UDBreakpointNavigatorViewController.h \
    UDBreakpointStore.h \
    UDBuildLogViewController.h \
    UDBuildRunner.h \
    UDBuildSystem.h \
    UDCodeDocument.h \
    UDCodeEditorLayoutManager.h \
    UDCodeEditorViewController.h \
    UDCodeKit.h \
    UDCommandTestRunner.h \
    UDCompletionListController.h \
    UDCredentialStore.h \
    UDCustomDocument.h \
    UDDebugAreaViewController.h \
    UDDebugBarViewController.h \
    UDDebugHoverViewController.h \
    UDDebugNavigatorViewController.h \
    UDDebugSession.h \
    UDDebugger.h \
    UDDecorationHighlighter.h \
    UDDecorationLayerRegistry.h \
    UDDiagnosticItem.h \
    UDDiagnosticStore.h \
    UDDiagnosticTextView.h \
    UDDiffEditorViewController.h \
    UDDocumentSymbol.h \
    UDEditorSession.h \
    UDEditorTabsController.h \
    UDErrorsViewController.h \
    UDEditorPanes.h \
    UDExtension.h \
    UDExtensionsWindowController.h \
    UDFileNavigatorViewController.h \
    UDFileSystemProvider.h \
    UDFileWatcher.h \
    UDFindBarViewController.h \
    UDFindModel.h \
    UDFindResultsGutterView.h \
    UDFoldingController.h \
    UDHistoryViewController.h \
    UDHoverViewController.h \
    UDInstalledExtensions.h \
    UDIssuePopupController.h \
    UDJumpBarController.h \
    UDJumpBarView.h \
    UDLSPCoordinator.h \
    UDLSPDiagnosticHighlighter.h \
    UDLanguageConfiguration.h \
    UDLanguageKeyHandler.h \
    UDLanguageMode.h \
    UDLanguageModeRegistry.h \
    UDLineNumberGutterView.h \
    UDLinkComputer.h \
    UDLinkDetector.h \
    UDLinkedEditing.h \
    UDOccurrencesHighlighter.h \
    UDOpenQuicklyController.h \
    UDPaneSplitController.h \
    UDPaths.h \
    UDPlaceholderHighlighter.h \
    UDPreferencesController.h \
    UDProject.h \
    UDProjectSettingsController.h \
    UDPseudoTerminal.h \
    UDSearchResultsViewController.h \
    UDSemanticTokensHighlighter.h \
    UDShell.h \
    UDSourceControl.h \
    UDSourceControlNavigatorViewController.h \
    UDStructuredNavigator.h \
    UDSyntaxHighlighter.h \
    UDTabBarView.h \
    UDTabItemView.h \
    UDTasks.h \
    UDTerminalView.h \
    UDTerminalViewController.h \
    UDTestNavigatorViewController.h \
    UDTestRunner.h \
    UDTests.h \
    UDTextModel+LSPTextBuffer.h \
    UDTextModelString.h \
    UDTextModelTextStorage.h \
    UDToolLocator.h \
    UDTreeSitterHighlighter.h \
    UDTreeSitterOutline.h \
    UDTreeSitterTypes.h \
    UDTreeView.h \
    UDWorkbench.h \
    UDWorkspaceEdit.h

UDCodeKit_RESOURCE_FILES = $(shell find Sources -name '*.xib' | sort)

# Its own folders first: a header a source imports by its name, from a
# folder that is not its own, is then reached by one path, the one its
# folder's sources reach it by (on Windows the include folder's link
# would be another file to #import).
UDCodeKit_INCLUDE_DIRS = $(addprefix -I,$(filter-out $(foreach d,$(UD_OTHER_DIRS),%/$(d)),$(shell find Sources -type d | sort))) \
    -I$(UD_INCLUDE) -I$(UD_INCLUDE)/UDCodeKit \
    -I../tree-sitter/include -I../tree-sitter/src -I../libvterm/include
UDCodeKit_LIB_DIRS = -L$(call UD_FRAMEWORK_LIB,UDPieceTable,UDPieceTable) \
    -L$(call UD_FRAMEWORK_LIB,LSPKit,LSPKit)
UDCodeKit_LIBRARIES_DEPEND_UPON = -lUDPieceTable -lLSPKit $(GUI_LIBS) $(FND_LIBS) $(OBJC_LIBS) \
    -ldispatch $(UD_BLOCKS_LIBS) $(UD_PTY_LIBS) $(UD_CREDENTIAL_LIBS)
# The system's credential store: libsecret on Linux, loaded when first
# needed (-ldl; no header needed), Credential Manager's advapi32 on Windows.
UD_CREDENTIAL_LIBS = $(if $(UD_WINDOWS),-ladvapi32,-ldl)
# tree-sitter's and libvterm's C want C11 (and C99's features) and their own warnings left alone.
ADDITIONAL_CFLAGS += -std=gnu11 -w

# Windows: a DLL exports what it marks, and once the runtime marks its
# classes, its C constants and functions must be marked too: UDCODEKIT_EXPORT
# (in its headers) is "export" while it is built, an import elsewhere.
ifneq ($(UD_WINDOWS),)
UDCodeKit_CPPFLAGS += "-DUDCODEKIT_EXPORT=__declspec(dllexport) extern"
endif

include $(GNUSTEP_MAKEFILES)/framework.make
