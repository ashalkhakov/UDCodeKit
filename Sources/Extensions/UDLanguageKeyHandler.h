/*---------------------------------------------------------------------------------------------
 *  UDLanguageKeyHandler.h  —  Protocol for language-specific keyboard handling.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDPieceTable.h>
#import <UDPieceTable/UDCursorsController.h>

NS_ASSUME_NONNULL_BEGIN

@protocol UDLanguageKeyHandler <NSObject>

@optional

/// Called when the user types a single printable character, AFTER the base
/// UDAutoIndenter has had a chance to process the event.
///
/// The handler reads current cursor positions from cursorsController.selections
/// and writes back new positions the same way. It does not need to return a
/// cursor offset — the controller's state is the cursor state.
///
/// Return YES if the event was consumed; NO to fall through to NSTextView default.
- (BOOL)handleTypedCharacter:(NSString *)chars
                   parseTree:(nullable const void *)parseTree
                   textModel:(UDTextModel *)model
           cursorsController:(UDCursorsController *)cursorsController;

/// Called when the user presses a deletion key, BEFORE the default deletion.
///
/// Return YES if the event was consumed (handler applied the deletion itself).
/// Return NO to let the default deletion proceed.
- (BOOL)handleDeleteRange:(NSRange)deleteRange
                parseTree:(nullable const void *)parseTree
                textModel:(UDTextModel *)model
        cursorsController:(UDCursorsController *)cursorsController;

@end

NS_ASSUME_NONNULL_END
