/*---------------------------------------------------------------------------------------------
 *  AppDelegate.m — TestApp entry point.
 *
 *  - JSON syntax highlighting via tree-sitter + UDTextModelTextStorage
 *  - Find functionality: search field at top, yellow highlights via 'find' decorations,
 *    gutter tick-marks on the right.
 *--------------------------------------------------------------------------------------------*/

#import "AppDelegate.h"
#import "UDTextModelTextStorage.h"
#import "TreeSitterTheme.h"
#import "tree_sitter_json.h"

// ---------------------------------------------------------------------------
// MARK: - Constants
// ---------------------------------------------------------------------------

static CGFloat const kSearchBarHeight  = 28.0;
static CGFloat const kFindGutterWidth  = 12.0;
static CGFloat const kLineGutterWidth  = 48.0; // UDLineNumberGutterWidth
static CGFloat const kErrorsViewWidth  = 180.0;

// macOS virtual key codes for arrow keys (same values as <Carbon/Carbon.h>
// kVK_UpArrow etc., duplicated here to avoid importing Carbon).
static const unsigned short kKeyCodeUpArrow      = 126;
static const unsigned short kKeyCodeDownArrow    = 125;
static const unsigned short kKeyCodeLeftArrow    = 123;
static const unsigned short kKeyCodeRightArrow   = 124;
static const unsigned short kKeyCodeReturn       = 36;  // main-keyboard Return
static const unsigned short kKeyCodeKeypadReturn = 76;  // numeric-keypad Enter

// ---------------------------------------------------------------------------
// MARK: - Initial demo text
// ---------------------------------------------------------------------------

static NSString * const kInitialText =
    @"{\n"
    @"  \"name\": \"UDPieceTable\",\n"
    @"  \"version\": 1,\n"
    @"  \"description\": \"Piece-table text editor with Tree-sitter syntax highlighting.\",\n"
    @"  \"features\": [\n"
    @"    \"piece-table editing\",\n"
    @"    \"incremental parsing\",\n"
    @"    \"syntax highlighting\"\n"
    @"  ],\n"
    @"  \"isAwesome\": true,\n"
    @"  \"author\": null\n"
    @"}";

// highlights.scm for JSON.
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

// indents.scm for JSON: object and array nodes indent their contents.
static NSString * const kJSONIndentsQuery = @"[(object) (array)] @indent";

// ---------------------------------------------------------------------------

@interface AppDelegate ()
@property (strong) IBOutlet NSWindow *window;
// Retained reference to the text storage (the layout-manager chain owns it,
// but we need it for the find implementation).
@property (nonatomic, strong) UDTextModelTextStorage *textStorage;
// IDs of the current 'find' decorations.
@property (nonatomic, strong) NSArray<NSString *> *findDecorationIDs;
@end

@implementation AppDelegate

// ---------------------------------------------------------------------------
// MARK: - Application lifecycle
// ---------------------------------------------------------------------------

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _findDecorationIDs = @[];

    // ------------------------------------------------------------------
    // 1. Create text storage + theme.
    // ------------------------------------------------------------------
    _textStorage = [[UDTextModelTextStorage alloc] initWithText:kInitialText];

    NSAppearanceName bestMatch =
        [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
             @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL darkMode = [bestMatch isEqualToString:NSAppearanceNameDarkAqua];
    _textStorage.theme = [[TreeSitterTheme alloc] initWithMode:darkMode];

    // ------------------------------------------------------------------
    // 2. Wire storage into the existing text view's layout chain.
    // ------------------------------------------------------------------
    NSLayoutManager *lm = [self.textView layoutManager];
    [[lm textStorage] removeLayoutManager:lm];
    [_textStorage addLayoutManager:lm];

    // ------------------------------------------------------------------
    // 3. Activate JSON grammar.
    // ------------------------------------------------------------------
    [_textStorage setLanguageFunc:(LanguageFunc)tree_sitter_json
              withHighlightsQuery:kJSONHighlightsQuery];

    // ------------------------------------------------------------------
    // 4. Build find UI (search field + find-results gutter) programmatically.
    // ------------------------------------------------------------------
    [self _buildFindUI];

    // ------------------------------------------------------------------
    // 5. Build line-number gutter, folding controller, bracket highlighter.
    // ------------------------------------------------------------------
    [self _buildEditorAccessories];

    // ------------------------------------------------------------------
    // 6. Build the errors panel (left side) and populate it.
    // ------------------------------------------------------------------
    [self _buildErrorsView];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Find UI setup
// ---------------------------------------------------------------------------

- (void)_buildFindUI {
    NSView *contentView = self.window.contentView;
    CGFloat W = NSWidth(contentView.bounds);
    CGFloat H = NSHeight(contentView.bounds);

    CGFloat editorH = H - kSearchBarHeight;

    // --- Find-results gutter (right strip, full height below search bar) ---
    _gutterView = [[UDFindResultsGutterView alloc]
                   initWithFrame:NSMakeRect(W - kFindGutterWidth, 0,
                                            kFindGutterWidth, editorH)];
    _gutterView.autoresizingMask =
        NSViewMinXMargin | NSViewHeightSizable | NSViewMaxYMargin;
    [contentView addSubview:_gutterView];

    // --- Resize scroll view to leave room for the errors panel, both gutters,
    //     and the search bar.  The XIB placed the scroll view at (0,0,W,H);
    //     we shrink and shift it.
    NSScrollView *sv = (NSScrollView *)self.textView.enclosingScrollView;
    CGFloat svX = kErrorsViewWidth + kLineGutterWidth;
    CGFloat svW = W - kErrorsViewWidth - kLineGutterWidth - kFindGutterWidth;
    sv.frame = NSMakeRect(svX, 0, svW, editorH);
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // --- Search field (top bar, spanning full width) ---
    _findField = [[NSSearchField alloc]
                  initWithFrame:NSMakeRect(0, editorH, W, kSearchBarHeight)];
    _findField.placeholderString = @"Find…";
    _findField.autoresizingMask  = NSViewWidthSizable | NSViewMinYMargin;
    _findField.delegate = self;
    _findField.target   = self;
    _findField.action   = @selector(_findFieldDidChange:);
    if (@available(macOS 10.0, *)) {
        ((NSSearchFieldCell *)_findField.cell).sendsSearchStringImmediately = YES;
    }
    [contentView addSubview:_findField];

    // Re-run the active search whenever the document text is edited.
    [[NSNotificationCenter defaultCenter]
        removeObserver:self
                  name:NSTextStorageDidProcessEditingNotification
                object:_textStorage];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_textStorageDidEdit:)
               name:NSTextStorageDidProcessEditingNotification
             object:_textStorage];
}

// ---------------------------------------------------------------------------
// MARK: - Editor accessories (line numbers, folding, bracket matching)
// ---------------------------------------------------------------------------

- (void)_buildEditorAccessories {
    NSView   *contentView = self.window.contentView;
    CGFloat   H           = NSHeight(contentView.bounds);
    CGFloat   editorH     = H - kSearchBarHeight;
    NSScrollView *sv      = (NSScrollView *)self.textView.enclosingScrollView;

    // --- Line-number gutter (left of scroll view, right of errors panel) ---
    _lineNumberGutterView =
        [[UDLineNumberGutterView alloc]
             initWithScrollView:sv
                       textView:self.textView
                      textModel:_textStorage.textModel];
    _lineNumberGutterView.frame =
        NSMakeRect(kErrorsViewWidth, 0, kLineGutterWidth, editorH);
    _lineNumberGutterView.autoresizingMask =
        NSViewMaxXMargin | NSViewHeightSizable | NSViewMaxYMargin;
    _lineNumberGutterView.delegate = self;
    [contentView addSubview:_lineNumberGutterView];

    // --- Folding controller ---
    _foldingController =
        [[UDFoldingController alloc] initWithTextView:self.textView
                                          textStorage:_textStorage
                                           highlighter:_textStorage.highlighter];
    _foldingController.lineNumberGutterView = _lineNumberGutterView;
    [_foldingController update];

    // --- Bracket-match highlighter ---
    _bracketMatchHighlighter =
        [[UDBracketMatchHighlighter alloc] initWithTextView:self.textView
                                                textStorage:_textStorage
                                                 highlighter:_textStorage.highlighter];

    // --- MISSING-node pill highlighter ---
    _missingNodeHighlighter =
        [[UDMissingNodeHighlighter alloc] initWithTextStorage:_textStorage
                                                   highlighter:_textStorage.highlighter];
    [_missingNodeHighlighter update];

    // --- Structured navigator ---
    _structuredNavigator =
        [[UDStructuredNavigator alloc] initWithTextView:self.textView
                                             highlighter:_textStorage.highlighter
                                               textModel:_textStorage.textModel];

    // --- Auto-indenter ---
    _autoIndenter =
        [[UDAutoIndenter alloc] initWithTextView:self.textView
                                      highlighter:_textStorage.highlighter
                                        textModel:_textStorage.textModel];
    [_autoIndenter configureWithLanguageFunc:(LanguageFunc)tree_sitter_json
                                indentsQuery:kJSONIndentsQuery];

    // --- Key monitor: Option-arrows (structured navigation) + Return (auto-indent) ---
    // Returns nil to consume the event; returns the original event to pass it through.
    __weak typeof(self) weakSelf = self;
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                          handler:^NSEvent *(NSEvent *event) {
        AppDelegate *strongSelf = weakSelf;
        if (!strongSelf) return event;
        // Only intercept when the text view is first responder.
        if (strongSelf.textView.window.firstResponder != strongSelf.textView) return event;

        // Return / Enter: auto-indent — only for unmodified Return (no Cmd/Ctrl/Option/Shift).
        NSEventModifierFlags relevantMods =
            event.modifierFlags & (NSEventModifierFlagCommand  |
                                   NSEventModifierFlagControl  |
                                   NSEventModifierFlagOption   |
                                   NSEventModifierFlagShift);
        if (relevantMods == 0) {
            switch (event.keyCode) {
                case kKeyCodeReturn:
                case kKeyCodeKeypadReturn:
                    if ([strongSelf->_autoIndenter handleReturnKey]) return nil;
                    return event;
            }
        }

        // Option-arrows: structured navigation (Option modifier required).
        if (event.modifierFlags & NSEventModifierFlagOption) {
            switch (event.keyCode) {
                case kKeyCodeUpArrow:    [strongSelf->_structuredNavigator moveToParent];       return nil;
                case kKeyCodeDownArrow:  [strongSelf->_structuredNavigator moveToFirstChild];   return nil;
                case kKeyCodeLeftArrow:  [strongSelf->_structuredNavigator moveToPrevSibling];  return nil;
                case kKeyCodeRightArrow: [strongSelf->_structuredNavigator moveToNextSibling];  return nil;
            }
        }
        return event;
    }];

    // Re-run folding + bracket match + missing-node after each document change.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_documentDidChange:)
               name:NSTextStorageDidProcessEditingNotification
             object:_textStorage];
}

// ---------------------------------------------------------------------------
// MARK: - Errors view setup
// ---------------------------------------------------------------------------

- (void)_buildErrorsView {
    NSView  *contentView = self.window.contentView;
    CGFloat  H           = NSHeight(contentView.bounds);
    CGFloat  editorH     = H - kSearchBarHeight;

    _errorsViewController =
        [[UDErrorsViewController alloc] initWithHighlighter:_textStorage.highlighter];

    NSView *errorsView = _errorsViewController.view;
    errorsView.frame = NSMakeRect(0, 0, kErrorsViewWidth, editorH);
    // Fixed width on the left; grows vertically with the window.
    errorsView.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
    [contentView addSubview:errorsView];

    // Populate with any errors from the initial parse.
    [_errorsViewController update];
    [self _updateGutterErrorMarks];
}

- (void)_updateGutterErrorMarks {
    UDTextModel *model       = _textStorage.textModel;
    NSInteger    totalLines  = [model getLineCount];
    if (totalLines <= 0) { _gutterView.errorFractions = @[]; return; }

    NSMutableArray<NSNumber *> *fracs =
        [NSMutableArray arrayWithCapacity:_errorsViewController.errors.count];
    for (UDParseErrorItem *err in _errorsViewController.errors) {
        // (line-1)/total mirrors the find-gutter formula so both use the same
        // coordinate space: line 1 → 0.0 (top), last line → just below 1.0.
        CGFloat frac = (CGFloat)(err.line - 1) / (CGFloat)totalLines;
        [fracs addObject:@(MAX(0.0, MIN(1.0, frac)))];
    }
    _gutterView.errorFractions = fracs;
}

// ---------------------------------------------------------------------------
// MARK: - Find implementation
// ---------------------------------------------------------------------------

- (void)_findFieldDidChange:(id)sender {
    NSString *query = [_findField stringValue];
    UDTextModel *model = _textStorage.textModel;

    if (query.length == 0) {
        // Clear all find decorations.
        _findDecorationIDs =
            [model deltaDecorations:_findDecorationIDs
                     newDecorations:@[]
                              owner:UDFindDecorationOwner];
        [_textStorage applyDecorationHighlights];
        _gutterView.matchFractions = @[];
        return;
    }

    // Find all matches (plain text, case-insensitive).
    NSArray<UDFindMatch *> *matches =
        [model findMatches:query
                   isRegex:NO
                 matchCase:NO
            wordSeparators:nil
          limitResultCount:500];

    // Build deltaDecorations from matches.
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

    // Update gutter tick marks.
    [self _updateGutterWithMatches:matches model:model];
}

- (void)_updateGutterWithMatches:(NSArray<UDFindMatch *> *)matches
                           model:(UDTextModel *)model {
    NSInteger totalLines = [model getLineCount];
    if (totalLines <= 0) { _gutterView.matchFractions = @[]; return; }

    NSMutableArray<NSNumber *> *fracs =
        [NSMutableArray arrayWithCapacity:matches.count];
    for (UDFindMatch *m in matches) {
        // startLineNumber is 1-based.
        CGFloat frac = (CGFloat)(m.range.startLineNumber - 1) / (CGFloat)totalLines;
        [fracs addObject:@(MAX(0.0, MIN(1.0, frac)))];
    }
    _gutterView.matchFractions = fracs;
}

// ---------------------------------------------------------------------------
// MARK: - NSSearchFieldDelegate
// ---------------------------------------------------------------------------

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == _findField) {
        [self _findFieldDidChange:_findField];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Re-run find on document change
// ---------------------------------------------------------------------------

- (void)_textStorageDidEdit:(NSNotification *)note {
    NSTextStorage *textStorage = note.object;
    // Only re-search when the string itself changed (not just attributes).
    if (!(textStorage.editedMask & NSTextStorageEditedCharacters)) return;
    if (_findField.stringValue.length == 0) return;
    [self _findFieldDidChange:_findField];
}

// ---------------------------------------------------------------------------
// MARK: - Document change → update folding + bracket match
// ---------------------------------------------------------------------------

- (void)_documentDidChange:(NSNotification *)note {
    NSTextStorage *textStorage = note.object;
    if (!(textStorage.editedMask & NSTextStorageEditedCharacters)) return;
    // Defer until the tree-sitter re-parse (triggered by UDTextModelTextStorage
    // processEditing) has completed and decorations are applied.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_foldingController update];
        [self->_bracketMatchHighlighter update];
        [self->_missingNodeHighlighter update];
        [self->_errorsViewController update];
        [self _updateGutterErrorMarks];
    });
}

// ---------------------------------------------------------------------------
// MARK: - UDLineNumberGutterViewDelegate
// ---------------------------------------------------------------------------

- (void)lineNumberGutterView:(UDLineNumberGutterView *)view
    didClickFoldIndicatorAtLine:(NSInteger)lineNumber {
    [_foldingController toggleFoldAtLine:lineNumber];
}

@end
