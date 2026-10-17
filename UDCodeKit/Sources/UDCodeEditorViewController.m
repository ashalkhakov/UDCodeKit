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
#import <UDPieceTable/UDPieceTable.h>

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface UDCodeEditorViewController () <UDLineNumberGutterViewDelegate, UDFindBarDelegate, UDFindActionHandler, UDJumpToLineDelegate>

// IBOutlets wired from UDCodeEditorViewController.xib.
@property (nonatomic, weak) IBOutlet NSScrollView            *scrollView;
@property (nonatomic, weak) IBOutlet UDDiagnosticTextView    *textView;
@property (nonatomic, weak) IBOutlet NSView                  *findBarHost;
@property (nonatomic, weak) IBOutlet NSView                  *editorArea;
@property (nonatomic, weak) IBOutlet UDLineNumberGutterView  *lineNumberGutterView;
@property (nonatomic, weak) IBOutlet UDFindResultsGutterView *gutterView;

@property (nonatomic, strong, nullable) UDFindBarViewController *findBar;
@property (nonatomic) CGFloat findBarHeight;
@property (nonatomic, strong, nullable) UDJumpToLineViewController *jumpToLine;
@property (nonatomic, strong) UDFoldingController      *foldingController;
@property (nonatomic, strong) UDBracketMatchHighlighter *bracketMatchHighlighter;
@property (nonatomic, strong) UDPlaceholderHighlighter *placeholderHighlighter;
@property (nonatomic, strong) UDStructuredNavigator    *structuredNavigator;
@property (nonatomic, strong) UDAutoIndenter           *autoIndenter;

// Text-model state.
@property (nonatomic, strong) UDTextModelTextStorage   *textStorage;
@property (nonatomic, strong, nullable) UDFindModel    *findModel;

@end

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
    _textView.findActionHandler = self;

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
    [_foldingController update];
    [_bracketMatchHighlighter update];
}

// ---------------------------------------------------------------------------
// MARK: - UDLineNumberGutterViewDelegate
// ---------------------------------------------------------------------------

- (void)lineNumberGutterView:(UDLineNumberGutterView *)view
    didClickFoldIndicatorAtLine:(NSInteger)lineNumber {
    [_foldingController toggleFoldAtLine:lineNumber];
}

// ---------------------------------------------------------------------------
// MARK: - Find
// ---------------------------------------------------------------------------

- (BOOL)isFindBarVisible {
    return _findBar != nil && ![_findBarHost isHidden];
}

- (void)showFindBarReplacing:(BOOL)replacing {
    (void)self.view;
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

/// The Find bar over the editor; the text takes the rest.
- (void)_layoutBars {
    NSRect bounds = self.view.bounds;
    CGFloat top = NSMaxY(bounds), width = NSWidth(bounds);
    if (self.isFindBarVisible) {
        _findBarHost.frame = NSMakeRect(0, top - _findBarHeight, width, _findBarHeight);
        top -= _findBarHeight;
    }
    _editorArea.frame = NSMakeRect(0, 0, width, top);
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
    UDTextModel *model = _textStorage.textModel;
    line = MAX(1, MIN(line, [model getLineCount]));
    NSUInteger start = (NSUInteger)[model getOffsetAt:line column:1];
    NSUInteger end = (NSUInteger)[model getOffsetAt:line column:[model getLineMaxColumn:line]];
    NSRange range = NSMakeRange(start, end - start);
    [_textView setSelectedRange:range];
    [_textView scrollRangeToVisible:range];
    [_textView centerSelectionInVisibleArea:nil];
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
