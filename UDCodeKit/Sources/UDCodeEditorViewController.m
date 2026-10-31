#import "UDCodeEditorViewController.h"
#import "UDPlaceholderHighlighter.h"
#import "UDLineNumberGutterView.h"
#import "UDFoldingController.h"
#import "UDBracketMatchHighlighter.h"
#import "UDStructuredNavigator.h"
#import "UDAutoIndenter.h"
#import "UDTreeSitterHighlighter.h"
#import "UDTextModelTextStorage.h"
#import "UDFindBarViewController.h"
#import "UDJumpToLineViewController.h"
#import "UDBreakpointStore.h"
#import "UDDebugSession.h"
#import "UDBreakpointEditorViewController.h"
#import "UDDebugHoverViewController.h"
#import "UDExtension.h"
#import "UDLinkDetector.h"
#import "UDAuthorsView.h"
#import "UDJumpBarView.h"
#import "UDJumpBarController.h"
#import <UDPieceTable/UDPieceTable.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface UDCodeEditorViewController () <UDLineNumberGutterViewDelegate, UDLineNumberGutterBreakpointSource,
                                          UDFindBarDelegate, UDFindActionHandler, UDJumpToLineDelegate,
                                          UDDebugTextHandler, UDBreakpointEditorDelegate, NSTextViewDelegate>

// IBOutlets wired from UDCodeEditorViewController.xib.
@property (nonatomic, weak) IBOutlet NSScrollView            *scrollView;
@property (nonatomic, weak) IBOutlet UDDiagnosticTextView    *textView;
@property (nonatomic, weak) IBOutlet NSView                  *findBarHost;
@property (nonatomic, weak) IBOutlet NSView                  *editorArea;
@property (nonatomic, weak) IBOutlet NSSplitView             *bodySplitView;
@property (nonatomic) CGFloat accessoryHeight;
@property (nonatomic, weak) IBOutlet UDLineNumberGutterView  *lineNumberGutterView;
/// Authors (git blame), hidden till shown, at the gutter's left.
@property (nonatomic, weak) IBOutlet UDAuthorsView *authorsView;
@property (nonatomic, weak) IBOutlet UDJumpBarView *jumpBar;
@property (nonatomic, weak) IBOutlet UDFindResultsGutterView *gutterView;

@property (nonatomic, strong, nullable) UDFindBarViewController *findBar;
@property (nonatomic) CGFloat findBarHeight;
@property (nonatomic, strong, nullable) UDJumpToLineViewController *jumpToLine;
@property (nonatomic, strong) UDFoldingController      *foldingController;
@property (nonatomic, strong) UDBracketMatchHighlighter *bracketMatchHighlighter;
@property (nonatomic, strong) UDPlaceholderHighlighter *placeholderHighlighter;
@property (nonatomic, strong) UDStructuredNavigator    *structuredNavigator;
@property (nonatomic, strong) UDAutoIndenter           *autoIndenter;
@property (nonatomic, strong) UDLinkDetector           *linkDetector;

// Text-model state.
@property (nonatomic, strong) UDTextModelTextStorage   *textStorage;
@property (nonatomic, strong, nullable) UDFindModel    *findModel;

// Breakpoints.
@property (nonatomic, strong, nullable) UDBreakpointStore *breakpointStore;
@property (nonatomic, copy, nullable)   NSString          *breakpointFile;
@property (nonatomic, strong, nullable) UDBreakpointEditorViewController *breakpointEditor;

// The debugger's: the gutter's menus (a breakpoint's, a line's), the text's
// items, from the XIB; the hover.
@property (nonatomic, strong) IBOutlet NSMenu *breakpointMenu;
@property (nonatomic, strong) IBOutlet NSMenu *lineMenu;
@property (nonatomic, strong) IBOutlet NSMenu *debugTextMenu;
@property (nonatomic) NSInteger menuLine;
// Source control's: a change bar's menu (Show, Stage, Discard Change), from
// the XIB, and the change it is about.
@property (nonatomic, strong) IBOutlet NSMenu *changeMenu;
@property (nonatomic, strong, nullable) UDDetailedLineRangeMapping *menuChange;
@property (nonatomic, strong, nullable) UDDebugHoverViewController *debugHover;
@property (nonatomic) NSRange debugHoverRange;

// Preview: the mode's rendering of the text, over the editor.
@property (nonatomic, strong, nullable) UDLanguageMode *languageMode;
@property (nonatomic) BOOL canShowPreview;
@property (nonatomic, strong, nullable) NSScrollView *previewScrollView;
@property (nonatomic, strong, nullable) NSTextView *previewTextView;

@end

NSNotificationName const UDCodeEditorPreviewDidChangeNotification = @"UDCodeEditorPreviewDidChangeNotification";

// ---------------------------------------------------------------------------

@implementation UDCodeEditorViewController

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage {
    self = [super initWithNibName:@"UDCodeEditorViewController"
                           bundle:[NSBundle bundleForClass:[UDCodeEditorViewController class]]];
    if (self) {
        _textStorage = textStorage;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
// MARK: - View lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];

    // 1. Wire the layout manager FIRST — decoration highlights need a live path.
    NSLayoutManager *lm = _textView.layoutManager;
    [[lm textStorage] removeLayoutManager:lm];
    [_textStorage addLayoutManager:lm];

    // 2. Configure text view.
    _textView.textModel = _textStorage.textModel;
    _textView.cursorsController = _textStorage.cursorsController;
    // Ensure the cursor controller reflects the text view's initial position.
    [_textView syncCursorControllerFromSelection];

    // 3. The gutters (from the XIB) follow the text view.
    [_lineNumberGutterView attachToScrollView:_scrollView
                                     textView:_textView
                                    textModel:_textStorage.textModel];
    [_authorsView attachToTextView:_textView textModel:_textStorage.textModel];
    _textView.findActionHandler = self;
    _textView.debugHandler = self;

    // 8. Folding controller.
    _foldingController =
        [[UDFoldingController alloc] initWithTextView:_textView
                                          textStorage:_textStorage
                                           highlighter:_textStorage.highlighter];
    _foldingController.lineNumberGutterView = _lineNumberGutterView;
    [_foldingController update];

    // 9. Bracket-match highlighter.
    _bracketMatchHighlighter =
        [[UDBracketMatchHighlighter alloc] initWithTextView:_textView
                                                textStorage:_textStorage
                                                 highlighter:_textStorage.highlighter];

    // 9b. Placeholders ("<#…#>"), as pills.
    _placeholderHighlighter =
        [[UDPlaceholderHighlighter alloc] initWithTextStorage:_textStorage
                                                  highlighter:_textStorage.highlighter];
    [_placeholderHighlighter update];

    // 10. Structured navigator.
    _structuredNavigator =
        [[UDStructuredNavigator alloc] initWithTextView:_textView
                                             highlighter:_textStorage.highlighter
                                               textModel:_textStorage.textModel];

    // 11. Auto-indenter (caller calls -configureWithLanguageFunc:indentsQuery: after viewDidLoad).
    _autoIndenter =
        [[UDAutoIndenter alloc] initWithHighlighter:_textStorage.highlighter
                                           textView:_textView
                                          textModel:_textStorage.textModel
                                  cursorsController:_textStorage.cursorsController];

    // 12. Wire the text view's key-handler references so that keyDown: in
    //     UDDiagnosticTextView can dispatch Return, Option+Arrow, and
    //     electric-pair events without a global NSEvent monitor.
    _textView.autoIndenter        = _autoIndenter;
    _textView.structuredNavigator = _structuredNavigator;

    // 12b. The text's links (Markdown's, say), followed with ⌘ to edit.
    _linkDetector = [[UDLinkDetector alloc] initWithTextStorage:_textStorage highlighter:_textStorage.highlighter];
    __weak UDCodeEditorViewController *weakSelf = self;
    _linkDetector.openLink = ^(NSURL *url) { [weakSelf followPreviewLink:url editing:YES]; };
    _textView.linkDetector = _linkDetector;

    // 13. Observe text-storage edits for folding and bracket match.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_textStorageDidEdit:)
               name:NSTextStorageDidProcessEditingNotification
             object:_textStorage];
}

- (void)configureForLanguageMode:(UDLanguageMode *)mode {
    (void)self.view;
    if (mode.languageFunc && mode.indentsQuery) {
        [_autoIndenter configureWithLanguageFunc:mode.languageFunc
                                    indentsQuery:mode.indentsQuery];
    }
    _autoIndenter.languageConfiguration = mode.languageConfiguration;
    _autoIndenter.languageKeyHandler    = mode.keyHandler;
    _languageMode = mode;
    _linkDetector.languageMode = mode;
    [_linkDetector update];
    _canShowPreview = mode.hasPreview;
    if (!_canShowPreview) self.showsPreview = NO;
    else if (_showsPreview) [self _renderPreview];
}

// ---------------------------------------------------------------------------
// MARK: - NSTextStorageDidProcessEditingNotification
// ---------------------------------------------------------------------------

- (void)_textStorageDidEdit:(NSNotification *)note {
    NSTextStorage *ts = note.object;
    if (!(ts.editedMask & NSTextStorageEditedCharacters)) return;

    [self performSelector:@selector(_updateAfterEdit) withObject:nil
               afterDelay:0 inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode ]];
}

- (void)_updateAfterEdit {
    if (_quickDiffOriginal) {
        // the change bars: a moment after the typing (VS Code's 200 ms)
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_computeQuickDiff) object:nil];
        [self performSelector:@selector(_computeQuickDiff) withObject:nil afterDelay:0.2];
    }
    [_foldingController update];
    [_bracketMatchHighlighter update];
    [_linkDetector scheduleUpdate];
    if (_showsPreview) {
        // a moment after the typing, not each keystroke
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_renderPreview) object:nil];
        [self performSelector:@selector(_renderPreview) withObject:nil afterDelay:0.3];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Authors (Xcode's: git blame beside the text)
// ---------------------------------------------------------------------------

- (BOOL)showsAuthors {
    return _authorsView && ![_authorsView isHidden];
}

- (void)setShowsAuthors:(BOOL)showsAuthors {
    (void)self.view;
    if (showsAuthors == self.showsAuthors) return;
    CGFloat width = NSWidth(_authorsView.frame) * (showsAuthors ? 1 : -1);
    // the gutter and the text moved over, or back
    for (NSView *view in @[ _lineNumberGutterView, _scrollView ]) {
        NSRect frame = view.frame;
        frame.origin.x += width;
        if (view == _scrollView) frame.size.width -= width;
        view.frame = frame;
    }
    if (!showsAuthors) _authorsView.ranges = @[];
    [_authorsView setHidden:!showsAuthors];
    [_editorArea setNeedsDisplay:YES];
}

- (NSArray<UDSourceControlBlameRange *> *)blameRanges {
    return _authorsView.ranges ?: @[];
}

- (void)setBlameRanges:(NSArray<UDSourceControlBlameRange *> *)blameRanges {
    _authorsView.ranges = blameRanges;
}

// ---------------------------------------------------------------------------
// MARK: - Change bars (VS Code's quick diff, Xcode's look)
// ---------------------------------------------------------------------------

static NSArray<NSString *> *UDLinesOfText(NSString *text) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        [lines addObject:[line hasSuffix:@"\r"] ? [line substringToIndex:line.length - 1] : line];
    }
    return lines;
}

- (NSArray<NSString *> *)_currentLines {
    UDTextModel *model = _textStorage.textModel;
    NSInteger count = [model getLineCount];
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (NSInteger line = 1; line <= count; line++) [lines addObject:[model getLineContent:line]];
    return lines;
}

- (void)setQuickDiffOriginal:(NSString *)quickDiffOriginal {
    if (quickDiffOriginal == _quickDiffOriginal || [quickDiffOriginal isEqualToString:_quickDiffOriginal]) return;
    _quickDiffOriginal = [quickDiffOriginal copy];
    [self _computeQuickDiff];
}

- (void)_computeQuickDiff {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_computeQuickDiff) object:nil];
    (void)self.view;
    if (!_quickDiffOriginal) {
        _quickDiffChanges = @[];
        _lineNumberGutterView.changes = @{};
        return;
    }
    UDLinesDiff *diff = [UDLinesDiffComputer diffOfOriginalLines:UDLinesOfText(_quickDiffOriginal) modifiedLines:[self _currentLines]
                                            ignoreTrimWhitespace:NO maxComputationTime:1.0];
    _quickDiffChanges = diff.changes;
    NSMutableDictionary<NSNumber *, NSNumber *> *marks = [NSMutableDictionary dictionary];
    for (UDDetailedLineRangeMapping *change in diff.changes) {
        if (UDLineRangeLength(change.modified) == 0) {
            marks[@(-(change.modified.startLineNumber - 1))] = @(UDGutterChangeDeletedAfter);
            continue;
        }
        UDGutterChange kind = UDLineRangeLength(change.original) == 0 ? UDGutterChangeAdded : UDGutterChangeModified;
        for (NSInteger line = change.modified.startLineNumber; line < change.modified.endLineNumberExclusive; line++) marks[@(line)] = @(kind);
    }
    _lineNumberGutterView.changes = marks;
}

/// The change whose bar is at @a line.
- (nullable UDDetailedLineRangeMapping *)_quickDiffChangeAtLine:(NSInteger)line {
    for (UDDetailedLineRangeMapping *change in _quickDiffChanges) {
        UDLineRange modified = change.modified;
        if (UDLineRangeLength(modified) == 0) {
            if (modified.startLineNumber - 1 == line || (line == 1 && modified.startLineNumber == 1)) return change;
        } else if (modified.startLineNumber <= line && line < modified.endLineNumberExclusive) {
            return change;
        }
    }
    return nil;
}

- (void)lineNumberGutterView:(UDLineNumberGutterView *)view didClickChangeAtLine:(NSInteger)lineNumber event:(NSEvent *)event {
    UDDetailedLineRangeMapping *change = [self _quickDiffChangeAtLine:lineNumber];
    if (!change) return;
    _menuChange = change;
    [NSMenu popUpContextMenu:_changeMenu withEvent:event forView:view];
}

- (IBAction)showChange:(nullable id)sender {
    [_sourceControlDelegate codeEditorShowChanges:self];
}

/// The original's text with @a change in it: what Stage Change stages.
- (IBAction)stageChange:(nullable id)sender {
    UDDetailedLineRangeMapping *change = _menuChange;
    if (!change) return;
    NSMutableArray<NSString *> *lines = [UDLinesOfText(_quickDiffOriginal) mutableCopy];
    NSArray<NSString *> *current = [self _currentLines];
    NSRange original = NSMakeRange((NSUInteger)change.original.startLineNumber - 1, (NSUInteger)UDLineRangeLength(change.original));
    NSRange modified = NSMakeRange((NSUInteger)change.modified.startLineNumber - 1, (NSUInteger)UDLineRangeLength(change.modified));
    [lines replaceObjectsInRange:original withObjectsFromArray:[current subarrayWithRange:modified]];
    [_sourceControlDelegate codeEditor:self stageText:[lines componentsJoinedByString:@"\n"]];
}

/// The change's lines as they were (Xcode asks first).
- (IBAction)discardChange:(nullable id)sender {
    UDDetailedLineRangeMapping *change = _menuChange;
    if (!change) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"The selected change will be discarded.";
    [alert addButtonWithTitle:@"Discard Change"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSArray<NSString *> *was = [UDLinesOfText(_quickDiffOriginal)
                                subarrayWithRange:NSMakeRange((NSUInteger)change.original.startLineNumber - 1,
                                                              (NSUInteger)UDLineRangeLength(change.original))];
    UDTextModel *model = _textStorage.textModel;
    NSInteger count = [model getLineCount];
    NSInteger start = change.modified.startLineNumber, end = change.modified.endLineNumberExclusive;
    NSString *text = [was componentsJoinedByString:@"\n"];
    UDRange range;
    if (start > count) {
        // lines deleted at the end: after the last
        range = PTRangeMake(count, [model getLineMaxColumn:count], count, [model getLineMaxColumn:count]);
        text = [@"\n" stringByAppendingString:text];
    } else if (end <= count) {
        // whole lines, their line breaks with them
        range = PTRangeMake(start, 1, end, 1);
        if (was.count) text = [text stringByAppendingString:@"\n"];
    } else if (was.count || start == 1) {
        range = PTRangeMake(start, 1, count, [model getLineMaxColumn:count]);
    } else {
        // the last lines, added: from the end of the line before
        range = PTRangeMake(start - 1, [model getLineMaxColumn:start - 1], count, [model getLineMaxColumn:count]);
    }
    [model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:range text:text] ]];
}

// ---------------------------------------------------------------------------
// MARK: - UDLineNumberGutterViewDelegate
// ---------------------------------------------------------------------------

- (void)lineNumberGutterView:(UDLineNumberGutterView *)view
    didClickFoldIndicatorAtLine:(NSInteger)lineNumber {
    [_foldingController toggleFoldAtLine:lineNumber];
}

- (void)lineNumberGutterView:(UDLineNumberGutterView *)view didClickLine:(NSInteger)lineNumber {
    if (_breakpointFile) [_breakpointStore clickBreakpointAtLine:lineNumber inFile:_breakpointFile];
}

- (void)lineNumberGutterView:(UDLineNumberGutterView *)view didDragBreakpointOffLine:(NSInteger)lineNumber {
    UDBreakpoint *breakpoint = _breakpointFile ? [_breakpointStore breakpointAtLine:lineNumber inFile:_breakpointFile] : nil;
    if (breakpoint) [_breakpointStore removeBreakpoint:breakpoint];
}

/// A breakpoint's menu (Edit, Disable, Delete), or a line's (Add, Add
/// Conditional, Add Logpoint, Run to Line), as VS Code's gutter has them.
- (NSMenu *)lineNumberGutterView:(UDLineNumberGutterView *)view menuForLine:(NSInteger)lineNumber {
    if (!_breakpointFile) return nil;
    _menuLine = lineNumber;
    return [_breakpointStore breakpointAtLine:lineNumber inFile:_breakpointFile] ? _breakpointMenu : _lineMenu;
}

// ---------------------------------------------------------------------------
// MARK: - Breakpoints
// ---------------------------------------------------------------------------

- (void)showBreakpointsOfStore:(UDBreakpointStore *)store forFile:(NSString *)path {
    (void)self.view;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_breakpointStore) {
        [center removeObserver:self name:UDBreakpointStoreDidChangeNotification object:_breakpointStore];
        [center removeObserver:self name:UDBreakpointStoreDidMoveInstructionPointerNotification object:_breakpointStore];
    }
    _breakpointStore = path ? store : nil;
    _breakpointFile = _breakpointStore ? [path stringByStandardizingPath] : nil;
    if (_breakpointStore) {
        [_breakpointStore attachTextModel:_textStorage.textModel toFile:_breakpointFile];
        [center addObserver:self selector:@selector(_breakpointsDidChange:)
                       name:UDBreakpointStoreDidChangeNotification object:_breakpointStore];
        [center addObserver:self selector:@selector(_breakpointsDidChange:)
                       name:UDBreakpointStoreDidMoveInstructionPointerNotification object:_breakpointStore];
    }
    _lineNumberGutterView.breakpointSource = _breakpointStore ? self : nil;
    [_textView setNeedsDisplay:YES];
}

- (void)_breakpointsDidChange:(NSNotification *)note {
    id files = note.userInfo[UDBreakpointStoreFileKey];
    if (![files isKindOfClass:[NSArray class]]) files = files ? @[ files ] : @[];
    if (![files containsObject:_breakpointFile]) return;
    [_lineNumberGutterView setNeedsDisplay:YES];
    if (note.name == UDBreakpointStoreDidMoveInstructionPointerNotification) [_textView setNeedsDisplay:YES];
}

- (NSDictionary<NSNumber *, NSNumber *> *)breakpointsInLines:(NSRange)lines {
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    for (UDBreakpoint *breakpoint in [_breakpointStore breakpointsInFile:_breakpointFile]) {
        if (!NSLocationInRange((NSUInteger)breakpoint.line, lines)) continue;
        NSInteger kind = !breakpoint.enabled ? UDGutterBreakpointDisabled
                       : !breakpoint.verified ? UDGutterBreakpointUnverified : UDGutterBreakpointEnabled;
        if (breakpoint.logpoint) kind |= UDGutterBreakpointLogpoint;
        else if (breakpoint.conditional) kind |= UDGutterBreakpointConditional;
        found[@(breakpoint.line)] = @(kind);
    }
    return found;
}

- (NSInteger)instructionPointerLine {
    return [_breakpointStore.instructionPointerFile isEqualToString:_breakpointFile] ? _breakpointStore.instructionPointerLine : 0;
}

- (IBAction)toggleBreakpoint:(id)sender {
    if (!_breakpointFile) {
        NSBeep();
        return;
    }
    [_breakpointStore toggleBreakpointAtLine:[self _caretLine] inFile:_breakpointFile];
}

- (NSInteger)_caretLine {
    return [_textStorage.textModel getPositionAt:(NSInteger)_textView.selectedRange.location].line;
}

// The gutter's menus: about the line they were opened on.

- (IBAction)addBreakpoint:(id)sender {
    if (_breakpointFile && _menuLine > 0) [_breakpointStore addBreakpointAtLine:_menuLine inFile:_breakpointFile];
}

- (IBAction)addConditionalBreakpoint:(id)sender {
    if (_menuLine > 0) [self _editBreakpointAtLine:_menuLine kind:UDBreakpointEditorCondition];
}

- (IBAction)addLogpoint:(id)sender {
    if (_menuLine > 0) [self _editBreakpointAtLine:_menuLine kind:UDBreakpointEditorLogMessage];
}

- (IBAction)editBreakpoint:(id)sender {
    if (_menuLine > 0) [self editBreakpointAtLine:_menuLine];
}

- (IBAction)toggleBreakpointEnabled:(id)sender {
    UDBreakpoint *breakpoint = [self _menuBreakpoint];
    if (breakpoint) [_breakpointStore setBreakpoint:breakpoint enabled:!breakpoint.enabled];
}

- (IBAction)deleteBreakpoint:(id)sender {
    UDBreakpoint *breakpoint = [self _menuBreakpoint];
    if (breakpoint) [_breakpointStore removeBreakpoint:breakpoint];
}

- (IBAction)runToLine:(id)sender {
    UDDebugSession *session = [self _session];
    if (session.canContinue && _menuLine > 0) [session runToLine:_menuLine inFile:_breakpointFile];
}

- (nullable UDBreakpoint *)_menuBreakpoint {
    return _breakpointFile && _menuLine > 0 ? [_breakpointStore breakpointAtLine:_menuLine inFile:_breakpointFile] : nil;
}

// ---------------------------------------------------------------------------
// MARK: - Editing a breakpoint: its condition, hit count, log message
// ---------------------------------------------------------------------------

- (void)editBreakpointAtLine:(NSInteger)line {
    [self _editBreakpointAtLine:line kind:UDBreakpointEditorCondition];
}

/// The box below @a line, showing @a kind (or what the breakpoint has);
/// what the session's adapter cannot do greyed.
- (void)_editBreakpointAtLine:(NSInteger)line kind:(UDBreakpointEditorKind)kind {
    (void)self.view;
    if (!_breakpointFile || line < 1) return;
    if (!_breakpointEditor) {
        _breakpointEditor = [[UDBreakpointEditorViewController alloc] init];
        _breakpointEditor.delegate = self;
    }
    [_breakpointEditor close];
    DAPClient *adapter = [self _liveSession].client;
    [_breakpointEditor setKind:UDBreakpointEditorCondition enabled:!adapter || adapter.supportsConditionalBreakpoints];
    [_breakpointEditor setKind:UDBreakpointEditorHitCondition enabled:!adapter || adapter.supportsHitConditionalBreakpoints];
    [_breakpointEditor setKind:UDBreakpointEditorLogMessage enabled:!adapter || adapter.supportsLogPoints];
    UDBreakpoint *breakpoint = [_breakpointStore breakpointAtLine:line inFile:_breakpointFile];
    _breakpointEditor.line = line;
    [_breakpointEditor beginWithCondition:breakpoint.condition hitCondition:breakpoint.hitCondition
                               logMessage:breakpoint.logMessage kind:kind];
    [self revealLine:line];
    [self _placeBreakpointEditor];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_editorAreaScrolled:)
                                                 name:NSViewBoundsDidChangeNotification object:_scrollView.contentView];
}

/// Just below its line (above it, at the bottom of the editor), from the
/// text's left edge.
- (void)_placeBreakpointEditor {
    UDTextModel *model = _textStorage.textModel;
    NSInteger line = MAX(1, MIN(_breakpointEditor.line, [model getLineCount]));
    NSLayoutManager *lm = _textView.layoutManager;
    NSUInteger offset = (NSUInteger)[model getOffsetAt:line column:1];
    NSRange glyphs = [lm glyphRangeForCharacterRange:NSMakeRange(offset, 0) actualCharacterRange:NULL];
    NSRect lineRect = [lm lineFragmentRectForGlyphAtIndex:MIN(glyphs.location, MAX([lm numberOfGlyphs], 1) - 1)
                                           effectiveRange:NULL];
    lineRect.origin.y += _textView.textContainerOrigin.y;
    NSRect inArea = [_textView convertRect:lineRect toView:_editorArea];
    CGFloat height = NSHeight(_breakpointEditor.view.frame);
    BOOL flipped = _editorArea.isFlipped;
    CGFloat below = flipped ? NSMaxY(inArea) : NSMinY(inArea);
    CGFloat top = flipped ? below + 2.0 : below - 2.0;
    BOOL fits = flipped ? top + height <= NSHeight(_editorArea.bounds) : top - height >= 0.0;
    if (!fits) top = flipped ? NSMinY(inArea) - 2.0 - height : NSMaxY(inArea) + 2.0 + height;
    // In the editor area's superview, where the box goes.
    NSPoint origin = [_editorArea convertPoint:NSMakePoint(NSMinX(_scrollView.frame) + 4.0, top)
                                        toView:_editorArea.superview];
    [_breakpointEditor showOverView:_editorArea top:origin.y left:origin.x];
}

- (void)_editorAreaScrolled:(NSNotification *)note {
    if (_breakpointEditor.isShown) [self _placeBreakpointEditor];
}

- (void)_closeBreakpointEditor {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewBoundsDidChangeNotification
                                                  object:_scrollView.contentView];
    BOOL hadKeyboard = _breakpointEditor.isShown;
    [_breakpointEditor close];
    if (hadKeyboard) [self.view.window makeFirstResponder:_textView];
}

/// Kept: the breakpoint's (added, when there was none, as VS Code adds it).
- (void)breakpointEditorDidAccept:(UDBreakpointEditorViewController *)editor {
    NSString *condition = editor.condition, *hitCondition = editor.hitCondition, *logMessage = editor.logMessage;
    [self _closeBreakpointEditor];
    if (!_breakpointFile) return;
    UDBreakpoint *breakpoint = [_breakpointStore breakpointAtLine:editor.line inFile:_breakpointFile]
                            ?: [_breakpointStore addBreakpointAtLine:editor.line inFile:_breakpointFile];
    [_breakpointStore setBreakpoint:breakpoint condition:condition hitCondition:hitCondition logMessage:logMessage];
}

- (void)breakpointEditorDidCancel:(UDBreakpointEditorViewController *)editor {
    [self _closeBreakpointEditor];
}

// ---------------------------------------------------------------------------
// MARK: - The debugger in the text: hover, Run to Cursor, Add to Watch
// ---------------------------------------------------------------------------

/// The store's session, while it has not ended.
- (nullable UDDebugSession *)_liveSession {
    UDDebugSession *session = _breakpointStore.debugSession;
    return session.state == UDDebugSessionStateEnded ? nil : session;
}

- (nullable UDDebugSession *)_session {
    return _breakpointFile ? [self _liveSession] : nil;
}

/// The session, when it is stopped in this file.
- (nullable UDDebugSession *)_sessionStoppedHere {
    UDDebugSession *session = [self _session];
    if (session.state != UDDebugSessionStateStopped) return nil;
    return [session.selectedFrame.path.stringByStandardizingPath isEqualToString:_breakpointFile] ? session : nil;
}

/// What to evaluate at @a index: the selection, when @a index is in it and
/// it is one line, else the expression there (VS Code's); its range.
- (NSRange)_expressionRangeAtIndex:(NSUInteger)index {
    NSString *text = _textStorage.string;
    NSRange selection = _textView.selectedRange;
    if (selection.length && NSLocationInRange(index, selection) &&
        [[text substringWithRange:selection] rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location == NSNotFound) {
        return selection;
    }
    if (index >= text.length) return NSMakeRange(NSNotFound, 0);
    NSRange line = [text lineRangeForRange:NSMakeRange(index, 0)];
    NSCharacterSet *word = [NSCharacterSet alphanumericCharacterSet];
    NSUInteger start = index, end = index;
    while (start > line.location && ([word characterIsMember:[text characterAtIndex:start - 1]] || [text characterAtIndex:start - 1] == '_')) start--;
    while (end < NSMaxRange(line) && ([word characterIsMember:[text characterAtIndex:end]] || [text characterAtIndex:end] == '_')) end++;
    if (end == start) return NSMakeRange(NSNotFound, 0);
    NSRange found = UDEvaluatableExpressionRange([text substringWithRange:line], NSMakeRange(start - line.location, end - start));
    return found.location == NSNotFound ? found : NSMakeRange(line.location + found.location, found.length);
}

- (BOOL)textView:(UDDiagnosticTextView *)textView showsDebugHoverAtIndex:(NSUInteger)characterIndex {
    UDDebugSession *session = [self _sessionStoppedHere];
    if (!session.client.supportsEvaluateForHovers) return NO;
    NSRange range = [self _expressionRangeAtIndex:characterIndex];
    if (range.location == NSNotFound) return NO;
    _debugHoverRange = range;
    [session evaluate:[_textStorage.string substringWithRange:range] context:@"hover"
               target:self action:@selector(_didEvaluateHover:)];
    return YES;
}

/// Shown, unless it did not evaluate (VS Code shows nothing then).
- (void)_didEvaluateHover:(UDDebugVariable *)variable {
    if (variable.failed || _debugHoverRange.location == NSNotFound) return;
    if (!_debugHover) _debugHover = [[UDDebugHoverViewController alloc] init];
    [_debugHover showVariable:variable ofSession:[self _sessionStoppedHere] atCharacterRange:_debugHoverRange
                   ofTextView:_textView];
}

/// Off the word: the hover goes, unless the mouse went into it (to open
/// what it shows); it goes when the mouse leaves it.
- (void)textViewDebugHoverDidEnd:(UDDiagnosticTextView *)textView {
    _debugHoverRange = NSMakeRange(NSNotFound, 0);
    if (!_debugHover.containsMouse) [_debugHover close];
}

- (NSArray<NSMenuItem *> *)debugMenuItemsForTextView:(UDDiagnosticTextView *)textView {
    if (![self _session]) return nil;
    return _debugTextMenu.itemArray;
}

- (IBAction)runToCursor:(id)sender {
    UDDebugSession *session = [self _session];
    if (session.canContinue) [session runToLine:[self _caretLine] inFile:_breakpointFile];
    else NSBeep();
}

- (IBAction)jumpToCursor:(id)sender {
    UDDebugSession *session = [self _session];
    if (session.canJump) [session jumpToLine:[self _caretLine] inFile:_breakpointFile];
    else NSBeep();
}

- (IBAction)addToWatch:(id)sender {
    NSRange range = [self _expressionRangeAtIndex:_textView.selectedRange.location];
    if (range.location == NSNotFound || !_breakpointStore) {
        NSBeep();
        return;
    }
    [_breakpointStore addWatchExpression:[_textStorage.string substringWithRange:range]];
}

- (BOOL)canPerformDebugAction:(SEL)action {
    UDDebugSession *session = [self _session];
    if (sel_isEqual(action, @selector(runToCursor:))) return session.canContinue;
    if (sel_isEqual(action, @selector(jumpToCursor:))) return session.canJump;
    if (sel_isEqual(action, @selector(addToWatch:))) {
        return _breakpointStore && [self _expressionRangeAtIndex:_textView.selectedRange.location].location != NSNotFound;
    }
    return NO;
}

/// The menus' items: theirs are this controller's (sel_isEqual: a XIB's
/// selector is another pointer on GNUstep).
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    if (sel_isEqual(action, @selector(runToCursor:)) || sel_isEqual(action, @selector(jumpToCursor:)) ||
        sel_isEqual(action, @selector(addToWatch:))) {
        return [self canPerformDebugAction:action];
    }
    if (sel_isEqual(action, @selector(runToLine:))) return [self _session].canContinue;
    if (sel_isEqual(action, @selector(togglePreview:))) {
        item.title = _showsPreview ? @"Hide Preview" : @"Show Preview";
        return _canShowPreview;
    }
    if (sel_isEqual(action, @selector(toggleBreakpointEnabled:))) {
        UDBreakpoint *breakpoint = [self _menuBreakpoint];
        item.title = breakpoint.enabled ? @"Disable Breakpoint" : @"Enable Breakpoint";
        return breakpoint != nil;
    }
    if (sel_isEqual(action, @selector(editBreakpoint:)) || sel_isEqual(action, @selector(deleteBreakpoint:))) {
        return [self _menuBreakpoint] != nil;
    }
    if (sel_isEqual(action, @selector(addBreakpoint:)) || sel_isEqual(action, @selector(addConditionalBreakpoint:)) ||
        sel_isEqual(action, @selector(addLogpoint:))) {
        return _breakpointFile != nil && _menuLine > 0;
    }
    if (sel_isEqual(action, @selector(showChange:)) || sel_isEqual(action, @selector(stageChange:))) return _menuChange != nil;
    if (sel_isEqual(action, @selector(discardChange:))) return _menuChange != nil && _textView.isEditable;
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Preview
// ---------------------------------------------------------------------------

- (void)setShowsPreview:(BOOL)showsPreview {
    if (showsPreview && !_canShowPreview) showsPreview = NO;
    if (showsPreview == _showsPreview) return;
    (void)self.view;
    _showsPreview = showsPreview;
    NSWindow *window = self.view.window;
    if (showsPreview) {
        BOOL editing = window.firstResponder == _textView;
        if (!_previewScrollView) [self _makePreview];
        [self _renderPreview];
        _previewScrollView.hidden = NO;
        _editorArea.hidden = YES;
        if (editing) [window makeFirstResponder:_previewTextView];
    } else {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_renderPreview) object:nil];
        BOOL reading = window.firstResponder == _previewTextView;
        _previewScrollView.hidden = YES;
        _editorArea.hidden = NO;
        if (reading) [window makeFirstResponder:_textView];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:UDCodeEditorPreviewDidChangeNotification object:self];
}

- (void)setPreviewBaseURL:(NSURL *)previewBaseURL {
    if (previewBaseURL == _previewBaseURL || [previewBaseURL isEqual:_previewBaseURL]) return;
    _previewBaseURL = [previewBaseURL copy];
    (void)self.view;
    _linkDetector.baseURL = _previewBaseURL;
    [_linkDetector update];
}

- (IBAction)togglePreview:(id)sender {
    self.showsPreview = !_showsPreview;
}

/// A read-only text view over the whole editor, the find bar's place and all.
- (void)_makePreview {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    NSSize size = scroll.contentSize;
    NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    text.editable = NO;
    text.selectable = YES;
    text.richText = YES;
    text.importsGraphics = NO;
    text.textContainerInset = NSMakeSize(20, 16);
    text.minSize = NSMakeSize(0, size.height);
    text.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    text.verticallyResizable = YES;
    text.horizontallyResizable = NO;
    text.autoresizingMask = NSViewWidthSizable;
    text.textContainer.widthTracksTextView = YES;
    text.drawsBackground = YES;
    text.backgroundColor = [NSColor textBackgroundColor];
    text.delegate = self;
    scroll.documentView = text;
    scroll.hidden = YES;
    [self.view addSubview:scroll positioned:NSWindowAbove relativeTo:nil];
    _previewScrollView = scroll;
    _previewTextView = text;
}

/// The text rendered again, where it was scrolled to.
- (void)_renderPreview {
    if (!_previewTextView) return;
    NSString *text = [_textStorage.string copy];
    NSAttributedString *rendered = [_languageMode previewOfText:text baseURL:_previewBaseURL]
        ?: [[NSAttributedString alloc] initWithString:@""];
    NSPoint scrolled = _previewScrollView.contentView.bounds.origin;
    NSMutableAttributedString *shown = [rendered mutableCopy];
    // a file's link says where it goes, and what ⌘ does (run by run: GNUstep
    // has no -enumerateAttribute:…usingBlock:)
    NSRange range = NSMakeRange(0, 0);
    for (NSUInteger at = 0; at < rendered.length; at = NSMaxRange(range)) {
        id link = [rendered attribute:NSLinkAttributeName atIndex:at effectiveRange:&range];
        NSURL *url = [link isKindOfClass:[NSURL class]] ? link : nil;
        if (!url.isFileURL || [self _isThisFile:url]) continue;
        NSString *where = url.path.lastPathComponent;
        if (url.fragment.length) where = [NSString stringWithFormat:@"%@#%@", where, url.fragment];
        [shown addAttribute:NSToolTipAttributeName
                      value:[NSString stringWithFormat:@"%@ — click to read, ⌘-click to edit", where] range:range];
    }
    [_previewTextView.textStorage setAttributedString:shown];
    [_previewTextView scrollPoint:scrolled];
}

// ---------------------------------------------------------------------------
// MARK: - Links in the preview
// ---------------------------------------------------------------------------

/// A link into this very file (its #heading), or one with only a fragment
/// (the file not saved).
- (BOOL)_isThisFile:(NSURL *)url {
    if (!url.path.length) return url.fragment.length > 0;
    return _previewBaseURL.path && [url.path.stringByStandardizingPath isEqualToString:_previewBaseURL.path.stringByStandardizingPath];
}

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex {
    if (textView != _previewTextView) return NO;
    NSURL *url = [link isKindOfClass:[NSURL class]] ? link : [NSURL URLWithString:[link description]];
    if (!url) return NO;
    BOOL editing = ([NSApp currentEvent].modifierFlags & NSEventModifierFlagCommand) != 0;
    [self followPreviewLink:url editing:editing];
    return YES;
}

- (void)followPreviewLink:(NSURL *)url editing:(BOOL)editing {
    if ([self _isThisFile:url]) {
        if (editing) {
            self.showsPreview = NO;
            [self.view.window makeFirstResponder:_textView];
            [self _placeCaretAtFragment:url.fragment];
        } else if (url.fragment.length && ![self revealPreviewAnchor:url.fragment]) {
            NSBeep();
        }
        return;
    }
    if ([_linkDelegate codeEditor:self openLink:url editing:editing]) return;
    [[NSWorkspace sharedWorkspace] openURL:url];
}

/// VS Code's #L12, #L12,3 (or #12,3) of a link to a place in a file: the
/// caret there, its line in the middle of the view.
- (void)_placeCaretAtFragment:(nullable NSString *)fragment {
    NSScanner *scanner = fragment ? [NSScanner scannerWithString:fragment] : nil;
    [scanner scanString:@"L" intoString:NULL];
    NSInteger line = 0, column = 1;
    if (![scanner scanInteger:&line] || line < 1) return;
    if ([scanner scanString:@"," intoString:NULL] && ![scanner scanInteger:&column]) column = 1;
    UDTextModel *model = _textStorage.textModel;
    line = MIN(line, [model getLineCount]);
    column = MAX(1, MIN(column, [model getLineMaxColumn:line]));
    NSRange caret = NSMakeRange((NSUInteger)[model getOffsetAt:line column:column], 0);
    [_textView setSelectedRange:caret];
    [_textView scrollRangeToVisible:caret];
    [_textView centerSelectionInVisibleArea:nil];
}

- (BOOL)revealPreviewAnchor:(NSString *)anchor {
    NSTextStorage *text = _previewTextView.textStorage;
    NSString *wanted = (anchor.stringByRemovingPercentEncoding ?: anchor).lowercaseString;
    NSRange found = NSMakeRange(NSNotFound, 0), range = NSMakeRange(0, 0);
    for (NSUInteger at = 0; at < text.length; at = NSMaxRange(range)) {
        id value = [text attribute:UDPreviewAnchorAttributeName atIndex:at effectiveRange:&range];
        if ([value isKindOfClass:[NSString class]] && [[value lowercaseString] isEqualToString:wanted]) {
            found = range;
            break;
        }
    }
    if (found.location == NSNotFound) return NO;
    // the heading at the top, the text laid out and the view its height first
    // (GNUstep sizes it only when it is drawn)
    NSLayoutManager *lm = _previewTextView.layoutManager;
    (void)[lm glyphRangeForTextContainer:_previewTextView.textContainer];
    [_previewTextView sizeToFit];
    NSRange glyphs = [lm glyphRangeForCharacterRange:NSMakeRange(found.location, 0) actualCharacterRange:NULL];
    NSRect line = [lm lineFragmentRectForGlyphAtIndex:glyphs.location effectiveRange:NULL];
    [_previewTextView scrollPoint:NSMakePoint(0, MAX(0.0, NSMinY(line) + _previewTextView.textContainerOrigin.y - 8.0))];
    [_previewTextView setSelectedRange:NSMakeRange(found.location, 0)];
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Find
// ---------------------------------------------------------------------------

- (BOOL)isFindBarVisible {
    return _findBar != nil && ![_findBarHost isHidden];
}

- (void)showFindBarReplacing:(BOOL)replacing {
    (void)self.view;
    self.showsPreview = NO;
    if (!_findBar) {
        _findModel = [[UDFindModel alloc] initWithTextModel:_textStorage.textModel];
        _findBar = [[UDFindBarViewController alloc] initWithFindModel:_findModel textView:_textView];
        _findBar.delegate = self;
        NSView *bar = _findBar.view;
        bar.frame = _findBarHost.bounds;
        bar.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [_findBarHost addSubview:bar];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_findMatchesChanged:)
                                                     name:UDFindModelDidChangeNotification
                                                   object:_findModel];
    }
    _findBarHost.hidden = NO;
    _findBar.replacing = replacing;    // asks for its height
    NSRange selection = _textView.selectedRange;
    NSString *selected = nil;
    if (selection.length > 0 && selection.length < 200) {
        selected = [_textStorage.string substringWithRange:selection];
        if ([selected rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound) selected = nil;
    }
    [_findBar focusWithSearchString:selected];
}

- (void)findBar:(UDFindBarViewController *)findBar wantsHeight:(CGFloat)height {
    _findBarHeight = height;
    [self _layoutBars];
}

- (void)findBarDidClose:(UDFindBarViewController *)findBar {
    [_findModel clear];
    _findBarHost.hidden = YES;
    [self _layoutBars];
    [self.view.window makeFirstResponder:_textView];
}

- (BOOL)showsJumpBar {
    return _jumpBar && ![_jumpBar isHidden];
}

- (void)setShowsJumpBar:(BOOL)showsJumpBar {
    (void)self.view;
    if (showsJumpBar == self.showsJumpBar) return;
    [_jumpBar setHidden:!showsJumpBar];
    [self _layoutBars];
}

- (void)setAccessoryViewController:(NSViewController *)accessoryViewController {
    (void)self.view;
    if (accessoryViewController == _accessoryViewController) return;
    NSView *before = _accessoryViewController.view;
    if (before.superview == _bodySplitView) {
        _accessoryHeight = NSHeight(before.frame);
        [before removeFromSuperview];
    }
    _accessoryViewController = accessoryViewController;
    NSView *view = accessoryViewController.view;
    if (!view) {
        [_bodySplitView adjustSubviews];
        return;
    }
    // under the text: as tall as it was, else a third
    CGFloat total = NSHeight(_bodySplitView.bounds), divider = _bodySplitView.dividerThickness;
    CGFloat height = _accessoryHeight > 0 ? _accessoryHeight : floor(total / 3);
    height = MIN(height, MAX(total - 80 - divider, 0));
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_bodySplitView addSubview:view];
    [_bodySplitView adjustSubviews];
    [_bodySplitView setPosition:total - height - divider ofDividerAtIndex:0];
}

/// The jump bar on top, the Find bar under it (as Xcode's); the text takes the rest.
- (void)_layoutBars {
    NSRect bounds = self.view.bounds;
    CGFloat top = NSMaxY(bounds), width = NSWidth(bounds);
    if (self.showsJumpBar) {
        CGFloat height = NSHeight(_jumpBar.frame);
        _jumpBar.frame = NSMakeRect(0, top - height, width, height);
        top -= height;
    }
    if (self.isFindBarVisible) {
        _findBarHost.frame = NSMakeRect(0, top - _findBarHeight, width, _findBarHeight);
        top -= _findBarHeight;
    }
    _bodySplitView.frame = NSMakeRect(0, 0, width, top);
    [self.view setNeedsDisplay:YES];
}

// ---------------------------------------------------------------------------
// MARK: - Jump to Line
// ---------------------------------------------------------------------------

- (BOOL)isJumpToLineVisible {
    return _jumpToLine.isShown;
}

/// The box over the top of the text (Xcode's), laid over it.
- (void)showJumpToLine {
    (void)self.view;
    self.showsPreview = NO;
    if (!_jumpToLine) {
        _jumpToLine = [[UDJumpToLineViewController alloc] init];
        _jumpToLine.delegate = self;
    }
    [_jumpToLine showOverView:_editorArea lineCount:[_textStorage.textModel getLineCount]];
}

- (void)_hideJumpToLine {
    [_jumpToLine close];
    [self.view.window makeFirstResponder:_textView];
}

- (void)jumpToLine:(UDJumpToLineViewController *)controller didChooseLine:(NSInteger)line {
    [self _hideJumpToLine];
    [self selectLine:line];
}

- (void)jumpToLineDidCancel:(UDJumpToLineViewController *)controller {
    [self _hideJumpToLine];
}

- (void)selectLine:(NSInteger)line {
    self.showsPreview = NO;
    UDTextModel *model = _textStorage.textModel;
    line = MAX(1, MIN(line, [model getLineCount]));
    NSUInteger start = (NSUInteger)[model getOffsetAt:line column:1];
    NSUInteger end = (NSUInteger)[model getOffsetAt:line column:[model getLineMaxColumn:line]];
    NSRange range = NSMakeRange(start, end - start);
    [_textView setSelectedRange:range];
    [_textView scrollRangeToVisible:range];
    [_textView centerSelectionInVisibleArea:nil];
}

- (void)revealLine:(NSInteger)line {
    (void)self.view;
    self.showsPreview = NO;
    UDTextModel *model = _textStorage.textModel;
    line = MAX(1, MIN(line, [model getLineCount]));
    NSLayoutManager *lm = _textView.layoutManager;
    NSRange glyphs = [lm glyphRangeForCharacterRange:NSMakeRange((NSUInteger)[model getOffsetAt:line column:1], 0)
                                actualCharacterRange:NULL];
    NSRect lineRect = [lm lineFragmentRectForGlyphAtIndex:MIN(glyphs.location, MAX([lm numberOfGlyphs], 1) - 1)
                                           effectiveRange:NULL];
    lineRect.origin.y += _textView.textContainerOrigin.y;
    NSRect visible = _textView.visibleRect;
    if (NSMinY(lineRect) >= NSMinY(visible) && NSMaxY(lineRect) <= NSMaxY(visible)) return;
    // Out of view: in the middle of it.
    NSPoint origin = NSMakePoint(NSMinX(visible), MAX(0.0, NSMidY(lineRect) - NSHeight(visible) / 2.0));
    [_textView scrollPoint:origin];
}

/// The matches changed: their highlights, and their marks in the gutter.
- (void)_findMatchesChanged:(NSNotification *)note {
    [_textStorage applyDecorationHighlights];
    UDTextModel *model = _textStorage.textModel;
    NSInteger lines = [model getLineCount];
    NSArray<UDIntervalNode *> *matches = [_findModel matchNodes];
    NSMutableArray<NSNumber *> *fractions = [NSMutableArray arrayWithCapacity:matches.count];
    for (UDIntervalNode *node in matches) {
        CGFloat line = (CGFloat)([model getPositionAt:node.start].line - 1);
        [fractions addObject:@(MAX(0.0, MIN(1.0, line / (CGFloat)MAX(lines, 1))))];
    }
    _gutterView.matchFractions = fractions;
}

// The text view forwards the Find menu (NSTextFinderAction tags).
- (void)performFindAction:(NSInteger)action {
    switch (action) {
        case 1:  [self showFindBarReplacing:NO]; break;                       // show find
        case 12: [self showFindBarReplacing:YES]; break;                      // show replace
        case 2:  if (!_findBar) [self showFindBarReplacing:NO]; else [_findBar findNext:nil]; break;
        case 3:  if (!_findBar) [self showFindBarReplacing:NO]; else [_findBar findPrevious:nil]; break;
        case 4:  [_findBar replaceAll:nil]; break;
        case 5:
        case 6:  [_findBar replace:nil]; break;
        case 7: {                                                             // use selection for find
            NSRange selection = _textView.selectedRange;
            if (selection.length == 0) break;
            [self showFindBarReplacing:_findBar.isReplacing];
            [_findBar focusWithSearchString:[_textStorage.string substringWithRange:selection]];
            [self.view.window makeFirstResponder:_textView];
            break;
        }
        case 11: [self findBarDidClose:_findBar]; break;                      // hide find
        case 13: _findBar.replacing = NO; break;                              // hide replace
        default: NSBeep(); break;
    }
}

- (BOOL)canPerformFindAction:(NSInteger)action {
    switch (action) {
        case 1: case 12: return YES;
        case 2: case 3: return YES;
        case 4: case 5: case 6: return self.isFindBarVisible && _findModel.matchCount > 0;
        case 7: return _textView.selectedRange.length > 0;
        case 11: return self.isFindBarVisible;
        case 13: return self.isFindBarVisible && _findBar.isReplacing;
        default: return NO;
    }
}

@end
