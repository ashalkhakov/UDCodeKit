/*---------------------------------------------------------------------------------------------
 *  UDCodeEditorViewController.h
 *
 *  NSViewController subclass that owns the text-editor pane:
 *    – scroll view + UDDiagnosticTextView
 *    – line-number gutter (left)
 *    – find-results / error-marks gutter (right)
 *    – the find and replace bar (top, on Find), UDFindBar.xib
 *    – folding, bracket-match, structured-navigation, auto-indentation
 *    – breakpoints in the gutter and the debugger's line, once given a
 *      UDBreakpointStore (-showBreakpointsOfStore:forFile:)
 *
 *  Loaded from UDCodeEditorViewController.xib, in the UDCodeKit bundle.
 *  Initialise with -initWithTextStorage: before accessing .view so that the
 *  layout manager is wired before any parse is triggered.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDTextModelTextStorage.h"
#import "UDFindResultsGutterView.h"
#import "UDDiagnosticTextView.h"
#import "UDAutoIndenter.h"
#import "UDLanguageMode.h"
#import "UDFindModel.h"

@class UDFindBarViewController, UDBreakpointStore;

NS_ASSUME_NONNULL_BEGIN

@interface UDCodeEditorViewController : NSViewController

/// The editor text view (UDDiagnosticTextView). Available after the view is loaded.
@property (nonatomic, weak, readonly) UDDiagnosticTextView    *textView;

/// The find-results / error-marks gutter on the right edge.
/// Set errorFractions on this whenever the diagnostic list changes.
@property (nonatomic, weak, readonly) UDFindResultsGutterView *gutterView;

/// Auto-indenter.  Call -configureWithLanguageFunc:indentsQuery: on it once
/// the language and indents query are known (e.g. in -windowDidLoad of the
/// owning NSWindowController).
@property (nonatomic, strong, readonly) UDAutoIndenter *autoIndenter;

/// The find bar and its model, once Find has been used.
@property (nonatomic, strong, readonly, nullable) UDFindBarViewController *findBar;
@property (nonatomic, strong, readonly, nullable) UDFindModel *findModel;
@property (nonatomic, readonly, getter=isFindBarVisible) BOOL findBarVisible;

/// Shows the find bar (with the replace row when @a replacing), searching
/// for the selection when it is a short single line.
- (void)showFindBarReplacing:(BOOL)replacing;

/// Jump to Line (⌘L): a field over the editor; Return selects that line.
@property (nonatomic, readonly, getter=isJumpToLineVisible) BOOL jumpToLineVisible;
- (void)showJumpToLine;
/// Selects line @a line (1-based; clamped to the text's) and scrolls to it.
- (void)selectLine:(NSInteger)line;
/// Scrolls line @a line into view (centred, when it was out of it), the
/// selection left as it is: where the debugger stopped, say.
- (void)revealLine:(NSInteger)line;

/// Shows @a store's breakpoints of the file at @a path in the gutter, and
/// the debugger's line when it is in this file; from now on the file's
/// breakpoints follow this editor's edits. A click on a line number adds a
/// breakpoint, or disables or enables the one there; dragging one off the
/// gutter removes it. nil: none shown.
- (void)showBreakpointsOfStore:(nullable UDBreakpointStore *)store forFile:(nullable NSString *)path;
@property (nonatomic, strong, readonly, nullable) UDBreakpointStore *breakpointStore;
@property (nonatomic, copy, readonly, nullable) NSString *breakpointFile;

/// Debug > Toggle Breakpoint (⌘\): a breakpoint at the caret's line, added
/// or removed.
- (IBAction)toggleBreakpoint:(nullable id)sender;

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
    NS_DESIGNATED_INITIALIZER;

/// Sets up auto-indentation, bracket pairs and key handling for @a mode.
/// Loads the view if it has not been loaded.
- (void)configureForLanguageMode:(UDLanguageMode *)mode;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
