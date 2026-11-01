/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleSyntax.h
 *
 *  What is typed in a query by example (a skeleton's entry, a condition
 *  box's line), coloured and explained: its short names said in words.
 *
 *    P.  G.                          what a column is to the answer: blue
 *    SUM. AVG. MIN. MAX. CNT.        aggregates, ALL. UNQ.: purple
 *    _c                              example elements: orange
 *    'text'                          brown
 *    = <> < > AND OR NOT IS NULL     dimmed
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// @a text coloured so, in @a font (@a color the rest's).
FOUNDATION_EXPORT NSAttributedString *UDSQLExampleHighlighted(NSString *text, NSFont *font, NSColor *color);
/// @a storage's text coloured so, its font kept (the condition box's, as
/// it is typed).
FOUNDATION_EXPORT void UDSQLExampleHighlight(NSTextStorage *storage);

/// What a skeleton's entry @a text means, a line of each of its parts
/// ("P. — printed: a column of the answer"…); nil when it is empty.
FOUNDATION_EXPORT NSString *_Nullable UDSQLExampleExplanation(NSString *text);
/// What the condition box takes, a line each.
FOUNDATION_EXPORT NSString *UDSQLExampleConditionHelp(void);

NS_ASSUME_NONNULL_END
