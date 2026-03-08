#import "UDDocumentWindowController.h"
#import "UDDocument.h"
#import "UDTextModelTextStorage.h"
#import "UDDiagnosticTextView.h"
#import "UDLSPCoordinator.h"
#import "UDLSPDiagnosticHighlighter.h"
#import "UDLSPServerLocator.h"
#import "TreeSitterTheme.h"
#import "UDFindResultsGutterView.h"
#import "UDLineNumberGutterView.h"
#import "UDFoldingController.h"
#import "UDBracketMatchHighlighter.h"
#import "UDMissingNodeHighlighter.h"
#import "UDParseErrorHighlighter.h"
#import "UDParseErrorCollector.h"
#import "UDDiagnosticStore.h"
#import "UDDiagnosticItem.h"
#import "UDErrorsViewController.h"
#import "UDStructuredNavigator.h"
#import "UDAutoIndenter.h"
#import "tree_sitter_json.h"

// ---------------------------------------------------------------------------
// MARK: - Layout constants
// ---------------------------------------------------------------------------

static CGFloat const kFindGutterWidth = 12.0;
static CGFloat const kLineGutterWidth = 48.0;
static CGFloat const kErrorsViewWidth = 180.0;

static const unsigned short kKeyCodeUpArrow      = 126;
static const unsigned short kKeyCodeDownArrow    = 125;
static const unsigned short kKeyCodeLeftArrow    = 123;
static const unsigned short kKeyCodeRightArrow   = 124;
static const unsigned short kKeyCodeReturn       = 36;
static const unsigned short kKeyCodeKeypadReturn = 76;

// ---------------------------------------------------------------------------

static NSString * const kJSONHighlightsQuery =
    @"(pair\n"
    @"  key: (_) @string.special.key)\n"
    @"(string) @string\n"
    @"(number) @number\n"
    @"[\n"
    @"  (null)\n"
    @"  (true)\n"
    @"  (false)\n"
    @"] @constant.builtin\n"
    @"(escape_sequence) @escape\n"
    @"(comment) @comment\n"
    @"(ERROR) @error";

static NSString * const kJSONIndentsQuery = @"[(object) (array)] @indent";

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface UDDocumentWindowController () <NSTextViewDelegate,
                                           UDLineNumberGutterViewDelegate,
                                           NSSearchFieldDelegate>

// IBOutlets.
@property (nonatomic, weak) IBOutlet NSScrollView         *scrollView;
@property (nonatomic, weak) IBOutlet UDDiagnosticTextView *textView;
@property (nonatomic, weak) IBOutlet NSSearchField        *findField;

// Created in -windowDidLoad.
@property (nonatomic, strong) UDTextModelTextStorage      *textStorage;
@property (nonatomic, strong) UDFindResultsGutterView     *gutterView;
@property (nonatomic, strong) UDLineNumberGutterView      *lineNumberGutterView;
@property (nonatomic, strong) UDFoldingController         *foldingController;
@property (nonatomic, strong) UDBracketMatchHighlighter   *bracketMatchHighlighter;
@property (nonatomic, strong) UDMissingNodeHighlighter    *missingNodeHighlighter;
@property (nonatomic, strong) UDParseErrorHighlighter     *parseErrorHighlighter;
@property (nonatomic, strong) UDParseErrorCollector       *parseErrorCollector;
@property (nonatomic, strong) UDDiagnosticStore           *diagnosticStore;
@property (nonatomic, strong) UDErrorsViewController      *errorsViewController;
@property (nonatomic, strong) UDStructuredNavigator       *structuredNavigator;
@property (nonatomic, strong) UDAutoIndenter              *autoIndenter;
@property (nonatomic, strong) NSArray<NSString *>         *findDecorationIDs;
@property (nonatomic, strong, nullable) UDLSPCoordinator  *lspCoordinator;

@end

// ---------------------------------------------------------------------------

@implementation UDDocumentWindowController

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)init {
    return [super initWithWindowNibName:@"UDDocumentWindowController"];
}

// ---------------------------------------------------------------------------
// MARK: - Lifecycle
// ---------------------------------------------------------------------------

- (void)windowDidLoad {

    [super windowDidLoad];

    _findDecorationIDs = @[];

    UDDocument *doc = (UDDocument *)self.document;

    // 1. Build text storage and apply the theme.
    _textStorage = [[UDTextModelTextStorage alloc] initWithText:doc.initialContent];
    doc.textStorage = _textStorage;

    NSAppearanceName best =
        [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
             @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [best isEqualToString:NSAppearanceNameDarkAqua];
    _textStorage.theme = [[TreeSitterTheme alloc] initWithMode:dark];

    // 2. Wire the layout manager in FIRST, before any parse is triggered,
    //    so that applyDecorationHighlights has a live layout manager to
    //    deliver edited notifications to.
    NSLayoutManager *lm = _textView.layoutManager;
    [[lm textStorage] removeLayoutManager:lm];
    [_textStorage addLayoutManager:lm];

    // 3. Now it is safe to parse — the layout chain is complete and the
    //    initial applyDecorationHighlights will reach the layout manager.
    [_textStorage setLanguageFunc:(LanguageFunc)tree_sitter_json
               withHighlightsQuery:kJSONHighlightsQuery];

    // 4. Configure text view.
    _textView.textModel = _textStorage.textModel;
    _textView.delegate  = self;

    // 4. Configure find field.
    _findField.delegate = self;
    _findField.target   = self;
    _findField.action   = @selector(_findFieldDidChange:);
    ((NSSearchFieldCell *)_findField.cell).sendsSearchStringImmediately = YES;

    // 5. Window title.
    NSURL *fileURL = doc.fileURL;
    self.window.title = fileURL ? fileURL.lastPathComponent : @"Untitled";

    // 6. Layout.
    NSView  *content = self.window.contentView;
    CGFloat  W       = NSWidth(content.bounds);
    CGFloat  H       = NSHeight(content.bounds);

    CGFloat svX = kErrorsViewWidth + kLineGutterWidth;
    CGFloat svH = H - NSHeight(_findField.frame);
    CGFloat svW = W - svX - kFindGutterWidth;
    _scrollView.frame        = NSMakeRect(svX, 0, svW, svH);
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSRect ff    = _findField.frame;
    ff.origin.x  = 0;
    ff.size.width = W;
    _findField.frame = ff;

    // 7. Find-results gutter.
    _gutterView =
        [[UDFindResultsGutterView alloc]
             initWithFrame:NSMakeRect(W - kFindGutterWidth, 0,
                                      kFindGutterWidth, svH)];
    _gutterView.autoresizingMask =
        NSViewMinXMargin | NSViewHeightSizable | NSViewMaxYMargin;
    [content addSubview:_gutterView];

    // 8. Line-number gutter.
    _lineNumberGutterView =
        [[UDLineNumberGutterView alloc]
             initWithScrollView:_scrollView
                       textView:_textView
                      textModel:_textStorage.textModel];
    _lineNumberGutterView.frame =
        NSMakeRect(kErrorsViewWidth, 0, kLineGutterWidth, svH);
    _lineNumberGutterView.autoresizingMask =
        NSViewMaxXMargin | NSViewHeightSizable | NSViewMaxYMargin;
    _lineNumberGutterView.delegate = self;
    [content addSubview:_lineNumberGutterView];

    // 9. Folding controller.
    _foldingController =
        [[UDFoldingController alloc] initWithTextView:_textView
                                          textStorage:_textStorage
                                           highlighter:_textStorage.highlighter];
    _foldingController.lineNumberGutterView = _lineNumberGutterView;
    [_foldingController update];

    // 10. Bracket-match highlighter.
    _bracketMatchHighlighter =
        [[UDBracketMatchHighlighter alloc] initWithTextView:_textView
                                                textStorage:_textStorage
                                                 highlighter:_textStorage.highlighter];

    // 11. MISSING-node highlighter.
    _missingNodeHighlighter =
        [[UDMissingNodeHighlighter alloc] initWithTextStorage:_textStorage
                                                   highlighter:_textStorage.highlighter];
    [_missingNodeHighlighter update];

    // 11a. Parse-error pill highlighter — creates UDParseErrorDecorationOwner
    //      decorations for inline Xcode-style error pills.
    _parseErrorHighlighter =
        [[UDParseErrorHighlighter alloc] initWithTextStorage:_textStorage
                                                  highlighter:_textStorage.highlighter];
    [_parseErrorHighlighter update];

    // 12. Diagnostic store — shared by the parse-error collector and LSP highlighter.
    _diagnosticStore = [[UDDiagnosticStore alloc] init];

    // 13. Parse-error collector — writes tree-sitter errors into the store.
    _parseErrorCollector =
        [[UDParseErrorCollector alloc] initWithTextStorage:_textStorage
                                                highlighter:_textStorage.highlighter
                                                      store:_diagnosticStore];
    [_parseErrorCollector update];

    // 14. Errors panel — observes the store via notification.
    NSView *errorsView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0,
                                                                   kErrorsViewWidth,
                                                                   svH)];
    errorsView.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
    [content addSubview:errorsView];
    [self _setupErrorsPanelInView:errorsView];

    // 15. Structured navigator.
    _structuredNavigator =
        [[UDStructuredNavigator alloc] initWithTextView:_textView
                                             highlighter:_textStorage.highlighter
                                               textModel:_textStorage.textModel];

    // 16. Auto-indenter.
    _autoIndenter =
        [[UDAutoIndenter alloc] initWithTextView:_textView
                                      highlighter:_textStorage.highlighter
                                        textModel:_textStorage.textModel];
    [_autoIndenter configureWithLanguageFunc:(LanguageFunc)tree_sitter_json
                                indentsQuery:kJSONIndentsQuery];

    // 17. Key monitor for structured navigation + auto-indent.
    __weak typeof(self) weakSelf = self;
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                          handler:^NSEvent *(NSEvent *event) {
        UDDocumentWindowController *wc = weakSelf;
        if (!wc) return event;
        if (wc->_textView.window.firstResponder != wc->_textView) return event;

        NSEventModifierFlags mods =
            event.modifierFlags & (NSEventModifierFlagCommand |
                                   NSEventModifierFlagControl |
                                   NSEventModifierFlagOption  |
                                   NSEventModifierFlagShift);
        if (mods == 0) {
            switch (event.keyCode) {
                case kKeyCodeReturn:
                case kKeyCodeKeypadReturn:
                    if ([wc->_autoIndenter handleReturnKey]) return nil;
                    return event;
            }
        }
        if (event.modifierFlags & NSEventModifierFlagOption) {
            switch (event.keyCode) {
                case kKeyCodeUpArrow:
                    [wc->_structuredNavigator moveToParent];      return nil;
                case kKeyCodeDownArrow:
                    [wc->_structuredNavigator moveToFirstChild];  return nil;
                case kKeyCodeLeftArrow:
                    [wc->_structuredNavigator moveToPrevSibling]; return nil;
                case kKeyCodeRightArrow:
                    [wc->_structuredNavigator moveToNextSibling]; return nil;
            }
        }
        return event;
    }];

    // 18. Text-storage edit notification.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_textStorageDidEdit:)
               name:NSTextStorageDidProcessEditingNotification
             object:_textStorage];

    // 19. Diagnostic-store change notification.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_diagnosticsDidChange:)
               name:UDDiagnosticsDidChangeNotification
             object:_diagnosticStore];

    // 20. LSP coordinator.
    [self _setupLSPCoordinator:doc.initialContent documentURL:fileURL];
}

// ---------------------------------------------------------------------------
// MARK: - Errors panel
// ---------------------------------------------------------------------------

/// Builds the diagnostic-list panel inside errorsView using UDErrorsViewController.
/// The controller observes UDDiagnosticsDidChangeNotification on _diagnosticStore
/// and refreshes its outline view automatically.
- (void)_setupErrorsPanelInView:(NSView *)errorsView {
    _errorsViewController =
        [[UDErrorsViewController alloc] initWithDiagnosticStore:_diagnosticStore];
    [self addChildViewController:_errorsViewController];
    NSView *ev = _errorsViewController.view;
    ev.frame             = errorsView.bounds;
    ev.autoresizingMask  = NSViewWidthSizable | NSViewHeightSizable;
    [errorsView addSubview:ev];
}

// ---------------------------------------------------------------------------
// MARK: - LSP setup
// ---------------------------------------------------------------------------

- (void)_setupLSPCoordinator:(NSString *)initialContent documentURL:(NSURL *)fileURL {
    NSURL *docURL = fileURL ?: [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"untitled.json"]];

    NSString *serverPath = [UDLSPServerLocator findJSONLanguageServerPath];
    if (!serverPath) {
        NSLog(@"[UDDocumentWindowController] No JSON language server found; "
              @"LSP layer inactive.  Tree-sitter errors still active.");
        return;
    }

    LSPClient *client =
        [[LSPClient alloc] initWithPath:serverPath
                              arguments:@[@"--stdio"]
                   currentDirectoryPath:docURL.URLByDeletingLastPathComponent.path
                             languageID:@"json"];

    // The LSP diagnostic highlighter owns both decorations and store writes.
    UDLSPDiagnosticHighlighter *lspHighlighter =
        [[UDLSPDiagnosticHighlighter alloc] initWithTextStorage:_textStorage
                                                     highlighter:_textStorage.highlighter
                                                           store:_diagnosticStore];

    _lspCoordinator =
        [[UDLSPCoordinator alloc] initWithTextStorage:_textStorage
                                               client:client
                                          documentURL:docURL
                                diagnosticHighlighter:lspHighlighter];
    [_lspCoordinator openDocument:initialContent];
}

// ---------------------------------------------------------------------------
// MARK: - Save notifications
// ---------------------------------------------------------------------------

- (void)documentWillSave {
    [_lspCoordinator documentWillSave];
}

- (void)documentDidSave:(BOOL)success {
    [_lspCoordinator documentDidSave];
    if (!success) {
        NSLog(@"[UDDocumentWindowController] File save failed; "
              @"LSP server has been notified of the save attempt.");
    }
}

// ---------------------------------------------------------------------------
// MARK: - Close
// ---------------------------------------------------------------------------

- (void)close {
    [_lspCoordinator closeDocument];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super close];
}

// ---------------------------------------------------------------------------
// MARK: - NSTextViewDelegate
// ---------------------------------------------------------------------------

- (BOOL)textView:(NSTextView *)textView
    shouldChangeTextInRange:(NSRange)affectedCharRange
          replacementString:(nullable NSString *)replacementString {
    [_lspCoordinator textWillChangeInRange:affectedCharRange
                         replacementString:replacementString ?: @""];
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - NSTextStorageDidProcessEditingNotification
// ---------------------------------------------------------------------------

- (void)_textStorageDidEdit:(NSNotification *)note {
    NSTextStorage *ts = note.object;
    if (!(ts.editedMask & NSTextStorageEditedCharacters)) return;

    if (_findField.stringValue.length > 0) {
        [self _findFieldDidChange:_findField];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_foldingController update];
        [self->_bracketMatchHighlighter update];
        [self->_missingNodeHighlighter update];
        [self->_parseErrorHighlighter update];
        [self->_parseErrorCollector update];
    });
}

// ---------------------------------------------------------------------------
// MARK: - UDDiagnosticsDidChangeNotification
// ---------------------------------------------------------------------------

- (void)_diagnosticsDidChange:(NSNotification *)note {
    // note.object is _diagnosticStore.
    NSArray<UDDiagnosticItem *> *all = _diagnosticStore.allDiagnostics;

    // Update gutter error marks.
    [self _updateGutterErrorMarksWithDiagnostics:all];

    // Force the text view to re-layout and redraw diagnostic pills.
    [_textView.layoutManager
        invalidateLayoutForCharacterRange:NSMakeRange(0, _textStorage.length)
                     actualCharacterRange:nil];
    [_textView setNeedsDisplay:YES];
}

// ---------------------------------------------------------------------------
// MARK: - Gutter error marks
// ---------------------------------------------------------------------------

- (void)_updateGutterErrorMarksWithDiagnostics:(NSArray<UDDiagnosticItem *> *)diagnostics {
    UDTextModel *model      = _textStorage.textModel;
    NSInteger    totalLines = [model getLineCount];
    if (totalLines <= 0) { _gutterView.errorFractions = @[]; return; }

    NSMutableArray<NSNumber *> *fracs =
        [NSMutableArray arrayWithCapacity:diagnostics.count];
    for (UDDiagnosticItem *item in diagnostics) {
        CGFloat frac = (CGFloat)(item.line - 1) / (CGFloat)totalLines;
        [fracs addObject:@(MAX(0.0, MIN(1.0, frac)))];
    }
    _gutterView.errorFractions = fracs;
}

// ---------------------------------------------------------------------------
// MARK: - Find
// ---------------------------------------------------------------------------

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
    [self _updateGutterWithMatches:matches model:model];
}

- (void)_updateGutterWithMatches:(NSArray<UDFindMatch *> *)matches
                           model:(UDTextModel *)model {
    NSInteger totalLines = [model getLineCount];
    if (totalLines <= 0) { _gutterView.matchFractions = @[]; return; }
    NSMutableArray<NSNumber *> *fracs =
        [NSMutableArray arrayWithCapacity:matches.count];
    for (UDFindMatch *m in matches) {
        CGFloat frac = (CGFloat)(m.range.startLineNumber - 1) / (CGFloat)totalLines;
        [fracs addObject:@(MAX(0.0, MIN(1.0, frac)))];
    }
    _gutterView.matchFractions = fracs;
}

// ---------------------------------------------------------------------------
// MARK: - NSSearchFieldDelegate
// ---------------------------------------------------------------------------

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == _findField) [self _findFieldDidChange:_findField];
}

// ---------------------------------------------------------------------------
// MARK: - UDLineNumberGutterViewDelegate
// ---------------------------------------------------------------------------

- (void)lineNumberGutterView:(UDLineNumberGutterView *)view
    didClickFoldIndicatorAtLine:(NSInteger)lineNumber {
    [_foldingController toggleFoldAtLine:lineNumber];
}

@end
