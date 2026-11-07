/*---------------------------------------------------------------------------------------------
 *  UDTreeView.h
 *
 *  A tree of an extension's own, as VS Code's tree views are its extensions'
 *  (TreeDataProvider, TreeItem, createTreeView): what is in it the
 *  extension's elements, any objects; each shown as the UDTreeItem its
 *  provider makes of it, and its children asked for when it is first
 *  expanded (never the whole tree). A project system's view of a project
 *  (VS Code's Solution Explorer: a solution's projects and their items; a
 *  game's decls, by type and name), beside the files' (UDFileNavigator).
 *
 *  An extension gives it as its navigator (-[UDExtension
 *  navigatorViewControllerForWorkbench:]). Choosing an element runs its
 *  item's command (VS Code's TreeItem.command): an action sent to a target,
 *  the tree view's own -openResource: (VS Code's vscode.open) to open its
 *  resourceURL in the window (-[UDWorkbench showURL:]: a file, or a URL of
 *  the extension's own scheme, UDFileSystemProvider.h). Its context
 *  menu is its provider's, from a XIB of its own. Laid out in UDTreeView.xib:
 *  the outline, and below it a filter field when the provider filters.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UDTreeViewController;
@protocol UDWorkbench;

/// Whether an item has children, and is shown with them (VS Code's
/// TreeItemCollapsibleState).
typedef NS_ENUM(NSInteger, UDTreeItemCollapsibleState) {
    UDTreeItemCollapsibleStateNone,        // a leaf
    UDTreeItemCollapsibleStateCollapsed,   // has children, shown closed
    UDTreeItemCollapsibleStateExpanded,    // has children, shown open
};

/// How an element is shown (VS Code's TreeItem).
@interface UDTreeItem : NSObject
+ (instancetype)itemWithLabel:(NSString *)label;
@property (nonatomic, copy) NSString *label;
/// Dimmer, at the row's right (VS Code's description): a decl's pak, say.
@property (nonatomic, copy, nullable) NSString *detail;
@property (nonatomic, copy, nullable) NSString *toolTip;
/// Before the label, 16 points square (VS Code's iconPath).
@property (nonatomic, strong, nullable) NSImage *image;
/// The resource it stands for (VS Code's resourceUri): what -openResource:
/// opens. Not opened when it is chosen unless its command says so.
@property (nonatomic, copy, nullable) NSURL *resourceURL;
/// Its command (VS Code's TreeItem.command): @a action sent when it is
/// chosen (clicked, or Return), with the tree view as the sender (its
/// -chosenElement the element); to @a target, or with no target to the tree
/// view itself (-openResource:). No action: choosing it does nothing, but a
/// double click opens or closes it.
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;
@property (nonatomic) UDTreeItemCollapsibleState collapsibleState;
/// What it is the same as after a refresh, for what was expanded and
/// selected (VS Code's id); nil: its label, under its parent's.
@property (nonatomic, copy, nullable) NSString *identifier;
@end

/// What is in the tree (VS Code's TreeDataProvider).
@protocol UDTreeDataProvider <NSObject>

/// The elements under @a element; nil element: the tree's top (getChildren).
- (NSArray *)treeView:(UDTreeViewController *)treeView childrenOfElement:(nullable id)element;

/// How @a element is shown (getTreeItem).
- (UDTreeItem *)treeView:(UDTreeViewController *)treeView itemForElement:(id)element;

@optional

/// The element @a element is under, nil at the top (getParent): what
/// -revealElement: needs.
- (nullable id)treeView:(UDTreeViewController *)treeView parentOfElement:(id)element;

/// The context menu of @a elements (those selected, or the one clicked;
/// VS Code's view/item/context), from a XIB of the provider's; nil: none.
- (nullable NSMenu *)treeView:(UDTreeViewController *)treeView menuForElements:(NSArray *)elements;

/// The filter field's text changed (empty: no filter): the provider then
/// gives only what matches, and calls -refresh. Implemented: the field is
/// shown.
- (void)treeView:(UDTreeViewController *)treeView filterDidChange:(NSString *)filter;

@end

/// The tree's view (VS Code's TreeView).
@interface UDTreeViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>

/// The tree of @a provider, in @a workbench's window (what its choices open
/// in), its title @a title (the navigator's segment's tool tip).
- (instancetype)initWithDataProvider:(id<UDTreeDataProvider>)provider
                           workbench:(nullable id<UDWorkbench>)workbench
                               title:(NSString *)title;

@property (nonatomic, weak, readonly, nullable) id<UDTreeDataProvider> dataProvider;
@property (nonatomic, weak, readonly, nullable) id<UDWorkbench> workbench;

@property (nonatomic, weak, readonly) IBOutlet NSOutlineView *outlineView;
@property (nonatomic, weak, readonly) IBOutlet NSSearchField *filterField;

/// The whole tree asked for again (VS Code's onDidChangeTreeData with no
/// element), what was expanded and selected kept so.
- (void)refresh;
/// @a element and what is under it asked for again (nil: the whole tree).
- (void)refreshElement:(nullable id)element;

/// The elements selected.
@property (nonatomic, readonly) NSArray *selectedElements;
/// @a element shown (what it is under expanded: the provider's
/// -treeView:parentOfElement:) and selected; NO when it can't be found.
- (BOOL)revealElement:(id)element;

/// The element whose item's command is being sent; nil otherwise.
@property (nonatomic, readonly, nullable) id chosenElement;

/// The selected element chosen, as a click chooses it: its command sent, or,
/// with none, it opened or closed.
- (IBAction)chooseSelectedElement:(nullable id)sender;
/// The chosen element's item's resourceURL shown in the window (VS Code's
/// vscode.open): a command for an item's action.
- (IBAction)openResource:(nullable id)sender;
/// The filter field's text given to the provider.
- (IBAction)filterChanged:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
