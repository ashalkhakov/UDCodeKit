/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleSyntax.h
 *
 *  What is typed in a query by example (a skeleton's entry, a condition
 *  box's line), coloured and explained: its short names said in words.
 *
 *  As RDLKit's and XFormsKit's expressions are: the engine says what a run
 *  of text is (+[UDSQLExampleCondition highlightTokensForString:], the
 *  lexer the condition box is read with: no second tokenizer to keep in
 *  step), and this what each kind looks like — the same palette as
 *  XFormsKit's XPath (XFDXPathTokenColor). Text only shown (a cell) is a
 *  plain attributed string; text edited is UDSQLExampleTextStorage's,
 *  which recolours itself on every change.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The colour a token's kind is drawn in: a named system colour where the
/// SDK has it (keeping contrast in a dark appearance), else a fixed one.
/// function (an aggregate) purple, variable (an element) teal, command
/// (P. G.) brown, string red, number blue, operator orange, punct dimmed,
/// name the text's own.
FOUNDATION_EXPORT NSColor *UDSQLExampleTokenColor(NSString *kind);

/// @a text coloured, as a plain attributed string, for where it is only
/// shown (a skeleton's cell); edited, UDSQLExampleTextStorage colours it.
FOUNDATION_EXPORT NSAttributedString *UDSQLExampleAttributedString(NSString *text, NSFont *_Nullable font);

/// What a skeleton's entry @a text means, a line of each of its parts
/// ("P. — printed: a column of the answer"…); nil when it is empty.
FOUNDATION_EXPORT NSString *_Nullable UDSQLExampleExplanation(NSString *text);
/// What the condition box takes, a line each.
FOUNDATION_EXPORT NSString *UDSQLExampleConditionHelp(void);

NS_ASSUME_NONNULL_END
