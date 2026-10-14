#import "UDCodeEditorViewController.h"
#import "UDLineNumberGutterView.h"
#import "UDFoldingController.h"
#import "UDBracketMatchHighlighter.h"
#import "UDStructuredNavigator.h"
#import "UDAutoIndenter.h"
#import "UDTreeSitterHighlighter.h"
#import "UDTextModelTextStorage.h"
#import <UDPieceTable/UDPieceTable.h>

// ---------------------------------------------------------------------------
// MARK: - Layout constants (private to this file)
// ---------------------------------------------------------------------------

static CGFloat const kEditorFindGutterWidth = 12.0;

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface UDCodeEditorViewController () <NSSearchFieldDelegate,
                                          UDLineNumberGutterViewDelegate>

// IBOutlets wired from UDCodeEditorViewController.xib.
@property (nonatomic, weak) IBOutlet NSScrollView         *scrollView;
@property (nonatomic, weak) IBOutlet UDDiagnosticTextView *textView;
@property (nonatomic, weak) IBOutlet NSSearchField        *findField;

// Created programmatically in -viewDidLoad.
@property (nonatomic, weak)   UDFindResultsGutterView *gutterView;
@property (nonatomic, strong) UDLineNumberGutterView   *lineNumberGutterView;
@property (nonatomic, strong) UDFoldingController      *foldingController;
@property (nonatomic, strong) UDBracketMatchHighlighter *bracketMatchHighlighter;
@property (nonatomic, strong) UDStructuredNavigator    *structuredNavigator;
@property (nonatomic, strong) UDAutoIndenter           *autoIndenter;

// Text-model state.
@property (nonatomic, strong) UDTextModelTextStorage   *textStorage;
@property (nonatomic, strong) NSArray<NSString *>      *findDecorationIDs;

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
        _textStorage       = textStorage;
        _findDecorationIDs = @[];
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

    // 3. Compute frames from the initial XIB bounds.
    NSView  *container = self.view;
    CGFloat  W         = NSWidth(container.bounds);
    CGFloat  H         = NSHeight(container.bounds);
    CGFloat  findH     = NSHeight(_findField.frame);
    CGFloat  editorH   = H - findH;

    // 4. Stretch find field to full width.
    NSRect ff   = _findField.frame;
    ff.origin.x = 0;
    ff.size.width = W;
    _findField.frame = ff;

    // 5. Shrink scroll view to leave room for both gutters.
    CGFloat svX = UDLineNumberGutterWidth;
    CGFloat svW = W - svX - kEditorFindGutterWidth;
    _scrollView.frame        = NSMakeRect(svX, 0, svW, editorH);
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // 6. Find-results / error-marks gutter (right edge).
    UDFindResultsGutterView *findGutter =
        [[UDFindResultsGutterView alloc]
             initWithFrame:NSMakeRect(W - kEditorFindGutterWidth, 0,
                                      kEditorFindGutterWidth, editorH)];
    findGutter.autoresizingMask =
        NSViewMinXMargin | NSViewHeightSizable | NSViewMaxYMargin;
    [container addSubview:findGutter];
    _gutterView = findGutter;

    // 7. Line-number gutter (left of scroll view).
    _lineNumberGutterView =
        [[UDLineNumberGutterView alloc]
             initWithScrollView:_scrollView
                       textView:_textView
                      textModel:_textStorage.textModel];
    _lineNumberGutterView.frame =
        NSMakeRect(0, 0, UDLineNumberGutterWidth, editorH);
    _lineNumberGutterView.autoresizingMask =
        NSViewMaxXMargin | NSViewHeightSizable | NSViewMaxYMargin;
    _lineNumberGutterView.delegate = self;
    [container addSubview:_lineNumberGutterView];

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

    // 13. Find field setup.
    _findField.delegate = self;
    _findField.target   = self;
    _findField.action   = @selector(_findFieldDidChange:);
    ((NSSearchFieldCell *)_findField.cell).sendsSearchStringImmediately = YES;

    // 14. Observe text-storage edits for folding, bracket match, and find.
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

    // Refresh find highlights if a query is active.
    if (_findField.stringValue.length > 0) {
        [self _findFieldDidChange:_findField];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_foldingController update];
        [self->_bracketMatchHighlighter update];
    });
}

// ---------------------------------------------------------------------------
// MARK: - UDLineNumberGutterViewDelegate
// ---------------------------------------------------------------------------

- (void)lineNumberGutterView:(UDLineNumberGutterView *)view
    didClickFoldIndicatorAtLine:(NSInteger)lineNumber {
    [_foldingController toggleFoldAtLine:lineNumber];
}

// ---------------------------------------------------------------------------
// MARK: - NSSearchFieldDelegate / Find
// ---------------------------------------------------------------------------

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == _findField) [self _findFieldDidChange:_findField];
}

- (void)_findFieldDidChange:(id)sender {
    NSString    *query = _findField.stringValue;
    UDTextModel *model = _textStorage.textModel;

    if (query.length == 0) {
        _findDecorationIDs =
            [model deltaDecorations:_findDecorationIDs
                     newDecorations:@[]
                              owner:UDFindDecorationOwner];
        [_textStorage applyDecorationHighlights];
        _gutterView.matchFractions = @[];
        return;
    }

    NSArray<UDFindMatch *> *matches =
        [model findMatches:query
                   isRegex:NO
                 matchCase:NO
            wordSeparators:nil
          limitResultCount:500];

    NSMutableArray<UDModelDeltaDecoration *> *newDecors =
        [NSMutableArray arrayWithCapacity:matches.count];
    for (UDFindMatch *m in matches) {
        UDDecorationOptions *opts =
            [[UDDecorationOptions alloc] initWithClassName:@"find" userInfo:nil];
        UDModelDeltaDecoration *d =
            [[UDModelDeltaDecoration alloc] initWithRange:m.range options:opts];
        d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
        [newDecors addObject:d];
    }

    _findDecorationIDs =
        [model deltaDecorations:_findDecorationIDs
                 newDecorations:newDecors
                          owner:UDFindDecorationOwner];
    [_textStorage applyDecorationHighlights];

    NSInteger totalLines = [model getLineCount];
    if (totalLines <= 0) { _gutterView.matchFractions = @[]; return; }
    NSMutableArray<NSNumber *> *fracs = [NSMutableArray arrayWithCapacity:matches.count];
    for (UDFindMatch *m in matches) {
        CGFloat frac = (CGFloat)(m.range.startLineNumber - 1) / (CGFloat)totalLines;
        [fracs addObject:@(MAX(0.0, MIN(1.0, frac)))];
    }
    _gutterView.matchFractions = fracs;
}

@end
