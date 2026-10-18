/*---------------------------------------------------------------------------------------------
 *  UDBreakpointEditorViewController.h
 *
 *  A breakpoint's condition, hit count and log message, edited as VS Code's
 *  breakpoint widget edits them: one field at a time, a popup choosing
 *  which (Expression, Hit Count, Log Message); Return keeps all three,
 *  Escape keeps none, and the field losing the keyboard (a click in the
 *  text) keeps them too. What the session's adapter cannot do is greyed in
 *  the popup, as VS Code warns of it.
 *
 *  A box laid over the editor just below the breakpoint's line (where VS
 *  Code opens its widget, and Xcode its popover), as Jump to Line's is
 *  (UDJumpToLineViewController: the keyboard in the editor's own window, on
 *  GNUstep too). Laid out in UDBreakpointEditor.xib;
 *  UDCodeEditorViewController shows it (Edit Breakpoint…, Add Conditional
 *  Breakpoint…, Add Logpoint… in the gutter's menu) and is its delegate.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class UDBreakpointEditorViewController;

/// The popup's items, by tag.
typedef NS_ENUM(NSInteger, UDBreakpointEditorKind) {
    UDBreakpointEditorCondition = 0,
    UDBreakpointEditorHitCondition = 1,
    UDBreakpointEditorLogMessage = 2,
};

@protocol UDBreakpointEditorDelegate <NSObject>
/// Return, or the keyboard gone elsewhere: keep what it has.
- (void)breakpointEditorDidAccept:(UDBreakpointEditorViewController *)editor;
/// Escape.
- (void)breakpointEditorDidCancel:(UDBreakpointEditorViewController *)editor;
@end

@interface UDBreakpointEditorViewController : NSViewController <NSTextFieldDelegate>

/// Loads UDBreakpointEditor.xib from UDCodeKit's bundle.
- (instancetype)init;

@property (nonatomic, weak, nullable) IBOutlet NSPopUpButton *kindPopUp;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *field;
@property (nonatomic, weak, nullable) id<UDBreakpointEditorDelegate> delegate;

/// The line it edits the breakpoint of (which may not be there yet).
@property (nonatomic) NSInteger line;
/// What it holds, the field's text in its place; empty strings for none.
@property (nonatomic, copy) NSString *condition;
@property (nonatomic, copy) NSString *hitCondition;
@property (nonatomic, copy) NSString *logMessage;
/// Which of them the field shows.
@property (nonatomic) UDBreakpointEditorKind kind;

/// Starts editing: the three, and which the field shows (the log message
/// when there is one, as VS Code chooses, else the hit count when it is
/// the only one, else the condition, unless @a kind says).
- (void)beginWithCondition:(nullable NSString *)condition hitCondition:(nullable NSString *)hitCondition
                logMessage:(nullable NSString *)logMessage kind:(UDBreakpointEditorKind)kind;
/// Whether @a kind can be chosen (what the adapter supports).
- (void)setKind:(UDBreakpointEditorKind)kind enabled:(BOOL)enabled;
- (BOOL)isKindEnabled:(UDBreakpointEditorKind)kind;

/// The box over @a view, its top at @a top (in @a view's superview), the
/// keyboard in its field; or moved there when it is up.
- (void)showOverView:(NSView *)view top:(CGFloat)top left:(CGFloat)left;
- (void)close;
@property (nonatomic, readonly, getter=isShown) BOOL shown;

/// The popup's: the field shows another of the three.
- (IBAction)kindChanged:(nullable id)sender;
/// The field's Return.
- (IBAction)accept:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
