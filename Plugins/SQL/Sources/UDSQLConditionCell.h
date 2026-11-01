/*---------------------------------------------------------------------------------------------
 *  UDSQLConditionCell.h
 *
 *  A condition's cell (a query by example's skeletons'): its text, and at
 *  its right a ▾ for what can be asked (its menu, its controller's); an
 *  empty one shows what may be typed, dimmed (its placeholder). Its text,
 *  being edited, is coloured as it is typed (UDSQLExampleTextStorage in
 *  the field editor, its own storage given back after).
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDSQLConditionCell : NSTextFieldCell
/// How wide its ▾ is, at its right: a click there is on it.
+ (CGFloat)menuWidth;
@end

NS_ASSUME_NONNULL_END
