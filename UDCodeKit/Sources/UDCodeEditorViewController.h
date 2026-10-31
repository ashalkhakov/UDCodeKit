/*---------------------------------------------------------------------------------------------
 *  UDCodeEditorViewController.h
 *
 *  NSViewController subclass that owns the text-editor pane:
 *    – scroll view + UDDiagnosticTextView
 *    – line-number gutter (left)
 *    – find-results / error-marks gutter (right)
 *    – the find and replace bar (top, on Find), UDFindBar.xib
 *    – Preview: the text rendered, in its place (for a mode that has one,
 *      Markdown's)
 *    – folding, bracket-match, structured-navigation, auto-indentation
 *    – breakpoints in the gutter and the debugger's line, once given a
 *      UDBreakpointStore (-showBreakpointsOfStore:forFile:); the gutter's
 *      menu edits them (UDBreakpointEditorViewController: a condition, a
 *      hit count, a log message); and while the store's session is stopped
 *      in the file, VS Code's debug hover (UDDebugHoverViewController) and
 *      Run to Cursor, Jump to Cursor and Add to Watch in the text's menu
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

@class UDFindBarViewController, UDBreakpointStore, UDBreakpointEditorViewController, UDDebugHoverViewController, UDSourceControlBlameRange,
       UDJumpBarView, UDJumpBarController;

NS_ASSUME_NONNULL_BEGIN

/// The editor switched between its text and Preview; the object is the editor.
FOUNDATION_EXPORT NSNotificationName const UDCodeEditorPreviewDidChangeNotification;

@class UDCodeEditorViewController;

/// What a link in the preview opens: the host's to say, as it has the tabs.
@protocol UDCodeEditorLinkDelegate <NSObject>
/// A link in the preview followed: clicked (to read, @a editing NO) or
/// ⌘-clicked (to edit). Return NO to have it opened as any other link is
/// (NSWorkspace: a web page in the browser).
- (BOOL)codeEditor:(UDCodeEditorViewController *)editor openLink:(NSURL *)url editing:(BOOL)editing;
@end

/// What the editor's change bars ask of source control.
@protocol UDCodeEditorSourceControlDelegate <NSObject>
/// Stage Change: @a indexText, the file's index text with the change in it, staged.
- (void)codeEditor:(UDCodeEditorViewController *)editor stageText:(NSString *)indexText;
/// Show Change: the file's Code Review.
- (void)codeEditorShowChanges:(UDCodeEditorViewController *)editor;
@end

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

/// The text its change bars are against (the file's index text, VS Code's
/// quick diff; nil: none): the lines changed since, drawn as Xcode's blue
/// bars in the gutter, a moment after each edit. A bar clicked: Show
/// Change, Stage Change, Discard Change.
@property (nonatomic, copy, nullable) NSString *quickDiffOriginal;
@property (nonatomic, readonly, copy) NSArray<UDDetailedLineRangeMapping *> *quickDiffChanges;
@property (nonatomic, weak, nullable) id<UDCodeEditorSourceControlDelegate> sourceControlDelegate;

/// Xcode's Authors beside the text (Editor > Authors): who last changed its
/// lines (blameRanges, git blame's), and when.
@property (nonatomic) BOOL showsAuthors;
@property (nonatomic, copy) NSArray<UDSourceControlBlameRange *> *blameRanges;

/// Xcode's jump bar over the text (VS Code's breadcrumbs), the XIB's: hidden
/// till shown; its controller (kept by the editor) fills it.
@property (nonatomic, weak, readonly) IBOutlet UDJumpBarView *jumpBar;
@property (nonatomic) BOOL showsJumpBar;
@property (nonatomic, strong, nullable) UDJumpBarController *jumpBarController;

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

/// Edit Breakpoint…: the box below line @a line for its breakpoint's
/// condition, hit count and log message (Return adds the breakpoint when
/// there is none). The breakpoint navigator's Edit Breakpoint… comes here.
- (void)editBreakpointAtLine:(NSInteger)line;
/// The box, once shown.
@property (nonatomic, strong, readonly, nullable) UDBreakpointEditorViewController *breakpointEditor;
/// The debug hover, once shown.
@property (nonatomic, strong, readonly, nullable) UDDebugHoverViewController *debugHover;

/// While the store's session is stopped (UDBreakpointStore.debugSession):
/// Run to Cursor (VS Code's), Jump to Cursor (when the adapter has
/// gotoTargets), at the caret's line; Add to Watch, the selection or the
/// expression at the caret. The text's context menu has them (from this
/// controller's XIB), and a host's Debug menu can send them to the first
/// responder (the text view hands them here).
- (IBAction)runToCursor:(nullable id)sender;
- (IBAction)jumpToCursor:(nullable id)sender;
- (IBAction)addToWatch:(nullable id)sender;

// ---------------------------------------------------------------------------
// MARK: - Preview
// ---------------------------------------------------------------------------

/// Whether the mode it was configured for renders its text (UDLanguageMode
/// hasPreview): Source | Preview then switches it.
@property (nonatomic, readonly) BOOL canShowPreview;

/// The text rendered, read-only, in place of the editor: its links open,
/// it follows the text's edits. Set NO, the text again; Find, Jump to Line
/// and going to a line (an issue's, the debugger's) set it NO. Posts
/// UDCodeEditorPreviewDidChangeNotification.
@property (nonatomic) BOOL showsPreview;

/// The file the preview's relative links and images, and the text's links,
/// are resolved against.
@property (nonatomic, copy, nullable) NSURL *previewBaseURL;

/// The preview's text view, once shown.
@property (nonatomic, readonly, nullable) NSTextView *previewTextView;

/// View > Show Preview (⌥⌘↩): Preview, or the text again.
- (IBAction)togglePreview:(nullable id)sender;

/// Opens the preview's links: other files (another Markdown file, read or
/// edited) are its to open; nil, or one that declines, and a link opens as
/// any other does.
@property (nonatomic, weak, nullable) id<UDCodeEditorLinkDelegate> linkDelegate;

/// What a click on a link in the preview does (a ⌘-click: @a editing): a
/// #fragment of this file's scrolls to its heading (⌘: the text, to edit;
/// VS Code's #L12, at that line);
/// any other link goes to the link delegate, else to NSWorkspace. A link
/// ⌘-clicked in the text (the mode's -linksInText:…) is followed so, to edit.
- (void)followPreviewLink:(NSURL *)url editing:(BOOL)editing;

/// Scrolls the preview to the heading @a anchor names (a link's #fragment,
/// UDPreviewAnchorAttributeName). NO when there is none.
- (BOOL)revealPreviewAnchor:(NSString *)anchor;

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
