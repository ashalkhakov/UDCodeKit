/*---------------------------------------------------------------------------------------------
 *  UDPaneSplitController.h
 *
 *  The Xcode-like layout of a split view's panes: the flexible pane (the
 *  editor) takes every resize, the others (navigator, inspector, a bottom
 *  pane) keep their size; any of those can be hidden and shown again at the
 *  size it had; dragging a divider stops at the panes' minimums; and the
 *  sizes and which panes show are saved under an autosave name.
 *
 *  Put one in the window's XIB as an object, connect its splitView (it
 *  becomes the split view's delegate), and set what differs from the
 *  defaults before the window shows. It lays the panes out itself — on
 *  macOS and on GNUstep, whose -adjustSubviews never asks the delegate
 *  about the last pane — so the XIB's frames need not be right.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

/// Posted when a pane shows or hides; the object is the controller.
UDCODEKIT_EXPORT NSNotificationName const UDPaneSplitControllerDidChangeVisibilityNotification;

@interface UDPaneSplitController : NSObject <NSSplitViewDelegate>

@property (nonatomic, weak, nullable) IBOutlet NSSplitView *splitView;

/// The pane that takes resizes. Defaults to 1: the middle of three.
@property (nonatomic) NSInteger flexiblePaneIndex;

/// Each pane's smallest thickness (width, or height in a horizontal split).
/// Defaults to 160 for every pane but the flexible one, 320 for that.
@property (nonatomic, copy) NSArray<NSNumber *> *minimumThicknesses;

/// The thickness of each pane but the flexible one the first time, before
/// anything is saved. Defaults to 240.
@property (nonatomic, copy) NSArray<NSNumber *> *defaultThicknesses;

/// Saves the panes' sizes and visibility in the user defaults under this
/// name, and restores them in -restoreLayout. Nil: nothing is saved.
@property (nonatomic, copy, nullable) NSString *autosaveName;

/// Restores what was saved (or the defaults) and lays the panes out. Call
/// once the split view is in its window (e.g. in -windowDidLoad).
- (void)restoreLayout;

- (BOOL)isPaneVisible:(NSInteger)index;
- (void)setPane:(NSInteger)index visible:(BOOL)visible;

/// Shows or hides the pane whose index is the sender's tag (a menu item).
- (IBAction)togglePane:(nullable id)sender;

/// The thickness a pane has, or would have when shown.
- (CGFloat)thicknessOfPane:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END
