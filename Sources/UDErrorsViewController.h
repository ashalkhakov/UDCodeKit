/*---------------------------------------------------------------------------------------------
 *  UDErrorsViewController.h
 *
 *  Displays a multi-file NSOutlineView of diagnostics, modelled after Xcode's
 *  Issue Navigator:
 *
 *    ▼ schema.json  (2 errors)
 *        Line 4: Unexpected token
 *        Line 7: Missing "}"
 *    ▼ config.json
 *    ▼ Untitled
 *
 *  Level 0 — one expandable row per open document (display name + store provided
 *             by the caller).
 *  Level 1 — individual diagnostics for that document.
 *
 *  The view is built entirely in code — no XIB.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDDiagnosticStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDErrorsViewController : NSViewController <NSOutlineViewDataSource,
                                                      NSOutlineViewDelegate>

/// Replace the full list of (store, displayName) pairs shown in the panel.
///
/// Duplicate stores are de-duplicated (first occurrence wins).  The outline
/// shows one top-level row per unique store, each expandable to its
/// diagnostics.  Existing notification subscriptions are cleaned up and new
/// ones are registered atomically.
///
/// Pass empty arrays to clear the panel.
- (void)setStores:(NSArray<UDDiagnosticStore *> *)stores
     displayNames:(NSArray<NSString *> *)displayNames;

@end

NS_ASSUME_NONNULL_END
