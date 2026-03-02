/*---------------------------------------------------------------------------------------------
 *  UDErrorsViewController.h
 *
 *  Displays a two-level NSOutlineView of TreeSitter parse errors, modelled
 *  after Xcode's Issue Navigator:
 *
 *    ▼ current.json  (N errors)
 *        Line 4: Unexpected token
 *        Line 7: Missing "}"
 *
 *  Level 0 — the source file (always "current.json").
 *  Level 1 — individual parse errors (ERROR + MISSING tree-sitter nodes).
 *
 *  Call -update after every parse to refresh the list.
 *  The view is built entirely in code — no XIB.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDTreeSitterHighlighter.h"
#import "UDParseErrorItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDErrorsViewController : NSViewController <NSOutlineViewDataSource,
                                                      NSOutlineViewDelegate>

- (instancetype)initWithHighlighter:(UDTreeSitterHighlighter *)highlighter;

/// Re-scan the current parse tree and refresh the outline view.
- (void)update;

/// The errors found during the last -update call.
/// Callers (e.g. AppDelegate) use this array to compute gutter tick positions.
@property (nonatomic, readonly, copy) NSArray<UDParseErrorItem *> *errors;

@end

NS_ASSUME_NONNULL_END
