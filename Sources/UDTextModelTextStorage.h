/*---------------------------------------------------------------------------------------------
 *  UDTextModelTextStorage.h — NSTextStorage backed by UDTextModel.
 *
 *  Edits flow through UDTextModel (enabling undo/redo and interval-tree
 *  decoration tracking).  Search-match highlights are applied as
 *  NSBackgroundColorAttributeName attributes derived from the model's "find" owner
 *  decorations.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDPieceTable/UDPieceTable.h>

NS_ASSUME_NONNULL_BEGIN

/// Owner string used when registering search-match decorations via deltaDecorations.
extern NSString * const UDFindDecorationOwner;

@interface UDTextModelTextStorage : NSTextStorage

/// The underlying text model.  Use this to run searches, manipulate decorations, etc.
@property (nonatomic, readonly, strong) UDTextModel *textModel;

/// Creates a new text storage initialised with the given text.
- (instancetype)initWithText:(NSString *)initialText;

/// Recomputes all "find" decoration background-color attributes from the model and
/// schedules a layout pass.  Call this after a batch of deltaDecorations changes.
- (void)applyDecorationHighlights;

@end

NS_ASSUME_NONNULL_END
