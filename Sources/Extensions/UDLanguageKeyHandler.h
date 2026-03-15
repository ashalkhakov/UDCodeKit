/*---------------------------------------------------------------------------------------------
 *  UDLanguageKeyHandler.h  —  Protocol for language-specific keyboard handling.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDPieceTable.h>
#import <UDPieceTable/UDCursorsController.h>

NS_ASSUME_NONNULL_BEGIN

@protocol UDLanguageKeyHandler <NSObject>

@optional

/// Called when the user types a single printable character, BEFORE the base
/// UDAutoIndenter electric-pair logic runs.
///
/// The handler reads current cursor positions from cursorsController.selections
/// and writes back new positions the same way.
///
/// Return YES if the event was consumed; NO to fall through to the default
/// electric-pair logic.
- (BOOL)handleTypedCharacter:(NSString *)chars
                   parseTree:(nullable const void *)parseTree
                   textModel:(UDTextModel *)model
           cursorsController:(UDCursorsController *)cursorsController;

/// Called when the user presses a deletion key (⌫ or ⌦), BEFORE the default
/// deletion.
///
/// Return YES if the event was consumed (handler applied the deletion itself).
/// Return NO to let the default deletion proceed.
- (BOOL)handleDeleteRange:(NSRange)deleteRange
                parseTree:(nullable const void *)parseTree
                textModel:(UDTextModel *)model
        cursorsController:(UDCursorsController *)cursorsController;

/// Called when the user presses Return / KP-Return, BEFORE the base
/// UDAutoIndenter smart-indentation logic runs.
///
/// Return YES if the event was consumed (handler inserted its own newline).
/// Return NO to let the default smart-indentation proceed.
- (BOOL)handleReturnKeyWithParseTree:(nullable const void *)parseTree
                           textModel:(UDTextModel *)model
                   cursorsController:(UDCursorsController *)cursorsController;

/// Called when the user presses Tab (no modifiers), BEFORE the default
/// tab-insert / indent logic.
///
/// Return YES if the event was consumed.
/// Return NO to let the default Tab behaviour proceed.
- (BOOL)handleTabKeyWithParseTree:(nullable const void *)parseTree
                        textModel:(UDTextModel *)model
                cursorsController:(UDCursorsController *)cursorsController;

/// Called when the user presses Shift-Tab, BEFORE the base de-indent logic.
///
/// Return YES if the event was consumed.
/// Return NO to let the default Shift-Tab de-indent proceed.
- (BOOL)handleShiftTabKeyWithParseTree:(nullable const void *)parseTree
                             textModel:(UDTextModel *)model
                     cursorsController:(UDCursorsController *)cursorsController;

@end

NS_ASSUME_NONNULL_END
