/*---------------------------------------------------------------------------------------------
 *  UDSQLConditionCell.h
 *
 *  A condition's cell (the browser's, a query by example's skeletons'): its
 *  text, and at its right a ▾ for what can be asked (its menu, its
 *  controller's); an empty one shows what may be typed, dimmed (its
 *  placeholder).
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDSQLConditionCell : NSTextFieldCell
/// How wide its ▾ is, at its right: a click there is on it.
+ (CGFloat)menuWidth;
@end

NS_ASSUME_NONNULL_END
