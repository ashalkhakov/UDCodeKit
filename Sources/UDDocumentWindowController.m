/*---------------------------------------------------------------------------------------------
 *  UDDocumentWindowController.m
 *
 *  Loaded from UDDocumentWindowController.xib.  -windowDidLoad sets up the
 *  text-storage layer (wired into the text view coming from the XIB), all editor
 *  accessories, and the LSP coordinator.
 *
 *  UDDocument is kept thin: it only reads/writes the file and creates this
 *  controller.  All per-window lifecycle and delegate logic lives here.
 *--------------------------------------------------------------------------------------------*/

#import "UDDocumentWindowController.h"
#import "UDDocument.h"
#import "UDTextModelTextStorage.h"
#import "UDDiagnosticTextView.h"
#import "UDLSPCoordinator.h"
#import "UDLSPServerLocator.h"
#import "TreeSitterTheme.h"
#import "UDFindResultsGutterView.h"
#import "UDLineNumberGutterView.h"
#import "UDFoldingController.h"
#import "UDBracketMatchHighlighter.h"
#import "UDMissingNodeHighlighter.h"
#import "UDStructuredNavigator.h"
#import "UDAutoIndenter.h"
#import "UDErrorsViewController.h"
#import "tree_sitter_json.h"

// ---------------------------------------------------------------------------
// MARK: - Layout constants
// ---------------------------------------------------------------------------

static CGFloat const kFindGutterWidth  = 12.0;
static CGFloat const kLineGutterWidth  = 48.0;
static CGFloat const kErrorsViewWidth  = 180.0;

// Virtual key codes (Carbon values, duplicated to avoid importing Carbon).
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
                                           NSSearchFieldDelegate,
                                           UDLSPCoordinatorDelegate>

// IBOutlets — connected in UDDocumentWindowController.xib.
@property (nonatomic, weak) IBOutlet NSScrollView          *scrollView;
@property (nonatomic, weak) IBOutlet UDDiagnosticTextView  *textView;
@property (nonatomic, weak) IBOutlet NSSearchField         *findField;

// Created in -windowDidLoad.
@property (nonatomic, strong) UDTextModelTextStorage       *textStorage;
@property (nonatomic, strong) UDFindResultsGutterView      *gutterView;
@property (nonatomic, strong) UDLineNumberGutterView       *lineNumberGutterView;
@property (nonatomic, strong) UDFoldingController          *foldingController;
@property (nonatomic, strong) UDBracketMatchHighlighter    *bracketMatchHighlighter;
@property (nonatomic, strong) UDMissingNodeHighlighter     *missingNodeHighlighter;
@property (nonatomic, strong) UDStructuredNavigator        *structuredNavigator;
@property (nonatomic, strong) UDAutoIndenter               *autoIndenter;
@property (nonatomic, strong) UDErrorsViewController       *errorsViewController;
@property (nonatomic, strong) NSArray<NSString *>          *findDecorationIDs;
@property (nonatomic, strong, nullable) UDLSPCoordinator   *lspCoordinator;

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

    // 1. Build text storage from the document's initial content and set the theme.
    NSString *content = doc.initialContent;

    _textStorage = [[UDTextModelTextStorage alloc] initWithText:content];

    // Register the text storage back on the document so writeToURL: can access it.
    doc.textStorage = _textStorage;

    NSAppearanceName best =
        [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
             @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [best isEqualToString:NSAppearanceNameDarkAqua];
    _textStorage.theme = [[TreeSitterTheme alloc] initWithMode:dark];

    [_textStorage setLanguageFunc:(LanguageFunc)tree_sitter_json
               withHighlightsQuery:kJSONHighlightsQuery];

    // 2. Wire the text storage into the text view's layout chain
    //    (the XIB gives us a plain NSLayoutManager backed by a default NSTextStorage;
    //    we replace that with our piece-table storage).
    NSLayoutManager *lm = _textView.layoutManager;
    [[lm textStorage] removeLayoutManager:lm];
    [_textStorage addLayoutManager:lm];

    // 3. Point the text view's diagnostics draw code at the text model.
    _textView.textModel = _textStorage.textModel;

    // 4. Configure the text view.
    _textView.delegate = self;

    // 5. Synchronise the window title.
    NSURL *fileURL = doc.fileURL;
    self.window.title = fileURL ? fileURL.lastPathComponent : @"Untitled";

    // 6. Lay out the accessory views that depend on the scroll view dimensions.
    NSView   *content  = self.window.contentView;
    CGFloat   W        = NSWidth(content.bounds);
    CGFloat   H        = NSHeight(content.bounds);

    // Reconfigure the scroll view frame to leave room for gutters.
    // The XIB places the scroll view at (0,0) full width; we narrow it here.
    CGFloat svX = kErrorsViewWidth + kLineGutterWidth;
    CGFloat svH = H - NSHeight(_findField.frame);
    CGFloat svW = W - svX - kFindGutterWidth;
    _scrollView.frame = NSMakeRect(svX, 0, svW, svH);
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Also resize the find field to stay full width.
    NSRect ff = _findField.frame;
    ff.origin.x = 0;
    ff.size.width = W;
    _findField.frame = ff;

    // 7. Find-results gutter (right strip).
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

    // 11. MISSING-node pill highlighter (tree-sitter — unchanged path).
    _missingNodeHighlighter =
        [[UDMissingNodeHighlighter alloc] initWithTextStorage:_textStorage
                                                   highlighter:_textStorage.highlighter];
    [_missingNodeHighlighter update];

    // 12. Structured navigator.
    _structuredNavigator =
        [[UDStructuredNavigator alloc] initWithTextView:_textView
                                             highlighter:_textStorage.highlighter
                                               textModel:_textStorage.textModel];

    // 13. Auto-indenter.
    _autoIndenter =
        [[UDAutoIndenter alloc] initWithTextView:_textView
                                      highlighter:_textStorage.highlighter
                                        textModel:_textStorage.textModel];
    [_autoIndenter configureWithLanguageFunc:(LanguageFunc)tree_sitter_json
                                indentsQuery:kJSONIndentsQuery];

    // 14. Tree-sitter errors panel (left side — UNCHANGED).
    _errorsViewController =
        [[UDErrorsViewController alloc] initWithHighlighter:_textStorage.highlighter];
    NSView *errorsView = _errorsViewController.view;
    errorsView.frame = NSMakeRect(0, 0, kErrorsViewWidth, svH);
    errorsView.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
    [content addSubview:errorsView];
    [_errorsViewController update];
    [self _updateGutterErrorMarks];

    // 15. Key monitor for structured navigation + auto-indent.
    __weak typeof(self) weakSelf = self;
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                          handler:^NSEvent *(NSEvent *event) {
        UDDocumentWindowController *wc = weakSelf;
        if (!wc) return event;
        if (wc->_textView.window.firstResponder != wc->_textView) return event;

        NSEventModifierFlags mods =
            event.modifierFlags & (NSEventModifierFlagCommand  |
                                   NSEventModifierFlagControl  |
                                   NSEventModifierFlagOption   |
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

    // 16. Re-run tree-sitter features after every character edit.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_textStorageDidEdit:)
               name:NSTextStorageDidProcessEditingNotification
             object:_textStorage];

    // 17. LSP coordinator — additive on top of tree-sitter.
    [self _setupLSPCoordinator:content documentURL:fileURL];
}

// ---------------------------------------------------------------------------
// MARK: - LSP setup
// ---------------------------------------------------------------------------

- (void)_setupLSPCoordinator:(NSString *)initialContent documentURL:(NSURL *)fileURL {
    NSURL *docURL = fileURL;
    if (!docURL) {
        docURL = [NSURL fileURLWithPath:
                  [NSTemporaryDirectory()
                   stringByAppendingPathComponent:@"untitled.json"]];
    }

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

    _lspCoordinator =
        [[UDLSPCoordinator alloc] initWithTextStorage:_textStorage
                                               client:client
                                          documentURL:docURL];
    _lspCoordinator.delegate = self;
    [_lspCoordinator openDocument:initialContent];
}

// ---------------------------------------------------------------------------
// MARK: - Save notifications (called by UDDocument)
// ---------------------------------------------------------------------------

- (void)documentWillSave {
    [_lspCoordinator documentWillSave];
}

- (void)documentDidSave:(BOOL)success {
    // Always inform the LSP server so its internal save-state stays consistent.
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
// MARK: - UDLSPCoordinatorDelegate
// ---------------------------------------------------------------------------

- (void)lspCoordinator:(UDLSPCoordinator *)coordinator
  didUpdateDiagnostics:(NSArray<LSPDiagnostic *> *)diagnostics
           forDocument:(NSURL *)url {
    // Decorations are already in the text model; just redisplay the text view.
    [_textView setNeedsDisplay:YES];
    [_textView.layoutManager
        invalidateLayoutForCharacterRange:NSMakeRange(0, _textStorage.length)
                     actualCharacterRange:nil];
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
        // Tree-sitter features — UNCHANGED.
        [self->_foldingController update];
        [self->_bracketMatchHighlighter update];
        [self->_missingNodeHighlighter update];
        [self->_errorsViewController update];
        [self _updateGutterErrorMarks];
    });
}

// ---------------------------------------------------------------------------
// MARK: - Find implementation
// ---------------------------------------------------------------------------

- (void)_findFieldDidChange:(id)sender {
    NSString    *query = [_findField stringValue];
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

- (void)_updateGutterErrorMarks {
    UDTextModel *model      = _textStorage.textModel;
    NSInteger    totalLines = [model getLineCount];
    if (totalLines <= 0) { _gutterView.errorFractions = @[]; return; }
    NSMutableArray<NSNumber *> *fracs =
        [NSMutableArray arrayWithCapacity:_errorsViewController.errors.count];
    for (UDParseErrorItem *err in _errorsViewController.errors) {
        CGFloat frac = (CGFloat)(err.line - 1) / (CGFloat)totalLines;
        [fracs addObject:@(MAX(0.0, MIN(1.0, frac)))];
    }
    _gutterView.errorFractions = fracs;
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
