/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleTextStorage.h
 *
 *  Text being edited as a query by example's (the condition box, a
 *  skeleton's cell being typed in), which recolours itself as it is typed.
 *
 *  Colouring belongs in the storage rather than in a -textDidChange: or a
 *  pass afterwards, because the storage is told about every change to the
 *  text — a paste, an undo, AppKit re-applying a control's own attributes
 *  — which a delegate doesn't all hear about, and colours set after the
 *  fact are lost when the field editor resets its typing attributes.
 *
 *  Ported from XFormsKit's XFDXPathTextStorage (itself RDLKit's
 *  RDLExpressionTextStorage's); the tokens are the engine's
 *  (+[UDSQLExampleCondition highlightTokensForString:]).
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDSQLExampleTextStorage : NSTextStorage

/// What the whole text starts from before token colours are laid over it.
@property (nonatomic, copy) NSDictionary<NSString *, id> *baseAttributes;

/// Takes over @a view's layout manager and answers the storage now behind
/// it, or nil if the view would not give it up. Anything already in the
/// view is carried across.
+ (nullable instancetype)installedInTextView:(NSTextView *)view;

@end

NS_ASSUME_NONNULL_END
