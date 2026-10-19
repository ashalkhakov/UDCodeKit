#
# UDCodeKit.framework on GNUstep: the editor. Links UDPieceTable and LSPKit
# (built first, in the tree) and compiles the tree-sitter runtime in.
#
FRAMEWORK_NAME = UDCodeKit

include ../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

UDCodeKit_OBJC_FILES = $(shell find Sources -name '*.m' | sort)
UDCodeKit_C_FILES = ../tree-sitter/src/lib.c $(wildcard ../libvterm/src/*.c)

# The headers sit in subfolders; <UDCodeKit/X.h> needs them in one:
# build/gnustep/include/UDCodeKit holds a link to each (see gnustep.make).
# Made as the makefile is read: gnustep-make copies the headers before any
# before-all rule runs.
UD_HEADER_LINKS := $(shell mkdir -p $(UD_INCLUDE)/UDCodeKit && \
    for h in `find $(CURDIR)/Sources -name '*.h'`; do ln -sfn $$h $(UD_INCLUDE)/UDCodeKit/; done)
UDCodeKit_HEADER_FILES_DIR = $(UD_INCLUDE)/UDCodeKit
UDCodeKit_HEADER_FILES = \
    UDTestNavigatorViewController.h \
    UDTests.h \
    UDSemanticTokensHighlighter.h \
    UDTerminalViewController.h \
    UDTerminalView.h \
    UDPseudoTerminal.h \
    UDIssuePopupController.h \
    UDLinkedEditing.h \
    UDOpenQuicklyController.h \
    UDOccurrencesHighlighter.h \
    UDSearchResultsViewController.h \
    UDWorkspaceEdit.h \
    UDTasks.h \
    UDFileWatcher.h \
    UDProjectSettingsController.h \
    UDBuildLogViewController.h \
    UDBuildRunner.h \
    UDFileNavigatorViewController.h \
    UDToolLocator.h \
    UDProject.h \
    TreeSitterTheme.h \
    UDAutoIndenter.h \
    UDBracketMatchHighlighter.h \
    UDBreakpointEditorViewController.h \
    UDBreakpointNavigatorViewController.h \
    UDBreakpointStore.h \
    UDCodeDocument.h \
    UDCodeEditorLayoutManager.h \
    UDCodeEditorViewController.h \
    UDCodeKit.h \
    UDDebugAreaViewController.h \
    UDDebugBarViewController.h \
    UDDebugHoverViewController.h \
    UDDebugNavigatorViewController.h \
    UDDebugSession.h \
    UDDecorationHighlighter.h \
    UDDecorationLayerRegistry.h \
    UDDiagnosticItem.h \
    UDDiagnosticStore.h \
    UDDiagnosticTextView.h \
    UDEditorSession.h \
    UDErrorsViewController.h \
    UDEditorTabsController.h \
    UDExtension.h \
    UDFindBarViewController.h \
    UDFindModel.h \
    UDFindResultsGutterView.h \
    UDFoldingController.h \
    UDCompletionListController.h \
    UDHoverViewController.h \
    UDLSPCoordinator.h \
    UDLSPDiagnosticHighlighter.h \
    UDLanguageConfiguration.h \
    UDLanguageKeyHandler.h \
    UDLanguageMode.h \
    UDLanguageModeRegistry.h \
    UDLineNumberGutterView.h \
    UDPaneSplitController.h \
    UDPlaceholderHighlighter.h \
    UDStructuredNavigator.h \
    UDSyntaxHighlighter.h \
    UDTabBarView.h \
    UDTabItemView.h \
    UDTextModel+LSPTextBuffer.h \
    UDTextModelString.h \
    UDTextModelTextStorage.h \
    UDTreeSitterHighlighter.h \
    UDTreeSitterTypes.h

UDCodeKit_RESOURCE_FILES = $(shell find Sources -name '*.xib' | sort)

UDCodeKit_INCLUDE_DIRS = -I$(UD_INCLUDE) -I$(UD_INCLUDE)/UDCodeKit \
    -I../tree-sitter/include -I../tree-sitter/src -I../libvterm/include
UDCodeKit_LIB_DIRS = -L$(call UD_FRAMEWORK_LIB,UDPieceTable,UDPieceTable) \
    -L$(call UD_FRAMEWORK_LIB,LSPKit,LSPKit)
UDCodeKit_LIBRARIES_DEPEND_UPON = -lUDPieceTable -lLSPKit $(GUI_LIBS) $(FND_LIBS) $(OBJC_LIBS) \
    -ldispatch -lBlocksRuntime -lutil
# tree-sitter's and libvterm's C want C11 (and C99's features) and their own warnings left alone.
ADDITIONAL_CFLAGS += -std=gnu11 -w

include $(GNUSTEP_MAKEFILES)/framework.make
