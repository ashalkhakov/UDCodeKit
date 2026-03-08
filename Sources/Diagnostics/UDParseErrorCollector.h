//
//  UDParseErrorCollector.h
//  TestApp
//
//  Created by artyom on 3/8/26.
//


#import "UDIncrementalHighlighterBase.h"
#import "UDDiagnosticStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Walks the tree-sitter parse tree (incrementally or fully) to collect
/// ERROR and MISSING nodes and writes them as UDDiagnosticSourceParser
/// diagnostics into a UDDiagnosticStore.
///
/// This class produces NO decorations — it inherits UDIncrementalHighlighterBase
/// purely for its incremental walk infrastructure.  -decorationOwner returns
/// an owner that is never written to the model.
@interface UDParseErrorCollector : UDIncrementalHighlighterBase

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter
                               store:(UDDiagnosticStore *)store NS_DESIGNATED_INITIALIZER;

// Parent designated initialiser is unavailable; use the one above.
- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
