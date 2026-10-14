//
//  UDCodeKit.h
//
//  A code editor for AppKit and GNUstep: the text storage over UDPieceTable's
//  text model, the editor view controller with its gutters, folding and
//  auto-indentation, tree-sitter highlighting, language modes loaded from
//  grammar bundles, and the language server client.
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
#import <UDCodeKit/UDTextEditorViewController.h>
#import <UDCodeKit/UDEditorSession.h>
