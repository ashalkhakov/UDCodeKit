/*---------------------------------------------------------------------------------------------
 *  UDErrorsViewController.h
 *
 *  Displays a two-level NSOutlineView of parse / LSP diagnostics, modelled
 *  after Xcode's Issue Navigator:
 *
 *    ▼ my-file.json  (N errors)
 *        Line 4: Unexpected token
 *        Line 7: Missing "}"
 *
 *  Level 0 — the source file (display name provided by the caller).
 *  Level 1 — individual diagnostics (ERROR + MISSING tree-sitter nodes, LSP items).
 *
 *  The view is built entirely in code — no XIB.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDTreeSitterHighlighter.h"
#import "UDDiagnosticStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDErrorsViewController : NSViewController <NSOutlineViewDataSource,
                                                      NSOutlineViewDelegate>

- (instancetype)initWithDiagnosticStore:(UDDiagnosticStore *)store;

/// Switch the view to show diagnostics from a different store and update the
/// filename shown in the root row of the outline view.
///
/// Removes the existing notification subscription, rebinds to the new store,
/// and reloads the outline view.  Calling with the same store and name is a
/// no-op.  Safe to call before the view has loaded (the reload happens lazily).
- (void)bindToStore:(UDDiagnosticStore *)store displayName:(NSString *)displayName;

@end

NS_ASSUME_NONNULL_END
