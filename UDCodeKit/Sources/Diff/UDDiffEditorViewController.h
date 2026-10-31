/*---------------------------------------------------------------------------------------------
 *  UDDiffEditorViewController.h
 *
 *  VS Code's diff editor, side by side: two code editors, the original
 *  (read-only unless originalEditable) and the modified, over their own text
 *  storages, which they may share with other tabs. The diff is computed
 *  (UDLinesDiffComputer) when they are shown and a moment after either
 *  changes; each editor draws it, and only it does: changed lines' and
 *  characters' backgrounds (removed red, inserted green), and blank, hatched
 *  space where the other side has more, so that the lines that correspond
 *  are side by side (VS Code's computeRangeAlignment). They scroll together.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDPieceTable/UDPieceTable.h>

NS_ASSUME_NONNULL_BEGIN

@class UDCodeEditorViewController, UDTextModelTextStorage, UDLanguageMode;

/// Posted, the diff editor the object, when its diff has been computed again.
FOUNDATION_EXPORT NSNotificationName const UDDiffEditorDidUpdateDiffNotification;

@interface UDDiffEditorViewController : NSViewController

- (instancetype)initWithOriginalTextStorage:(UDTextModelTextStorage *)original
                        modifiedTextStorage:(UDTextModelTextStorage *)modified;
/// Xcode's Code Review of a file: @a modifiedEditor, its tab's, is the
/// modified side (with all it is: its caret, its undo, its find bar) and the
/// diff's view takes its place; -invalidate gives it back.
- (instancetype)initWithOriginalTextStorage:(UDTextModelTextStorage *)original
                             modifiedEditor:(UDCodeEditorViewController *)modifiedEditor;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// The two sides (which is left: modifiedOnLeft).
@property (nonatomic, strong, readonly) UDCodeEditorViewController *originalEditor;
@property (nonatomic, strong, readonly) UDCodeEditorViewController *modifiedEditor;

/// The modified side on the left, the original on the right (Xcode's order:
/// yours, then what it was); else VS Code's. Set before the view loads.
@property (nonatomic) BOOL modifiedOnLeft;

/// The original's text may be edited (VS Code's originalEditable): NO.
@property (nonatomic) BOOL originalEditable;

/// A line's leading and trailing white space is no change (VS Code's
/// diffEditor.ignoreTrimWhitespace): YES.
@property (nonatomic) BOOL ignoreTrimWhitespace;

/// Its decorations, view zones and observers gone; an editor it was given
/// out of its view, as it was. Its view shows nothing more.
- (void)invalidate;

/// Both editors in @a mode (an editor it was given is left as it is).
- (void)configureForLanguageMode:(UDLanguageMode *)mode;

/// The diff shown: its changes, in the texts' order.
@property (nonatomic, strong, readonly, nullable) UDLinesDiff *diff;

/// Computes the diff now (rather than a moment after an edit), and shows it.
- (void)computeDiff;

/// The editor the user is in: the original when its text view has the
/// focus, else the modified (VS Code's active editor of a diff editor).
@property (nonatomic, readonly) UDCodeEditorViewController *activeEditor;

/// The caret at the start of the next change (after the caret's line, round
/// to the first), or the previous one, in the active editor: VS Code's Go to
/// Next / Previous Change (⌥F5, ⇧⌥F5).
- (IBAction)goToNextChange:(nullable id)sender;
- (IBAction)goToPreviousChange:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
