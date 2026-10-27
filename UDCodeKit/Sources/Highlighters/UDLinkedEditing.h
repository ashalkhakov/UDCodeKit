/*---------------------------------------------------------------------------------------------
 *  UDLinkedEditing.h
 *
 *  Places in a text edited together, as Xcode's Rename edits a symbol where
 *  it stands: each place outlined, the first selected; what is typed in it
 *  is copied to the others as it is typed. Return (or the caret leaving the
 *  first place, or an edit elsewhere) ends it as it is; Escape puts back
 *  what was there. The delegate hears which.
 *--------------------------------------------------------------------------------------------*/

#import "UDDecorationHighlighter.h"

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

UDCODEKIT_EXPORT NSString * const UDLinkedEditingDecorationOwner;

@class UDLinkedEditing;

@protocol UDLinkedEditingDelegate <NSObject>
/// Ended: @a text is in every place now (the original's, when cancelled).
- (void)linkedEditing:(UDLinkedEditing *)editing didEndWithText:(NSString *)text cancelled:(BOOL)cancelled;
@end

@interface UDLinkedEditing : UDDecorationHighlighter

/// @a ranges: character ranges of @a textView's text, each holding the same
/// text; the first is the one typed in.
- (instancetype)initWithTextView:(NSTextView *)textView
                     textStorage:(UDTextModelTextStorage *)textStorage
                          ranges:(NSArray<NSValue *> *)ranges;

@property (nonatomic, weak, nullable) id<UDLinkedEditingDelegate> delegate;

/// Outlines the places, selects the first, and follows what is typed.
- (void)begin;
/// Ends it, as it is (Return).
- (void)commit;
/// Ends it, what was there put back (Escape).
- (void)cancel;
@property (nonatomic, readonly, getter=isActive) BOOL active;

/// The places, as they are now.
@property (nonatomic, readonly, copy) NSArray<NSValue *> *ranges;
/// What the first place holds now.
@property (nonatomic, readonly, copy) NSString *text;
/// What every place held at the start.
@property (nonatomic, readonly, copy) NSString *originalText;

@end

NS_ASSUME_NONNULL_END
