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
#import <UDCodeKit/UDCodeKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UDErrorsViewController;

/// Delegate protocol for UDErrorsViewController.
/// Implement to respond when the user selects a diagnostic item in the panel.
@protocol UDErrorsViewControllerDelegate <NSObject>
@optional

/// Called when the user selects an individual diagnostic item in the panel.
///
/// The delegate is responsible for navigating the editor to the location
/// described by @a diagnostic (switching tabs if necessary, scrolling to line).
///
/// @param vc          The errors view controller that sent this message.
/// @param diagnostic  The selected diagnostic item.
/// @param store       The diagnostic store that owns the item (identifies the document).
- (void)errorsViewController:(UDErrorsViewController *)vc
         didSelectDiagnostic:(UDDiagnosticItem *)diagnostic
                     inStore:(UDDiagnosticStore *)store;

@end

@interface UDErrorsViewController : NSViewController <NSOutlineViewDataSource,
                                                      NSOutlineViewDelegate>

/// Delegate that receives navigation requests when the user clicks a diagnostic.
@property (nonatomic, weak, nullable) id<UDErrorsViewControllerDelegate> delegate;

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
