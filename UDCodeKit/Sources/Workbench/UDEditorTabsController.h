/*---------------------------------------------------------------------------------------------
 *  UDEditorTabsController.h
 *
 *  Editor tabs: a UDTabBarView over a tabless NSTabView, as one control.
 *  Each tab is a UDTabBarItem (title, dirty dot, pin, the object it shows)
 *  and the view controller whose view the tab view shows for it.
 *
 *  Put one in the window's XIB as an object and connect tabBar, tabView and
 *  delegate; the bar's delegate becomes this controller.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDTabBarView.h"

NS_ASSUME_NONNULL_BEGIN

@class UDEditorTabsController;

@protocol UDEditorTabsControllerDelegate <NSObject>
@optional
/// Whether a tab may close — the place to ask about unsaved changes.
/// Defaults to YES.
- (BOOL)editorTabs:(UDEditorTabsController *)tabs shouldCloseItem:(UDTabBarItem *)item;
- (void)editorTabs:(UDEditorTabsController *)tabs didCloseItem:(UDTabBarItem *)item;
/// The selected tab changed (nil: none left).
- (void)editorTabs:(UDEditorTabsController *)tabs didSelectItem:(nullable UDTabBarItem *)item;
@end

@interface UDEditorTabsController : NSObject <UDTabBarViewDelegate>

@property (nonatomic, weak, nullable) IBOutlet UDTabBarView *tabBar;
@property (nonatomic, weak, nullable) IBOutlet NSTabView *tabView;
@property (nonatomic, weak, nullable) IBOutlet id<UDEditorTabsControllerDelegate> delegate;

/// The tabs in the bar's order.
@property (nonatomic, readonly) NSArray<UDTabBarItem *> *items;
@property (nonatomic, readonly, nullable) UDTabBarItem *selectedItem;

/// Adds a tab showing @a viewController's view, and selects it.
- (UDTabBarItem *)addItemWithTitle:(NSString *)title
                 representedObject:(nullable id)representedObject
                    viewController:(NSViewController *)viewController;

- (nullable NSViewController *)viewControllerForItem:(UDTabBarItem *)item;
- (nullable UDTabBarItem *)itemWithRepresentedObject:(id)representedObject;

- (void)selectItem:(UDTabBarItem *)item;

/// Closes the tab if the delegate agrees (pinned tabs do not close).
/// Returns whether it closed.
- (BOOL)closeItem:(UDTabBarItem *)item;

/// Removes the tab without asking.
- (void)removeItem:(UDTabBarItem *)item;

- (IBAction)closeSelectedTab:(nullable id)sender;
- (IBAction)selectNextTab:(nullable id)sender;
- (IBAction)selectPreviousTab:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
