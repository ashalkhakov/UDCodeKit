/*---------------------------------------------------------------------------------------------
 *  UDBadgeTextFieldCell.h
 *
 *  A navigator row's text with a badge at its right: Xcode's source-control
 *  letter (M, A, ?, ...), small and grey, the text cut short before it.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDBadgeTextFieldCell : NSTextFieldCell

/// The badge drawn at the right; nil: none.
@property (nonatomic, copy, nullable) NSString *badge;
/// Its colour: the secondary label colour unless set.
@property (nonatomic, strong, nullable) NSColor *badgeColor;

@end

NS_ASSUME_NONNULL_END
