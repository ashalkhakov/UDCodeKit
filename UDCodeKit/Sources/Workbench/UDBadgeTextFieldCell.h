/*---------------------------------------------------------------------------------------------
 *  UDBadgeTextFieldCell.h
 *
 *  A navigator row's text with a badge at its right: Xcode's source-control
 *  letter (M, A, ?, ...), small and grey, the text cut short before it. A
 *  longer badge (a table's entities) yields to the text: what the row has
 *  left, cut short with an ellipsis, or none. An image may come before the
 *  text (a tree item's).
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDBadgeTextFieldCell : NSTextFieldCell

/// The badge drawn at the right; nil: none.
@property (nonatomic, copy, nullable) NSString *badge;
/// Its colour: the secondary label colour unless set.
@property (nonatomic, strong, nullable) NSColor *badgeColor;
/// An image before the text (a tree item's, 16 points square); nil: none.
@property (nonatomic, strong, nullable) NSImage *leadingImage;

@end

NS_ASSUME_NONNULL_END
