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
#import "UDDiagnosticStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDErrorsViewController : NSViewController <NSOutlineViewDataSource,
                                                      NSOutlineViewDelegate>

- (instancetype)initWithDiagnosticStore:(UDDiagnosticStore *)store;

@end

NS_ASSUME_NONNULL_END
