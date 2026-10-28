//
//  UDCodeKit.h
//
//  A code editor for AppKit and GNUstep: the text storage over UDPieceTable's
//  text model, the editor view controller with its gutters, folding and
//  auto-indentation, tree-sitter highlighting, language modes loaded from
//  grammar bundles, the language server client, and the debugger (a debug
//  adapter's client, with Xcode's breakpoints, debug bar, debug navigator,
//  breakpoint navigator and debug area, and VS Code's conditions, logpoints,
//  watches and debug hover).
//

#import <Cocoa/Cocoa.h>
#import <UDPieceTable/UDPieceTable.h>

#import <UDCodeKit/UDTreeSitterTypes.h>
#import <UDCodeKit/UDTextModelString.h>
#import <UDCodeKit/UDTextModelTextStorage.h>
#import <UDCodeKit/UDTreeSitterHighlighter.h>
#import <UDCodeKit/UDDecorationHighlighter.h>
#import <UDCodeKit/UDDecorationLayerRegistry.h>
#import <UDCodeKit/UDSyntaxHighlighter.h>
#import <UDCodeKit/UDBracketMatchHighlighter.h>
#import <UDCodeKit/UDLSPDiagnosticHighlighter.h>
#import <UDCodeKit/TreeSitterTheme.h>

#import <UDCodeKit/UDDiagnosticItem.h>
#import <UDCodeKit/UDDiagnosticStore.h>
#import <UDCodeKit/UDLanguageKeyHandler.h>
#import <UDCodeKit/UDExtension.h>
#import <UDCodeKit/UDLanguageConfiguration.h>
#import <UDCodeKit/UDLanguageMode.h>
#import <UDCodeKit/UDLanguageModeRegistry.h>
#import <UDCodeKit/UDCodeDocument.h>

#import <UDCodeKit/UDTextModel+LSPTextBuffer.h>
#import <UDCodeKit/UDLSPCoordinator.h>

#import <UDCodeKit/UDAutoIndenter.h>
#import <UDCodeKit/UDStructuredNavigator.h>
#import <UDCodeKit/UDCodeEditorLayoutManager.h>
#import <UDCodeKit/UDLineNumberGutterView.h>
#import <UDCodeKit/UDFindResultsGutterView.h>
#import <UDCodeKit/UDFoldingController.h>
#import <UDCodeKit/UDDiagnosticTextView.h>
#import <UDCodeKit/UDCodeEditorViewController.h>
#import <UDCodeKit/UDEditorSession.h>
#import <UDCodeKit/UDFindModel.h>
#import <UDCodeKit/UDFindBarViewController.h>

#import <UDCodeKit/UDTabBarView.h>
#import <UDCodeKit/UDTabItemView.h>
#import <UDCodeKit/UDEditorTabsController.h>
#import <UDCodeKit/UDPaneSplitController.h>
#import <UDCodeKit/UDCompletionListController.h>
#import <UDCodeKit/UDErrorsViewController.h>
#import <UDCodeKit/UDHoverViewController.h>
#import <UDCodeKit/UDPlaceholderHighlighter.h>

#import <UDCodeKit/UDBreakpointStore.h>
#import <UDCodeKit/UDDebugSession.h>
#import <UDCodeKit/UDDebugBarViewController.h>
#import <UDCodeKit/UDDebugNavigatorViewController.h>
#import <UDCodeKit/UDDebugAreaViewController.h>
#import <UDCodeKit/UDBreakpointNavigatorViewController.h>
#import <UDCodeKit/UDBreakpointEditorViewController.h>
#import <UDCodeKit/UDDebugHoverViewController.h>
#import <UDCodeKit/UDDebugger.h>
#import <UDCodeKit/UDTestRunner.h>
#import <UDCodeKit/UDCommandTestRunner.h>
#import <UDCodeKit/UDBuildSystem.h>
#import <UDCodeKit/UDTestNavigatorViewController.h>
#import <UDCodeKit/UDTests.h>
#import <UDCodeKit/UDSemanticTokensHighlighter.h>
#import <UDCodeKit/UDTerminalViewController.h>
#import <UDCodeKit/UDTerminalView.h>
#import <UDCodeKit/UDPseudoTerminal.h>
#import <UDCodeKit/UDShell.h>
#import <UDCodeKit/UDPaths.h>
#import <UDCodeKit/UDIssuePopupController.h>
#import <UDCodeKit/UDLinkedEditing.h>
#import <UDCodeKit/UDOpenQuicklyController.h>
#import <UDCodeKit/UDOccurrencesHighlighter.h>
#import <UDCodeKit/UDSearchResultsViewController.h>
#import <UDCodeKit/UDWorkspaceEdit.h>
#import <UDCodeKit/UDTasks.h>
#import <UDCodeKit/UDFileWatcher.h>
#import <UDCodeKit/UDProjectSettingsController.h>
#import <UDCodeKit/UDPreferencesController.h>
#import <UDCodeKit/UDBuildLogViewController.h>
#import <UDCodeKit/UDBuildRunner.h>
#import <UDCodeKit/UDFileNavigatorViewController.h>
#import <UDCodeKit/UDToolLocator.h>
#import <UDCodeKit/UDProject.h>
