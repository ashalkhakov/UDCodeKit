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
    UDDebugger.h \
    UDTestRunner.h \
    UDCommandTestRunner.h \
    UDBuildSystem.h \
    UDTestNavigatorViewController.h \
    UDTests.h \
    UDSemanticTokensHighlighter.h \
    UDTerminalViewController.h \
    UDTerminalView.h \
    UDPseudoTerminal.h \
    UDShell.h \
    UDPaths.h \
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
    -ldispatch $(UD_BLOCKS_LIBS) $(UD_PTY_LIBS)
# tree-sitter's and libvterm's C want C11 (and C99's features) and their own warnings left alone.
ADDITIONAL_CFLAGS += -std=gnu11 -w

# Windows: a DLL exports what it marks, and once the runtime marks its
# classes, its C constants and functions must be marked too: UDCODEKIT_EXPORT
# (in its headers) is "export" while it is built, an import elsewhere.
ifneq ($(UD_WINDOWS),)
UDCodeKit_CPPFLAGS += "-DUDCODEKIT_EXPORT=__declspec(dllexport) extern"
endif

include $(GNUSTEP_MAKEFILES)/framework.make
