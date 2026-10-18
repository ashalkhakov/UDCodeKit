/*---------------------------------------------------------------------------------------------
 *  UDBreakpointNavigatorViewController.h
 *
 *  Xcode's breakpoint navigator, with what VS Code's BREAKPOINTS section
 *  has: the exception filters the adapter offers (when it offers any, as
 *  VS Code lists them first), then every breakpoint, by file,
 *
 *    ☑ Errors
 *    ☐ Warnings
 *    ▼ script.script
 *        ☑ Line 12
 *        ☐ Line 30  ·  Condition: i > 2
 *        ☑ Line 41  ·  Log: i is {i}
 *    ▶ other.script
 *    ─────────────────────────────
 *    −
 *
 *  a check box each to turn it on or off (setExceptionBreakpoints, or the
 *  breakpoint enabled), a breakpoint the adapter could not bind grey (why,
 *  in its tooltip). A double click shows a breakpoint's line (the
 *  delegate's); its menu edits it (Edit Breakpoint…, the delegate's: the
 *  editor's box), enables or disables it, deletes it, and enables,
 *  disables or deletes every one; − deletes the selected one.
 *
 *  Laid out in UDBreakpointNavigator.xib. A host puts its view in its
 *  navigator (Xcode's ⌘8) and gives it the window's UDBreakpointStore.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDBreakpointStore.h"

NS_ASSUME_NONNULL_BEGIN

@class UDBreakpointNavigatorViewController;

@protocol UDBreakpointNavigatorDelegate <NSObject>
@optional
/// A breakpoint chosen (a double click): show its file at its line.
- (void)breakpointNavigator:(UDBreakpointNavigatorViewController *)navigator showBreakpoint:(UDBreakpoint *)breakpoint;
/// Edit Breakpoint…: show its file, and its editor's box for it
/// (UDCodeEditorViewController's -editBreakpointAtLine:).
- (void)breakpointNavigator:(UDBreakpointNavigatorViewController *)navigator editBreakpoint:(UDBreakpoint *)breakpoint;
@end

@interface UDBreakpointNavigatorViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate,
                                                                   NSMenuDelegate>

- (instancetype)init;

@property (nonatomic, strong, nullable) UDBreakpointStore *breakpoints;
@property (nonatomic, weak, nullable) id<UDBreakpointNavigatorDelegate> delegate;

/// The exception filters, the files, their breakpoints; columns "enabled"
/// (a check box) and "breakpoint".
@property (nonatomic, weak, readonly) IBOutlet NSOutlineView *outlineView;
@property (nonatomic, weak, readonly) IBOutlet NSButton *removeButton;

/// What a row shows: a breakpoint, an exception filter (its id), or neither
/// (a file).
- (nullable UDBreakpoint *)breakpointOfRow:(NSInteger)row;
- (nullable NSString *)exceptionFilterOfRow:(NSInteger)row;

/// The clicked (or selected) breakpoint: shown, edited, enabled or
/// disabled, deleted.
- (IBAction)showBreakpoint:(nullable id)sender;
- (IBAction)editBreakpoint:(nullable id)sender;
- (IBAction)toggleBreakpointEnabled:(nullable id)sender;
- (IBAction)deleteBreakpoint:(nullable id)sender;
/// Every breakpoint.
- (IBAction)enableAllBreakpoints:(nullable id)sender;
- (IBAction)disableAllBreakpoints:(nullable id)sender;
- (IBAction)deleteAllBreakpoints:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
