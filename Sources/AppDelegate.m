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

    // --- Resize scroll view to leave room for both gutters and the search bar ---
    // The XIB placed the scroll view at (0,0,W,H); we shrink and shift it.
    NSScrollView *sv = (NSScrollView *)self.textView.enclosingScrollView;
    CGFloat svX = kLineGutterWidth;
    CGFloat svW = W - kLineGutterWidth - kFindGutterWidth;
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

    // --- Line-number gutter (left strip) ---
    _lineNumberGutterView =
        [[UDLineNumberGutterView alloc]
             initWithScrollView:sv
                       textView:self.textView
                      textModel:_textStorage.textModel];
    _lineNumberGutterView.frame =
        NSMakeRect(0, 0, kLineGutterWidth, editorH);
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

    // Re-run folding + bracket match after each document change.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_documentDidChange:)
               name:NSTextStorageDidProcessEditingNotification
             object:_textStorage];
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
