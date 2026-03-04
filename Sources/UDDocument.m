/*---------------------------------------------------------------------------------------------
 *  UDDocument.m — NSDocument implementation for the TestApp.
 *
 *  The window controller and all editor components that used to live in
 *  AppDelegate now live here so each document gets its own independent stack.
 *
 *  Tree-sitter error output (UDErrorsViewController on the left panel +
 *  UDMissingNodeHighlighter orange pills) is preserved exactly as before.
 *  LSP diagnostics from UDLSPCoordinator are strictly ADDITIVE: they appear as
 *  a red/yellow background (layer 5 in UDTextModelTextStorage) plus inline
 *  labels drawn by UDDiagnosticTextView.
 *--------------------------------------------------------------------------------------------*/

#import "UDDocument.h"
#import "UDTextModelTextStorage.h"
#import "UDDiagnosticTextView.h"
#import "UDLSPCoordinator.h"
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
// MARK: - Layout constants (match the old AppDelegate values)
// ---------------------------------------------------------------------------

static CGFloat const kSearchBarHeight  = 28.0;
static CGFloat const kFindGutterWidth  = 12.0;
static CGFloat const kLineGutterWidth  = 48.0;
static CGFloat const kErrorsViewWidth  = 180.0;
static CGFloat const kWindowWidth      = 900.0;
static CGFloat const kWindowHeight     = 600.0;

// Virtual key codes (Carbon values, duplicated to avoid importing Carbon).
static const unsigned short kKeyCodeUpArrow      = 126;
static const unsigned short kKeyCodeDownArrow    = 125;
static const unsigned short kKeyCodeLeftArrow    = 123;
static const unsigned short kKeyCodeRightArrow   = 124;
static const unsigned short kKeyCodeReturn       = 36;
static const unsigned short kKeyCodeKeypadReturn = 76;

// ---------------------------------------------------------------------------
// MARK: - Initial demo text
// ---------------------------------------------------------------------------

static NSString * const kInitialText =
    @"{\n"
    @"  \"name\": \"UDPieceTable\",\n"
    @"  \"version\": 1,\n"
    @"  \"description\": \"Piece-table editor with Tree-sitter + LSP.\",\n"
    @"  \"features\": [\n"
    @"    \"piece-table editing\",\n"
    @"    \"incremental parsing\",\n"
    @"    \"syntax highlighting\"\n"
    @"  ],\n"
    @"  \"isAwesome\": true,\n"
    @"  \"author\": null\n"
    @"}";

// JSON grammar queries (unchanged from AppDelegate).
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

@interface UDDocument () <NSTextViewDelegate,
                           UDLineNumberGutterViewDelegate,
                           NSSearchFieldDelegate,
                           UDLSPCoordinatorDelegate>

// Core editor components.
@property (nonatomic, strong) UDTextModelTextStorage    *textStorage;
@property (nonatomic, strong) UDDiagnosticTextView      *textView;

// Text read from file before the window is built; consumed in _buildEditorWindow.
@property (nonatomic, copy, nullable) NSString          *initialText;

// Window and accessory views.
@property (nonatomic, strong) NSWindow                  *editorWindow;
@property (nonatomic, strong) NSSearchField             *findField;
@property (nonatomic, strong) UDFindResultsGutterView   *gutterView;
@property (nonatomic, strong) UDLineNumberGutterView    *lineNumberGutterView;

// Editor feature controllers.
@property (nonatomic, strong) UDFoldingController       *foldingController;
@property (nonatomic, strong) UDBracketMatchHighlighter *bracketMatchHighlighter;
@property (nonatomic, strong) UDMissingNodeHighlighter  *missingNodeHighlighter;
@property (nonatomic, strong) UDStructuredNavigator     *structuredNavigator;
@property (nonatomic, strong) UDAutoIndenter            *autoIndenter;
@property (nonatomic, strong) UDErrorsViewController    *errorsViewController;

// Find state.
@property (nonatomic, strong) NSArray<NSString *>       *findDecorationIDs;

// LSP coordinator — strictly additive, no change to tree-sitter output.
@property (nonatomic, strong, nullable) UDLSPCoordinator *lspCoordinator;

@end

// ---------------------------------------------------------------------------

@implementation UDDocument

// ---------------------------------------------------------------------------
// MARK: - NSDocument init
// ---------------------------------------------------------------------------

- (instancetype)init {
    self = [super init];
    if (self) {
        _findDecorationIDs = @[];
    }
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - Read / write
// ---------------------------------------------------------------------------

- (BOOL)readFromURL:(NSURL *)url
             ofType:(NSString *)typeName
              error:(NSError **)outError {
    NSString *content = [NSString stringWithContentsOfURL:url
                                                 encoding:NSUTF8StringEncoding
                                                    error:outError];
    if (!content) return NO;

    if (_textStorage) {
        // Already loaded (window is open); replace text.
        UDTextModel *model = _textStorage.textModel;
        NSString    *old   = [model getValue];
        UDPosition   sp    = [model getPositionAt:0];
        UDPosition   ep    = [model getPositionAt:(NSInteger)old.length];
        UDRange      r     = PTRangeMake(sp.line, sp.column, ep.line, ep.column);
        UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:r text:content];
        [model applyEdits:@[edit]];
    } else {
        // First read — text stored for window controller to pick up.
        self.initialText = [content copy];
    }
    return YES;
}

- (BOOL)writeToURL:(NSURL *)url
            ofType:(NSString *)typeName
             error:(NSError **)outError {
    NSString *text = _textStorage ? [_textStorage.textModel getValue] : @"";
    return [text writeToURL:url
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:outError];
}

- (BOOL)writeSafelyToURL:(NSURL *)url
                  ofType:(NSString *)typeName
        forSaveOperation:(NSSaveOperationType)op
                   error:(NSError **)outError {
    if (_lspCoordinator) [_lspCoordinator documentWillSave];
    BOOL ok = [super writeSafelyToURL:url ofType:typeName
                      forSaveOperation:op error:outError];
    if (ok && _lspCoordinator) [_lspCoordinator documentDidSave];
    return ok;
}

// ---------------------------------------------------------------------------
// MARK: - Window controllers
// ---------------------------------------------------------------------------

- (void)makeWindowControllers {
    [self _buildEditorWindow];
    NSWindowController *wc = [[NSWindowController alloc]
                                initWithWindow:_editorWindow];
    [self addWindowController:wc];
}

// ---------------------------------------------------------------------------
// MARK: - Window / view construction
// ---------------------------------------------------------------------------

- (void)_buildEditorWindow {
    // 1. Text storage + theme.
    NSString *initialContent = self.initialText ?: kInitialText;
    self.initialText = nil; // release memory once used

    _textStorage = [[UDTextModelTextStorage alloc] initWithText:initialContent];

    NSAppearanceName best =
        [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
             @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [best isEqualToString:NSAppearanceNameDarkAqua];
    _textStorage.theme = [[TreeSitterTheme alloc] initWithMode:dark];

    [_textStorage setLanguageFunc:(LanguageFunc)tree_sitter_json
               withHighlightsQuery:kJSONHighlightsQuery];

    // 2. Window.
    NSRect frame = NSMakeRect(100, 100, kWindowWidth, kWindowHeight);
    NSWindowStyleMask style = NSWindowStyleMaskTitled       |
                              NSWindowStyleMaskClosable     |
                              NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskResizable;
    _editorWindow = [[NSWindow alloc] initWithContentRect:frame
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    NSString *title = self.fileURL ? self.fileURL.lastPathComponent : @"Untitled";
    _editorWindow.title = title;

    NSView *content = _editorWindow.contentView;
    CGFloat W = NSWidth(content.bounds);
    CGFloat H = NSHeight(content.bounds);
    CGFloat editorH = H - kSearchBarHeight;

    // 3. Build text view.
    _textView = [[UDDiagnosticTextView alloc]
                     initWithFrame:NSMakeRect(0, 0, 400, 400)];
    _textView.richText             = NO;
    _textView.importsGraphics      = NO;
    _textView.allowsUndo           = YES;
    _textView.autoresizingMask     = NSViewWidthSizable | NSViewHeightSizable;
    _textView.delegate             = self;
    _textView.documentText         = initialContent;

    // Wire our text storage into the text view's layout chain.
    NSLayoutManager *lm = _textView.layoutManager;
    [[lm textStorage] removeLayoutManager:lm];
    [_textStorage addLayoutManager:lm];

    // 4. Scroll view.
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    sv.documentView          = _textView;
    sv.hasVerticalScroller   = YES;
    sv.hasHorizontalScroller = NO;
    sv.autohidesScrollers    = YES;
    sv.borderType            = NSNoBorder;

    CGFloat svX = kErrorsViewWidth + kLineGutterWidth;
    CGFloat svW = W - kErrorsViewWidth - kLineGutterWidth - kFindGutterWidth;
    sv.frame           = NSMakeRect(svX, 0, svW, editorH);
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:sv];

    // 5. Find-results gutter.
    _gutterView = [[UDFindResultsGutterView alloc]
                   initWithFrame:NSMakeRect(W - kFindGutterWidth, 0,
                                            kFindGutterWidth, editorH)];
    _gutterView.autoresizingMask =
        NSViewMinXMargin | NSViewHeightSizable | NSViewMaxYMargin;
    [content addSubview:_gutterView];

    // 6. Search field.
    _findField = [[NSSearchField alloc]
                  initWithFrame:NSMakeRect(0, editorH, W, kSearchBarHeight)];
    _findField.placeholderString = @"Find…";
    _findField.autoresizingMask  = NSViewWidthSizable | NSViewMinYMargin;
    _findField.delegate = self;
    _findField.target   = self;
    _findField.action   = @selector(_findFieldDidChange:);
    ((NSSearchFieldCell *)_findField.cell).sendsSearchStringImmediately = YES;
    [content addSubview:_findField];

    // 7. Line-number gutter.
    _lineNumberGutterView =
        [[UDLineNumberGutterView alloc]
             initWithScrollView:sv
                       textView:_textView
                      textModel:_textStorage.textModel];
    _lineNumberGutterView.frame =
        NSMakeRect(kErrorsViewWidth, 0, kLineGutterWidth, editorH);
    _lineNumberGutterView.autoresizingMask =
        NSViewMaxXMargin | NSViewHeightSizable | NSViewMaxYMargin;
    _lineNumberGutterView.delegate = self;
    [content addSubview:_lineNumberGutterView];

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

    // 10. MISSING-node pill highlighter (tree-sitter, unchanged).
    _missingNodeHighlighter =
        [[UDMissingNodeHighlighter alloc] initWithTextStorage:_textStorage
                                                   highlighter:_textStorage.highlighter];
    [_missingNodeHighlighter update];

    // 11. Structured navigator.
    _structuredNavigator =
        [[UDStructuredNavigator alloc] initWithTextView:_textView
                                             highlighter:_textStorage.highlighter
                                               textModel:_textStorage.textModel];

    // 12. Auto-indenter.
    _autoIndenter =
        [[UDAutoIndenter alloc] initWithTextView:_textView
                                      highlighter:_textStorage.highlighter
                                        textModel:_textStorage.textModel];
    [_autoIndenter configureWithLanguageFunc:(LanguageFunc)tree_sitter_json
                                indentsQuery:kJSONIndentsQuery];

    // 13. Tree-sitter errors panel (left side — UNCHANGED).
    _errorsViewController =
        [[UDErrorsViewController alloc] initWithHighlighter:_textStorage.highlighter];
    NSView *errorsView = _errorsViewController.view;
    errorsView.frame = NSMakeRect(0, 0, kErrorsViewWidth, editorH);
    errorsView.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
    [content addSubview:errorsView];
    [_errorsViewController update];
    [self _updateGutterErrorMarks];

    // 14. Key monitor for structured navigation + auto-indent.
    __weak typeof(self) weakSelf = self;
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                          handler:^NSEvent *(NSEvent *event) {
        UDDocument *doc = weakSelf;
        if (!doc) return event;
        if (doc->_textView.window.firstResponder != doc->_textView) return event;

        NSEventModifierFlags relevantMods =
            event.modifierFlags & (NSEventModifierFlagCommand  |
                                   NSEventModifierFlagControl  |
                                   NSEventModifierFlagOption   |
                                   NSEventModifierFlagShift);
        if (relevantMods == 0) {
            switch (event.keyCode) {
                case kKeyCodeReturn:
                case kKeyCodeKeypadReturn:
                    if ([doc->_autoIndenter handleReturnKey]) return nil;
                    return event;
            }
        }
        if (event.modifierFlags & NSEventModifierFlagOption) {
            switch (event.keyCode) {
                case kKeyCodeUpArrow:    [doc->_structuredNavigator moveToParent];      return nil;
                case kKeyCodeDownArrow:  [doc->_structuredNavigator moveToFirstChild];  return nil;
                case kKeyCodeLeftArrow:  [doc->_structuredNavigator moveToPrevSibling]; return nil;
                case kKeyCodeRightArrow: [doc->_structuredNavigator moveToNextSibling]; return nil;
            }
        }
        return event;
    }];

    // 15. Re-run features after text changes.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_textStorageDidEdit:)
               name:NSTextStorageDidProcessEditingNotification
             object:_textStorage];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_documentDidChange:)
               name:NSTextStorageDidProcessEditingNotification
             object:_textStorage];

    // 16. LSP coordinator — purely additive on top of tree-sitter.
    [self _setupLSPCoordinator:initialContent];

    [_editorWindow makeKeyAndOrderFront:nil];
}

// ---------------------------------------------------------------------------
// MARK: - LSP setup
// ---------------------------------------------------------------------------

- (void)_setupLSPCoordinator:(NSString *)initialContent {
    // Determine the document URL.  For new (untitled) documents we use a
    // temporary path; the server receives a proper URL when the file is saved.
    NSURL *docURL = self.fileURL;
    if (!docURL) {
        docURL = [NSURL fileURLWithPath:
                  [NSTemporaryDirectory()
                   stringByAppendingPathComponent:@"untitled.json"]];
    }

    // Try to find a JSON language server executable.
    NSString *serverPath = [self _findJSONLanguageServer];
    if (!serverPath) {
        // No server available — LSP layer stays dormant.
        // Tree-sitter errors continue to work normally.
        NSLog(@"[UDDocument] No JSON language server found; LSP layer inactive.");
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

/// Returns the path to a JSON language server or nil if none is found.
- (nullable NSString *)_findJSONLanguageServer {
    // Common installation paths for vscode-json-languageserver.
    NSArray<NSString *> *candidates = @[
        // npm global install (macOS default).
        @"/usr/local/bin/vscode-json-languageserver",
        @"/usr/bin/vscode-json-languageserver",
        // npm install via nvm or homebrew.
        @"/opt/homebrew/bin/vscode-json-languageserver",
        // Yarn global.
        [@"~/.yarn/bin/vscode-json-languageserver" stringByExpandingTildeInPath],
        // npm global via node_modules.
        [@"~/.npm-global/bin/vscode-json-languageserver"
          stringByExpandingTildeInPath],
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if ([fm isExecutableFileAtPath:path]) return path;
    }
    return nil;
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

/// Called *before* a text edit lands in the storage — perfect for informing LSP.
- (BOOL)textView:(NSTextView *)textView
    shouldChangeTextInRange:(NSRange)affectedCharRange
          replacementString:(nullable NSString *)replacementString {
    [_lspCoordinator textWillChangeInRange:affectedCharRange
                         replacementString:replacementString ?: @""];
    return YES; // always allow the edit
}

// ---------------------------------------------------------------------------
// MARK: - UDLSPCoordinatorDelegate
// ---------------------------------------------------------------------------

- (void)lspCoordinator:(UDLSPCoordinator *)coordinator
  didUpdateDiagnostics:(NSArray<LSPDiagnostic *> *)diagnostics
           forDocument:(NSURL *)url {
    // Push diagnostics to the text view for inline label rendering.
    _textView.lspDiagnostics = diagnostics;
    _textView.documentText   = [_textStorage.textModel getValue];
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
    // Keep documentText in sync for inline-label re-layout.
    _textView.documentText = [_textStorage.textModel getValue];
}

- (void)_documentDidChange:(NSNotification *)note {
    NSTextStorage *ts = note.object;
    if (!(ts.editedMask & NSTextStorageEditedCharacters)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Tree-sitter features — UNCHANGED.
        [self->_foldingController update];
        [self->_bracketMatchHighlighter update];
        [self->_missingNodeHighlighter update];
        [self->_errorsViewController update];   // tree-sitter errors panel
        [self _updateGutterErrorMarks];
    });
}

// ---------------------------------------------------------------------------
// MARK: - Find implementation (unchanged logic from AppDelegate)
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
