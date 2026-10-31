/*---------------------------------------------------------------------------------------------
 *  UDJumpBarView.h
 *
 *  Xcode's jump bar (VS Code's breadcrumbs) over an editor: a row of
 *  segments — the project, its folders, the file, the symbols holding the
 *  caret — each an icon and a title, separated by chevrons. A segment
 *  clicked pops the delegate's menu under it (its level's files, the file's
 *  symbols). A symbol's icon is Xcode's: its kind's letter on its colour.
 *  Placed in a XIB (the editor's); drawn by itself.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDDocumentSymbol.h>

NS_ASSUME_NONNULL_BEGIN

@class UDJumpBarView;

/// A segment: a title, with a file's icon or a symbol kind's.
@interface UDJumpBarItem : NSObject
+ (instancetype)itemWithTitle:(NSString *)title image:(nullable NSImage *)image representedObject:(nullable id)object;
+ (instancetype)itemWithTitle:(NSString *)title symbolKind:(UDSymbolKind)kind representedObject:(nullable id)object;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, strong, nullable) NSImage *image;
/// 0: none (a file's image instead).
@property (nonatomic, readonly) UDSymbolKind symbolKind;
@property (nonatomic, readonly, strong, nullable) id representedObject;
@end

@protocol UDJumpBarViewDelegate <NSObject>
/// The menu of the segment at @a index, popped under it; nil: none.
- (nullable NSMenu *)jumpBar:(UDJumpBarView *)jumpBar menuForItemAtIndex:(NSUInteger)index;
@end

@interface UDJumpBarView : NSView

@property (nonatomic, weak, nullable) IBOutlet id<UDJumpBarViewDelegate> delegate;
@property (nonatomic, copy) NSArray<UDJumpBarItem *> *items;

/// The segment at @a index's rect, as drawn (titles of folders may be left
/// out where the bar is narrow, as Xcode does); NSZeroRect when none.
- (NSRect)rectOfItemAtIndex:(NSUInteger)index;
/// The segment at @a index clicked: its menu popped.
- (void)popUpMenuOfItemAtIndex:(NSUInteger)index;

/// Xcode's symbol icon: @a kind's letter, white on its colour, @a size square.
+ (NSImage *)imageOfSymbolKind:(UDSymbolKind)kind size:(CGFloat)size;

@end

NS_ASSUME_NONNULL_END
