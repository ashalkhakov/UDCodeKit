//
//  AppDelegate.h
//  UDPieceTable
//
//  Created by Artyom Shalkhakov on 01.03.2026.
//

#import <Cocoa/Cocoa.h>
#import "UDFindResultsGutterView.h"
#import "UDLineNumberGutterView.h"
#import "UDFoldingController.h"
#import "UDBracketMatchHighlighter.h"
#import "UDMissingNodeHighlighter.h"
#import "UDStructuredNavigator.h"
#import "UDAutoIndenter.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSSearchFieldDelegate,
                                   UDLineNumberGutterViewDelegate>

@property (nonatomic, weak) IBOutlet NSTextView *textView;

/// Search field added programmatically at the top of the window.
@property (nonatomic, strong) NSSearchField *findField;

/// Gutter view added programmatically to the right of the scroll view.
@property (nonatomic, strong) UDFindResultsGutterView *gutterView;

/// Line-number gutter view to the left of the scroll view.
@property (nonatomic, strong) UDLineNumberGutterView *lineNumberGutterView;

/// Folding controller.
@property (nonatomic, strong) UDFoldingController *foldingController;

/// Bracket-match highlighter.
@property (nonatomic, strong) UDBracketMatchHighlighter *bracketMatchHighlighter;

/// MISSING-node pill highlighter.
@property (nonatomic, strong) UDMissingNodeHighlighter *missingNodeHighlighter;

/// Structured (tree) navigator.
@property (nonatomic, strong) UDStructuredNavigator *structuredNavigator;

/// Tree-sitter-driven auto-indenter.
@property (nonatomic, strong) UDAutoIndenter *autoIndenter;

@end

