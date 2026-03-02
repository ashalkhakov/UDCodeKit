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

static CGFloat const kSearchBarHeight = 28.0;
static CGFloat const kGutterWidth     = 12.0;

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
    // 4. Build find UI (search field + gutter) programmatically.
    // ------------------------------------------------------------------
    [self _buildFindUI];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {}

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

    // --- Gutter view (right strip, full height below search bar) ---
    CGFloat editorH = H - kSearchBarHeight;
    _gutterView = [[UDFindResultsGutterView alloc]
                   initWithFrame:NSMakeRect(W - kGutterWidth, 0, kGutterWidth, editorH)];
    _gutterView.autoresizingMask =
        NSViewMinXMargin | NSViewHeightSizable | NSViewMaxYMargin;
    [contentView addSubview:_gutterView];

    // --- Resize scroll view to leave room for the search bar and gutter ---
    // The XIB placed the scroll view at (0,0,W,H); shrink it.
    NSScrollView *sv = (NSScrollView *)self.textView.enclosingScrollView;
    CGFloat svW = W - kGutterWidth;
    sv.frame = NSMakeRect(0, 0, svW, editorH);
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // --- Search field (top bar, spanning full width) ---
    _findField = [[NSSearchField alloc]
                  initWithFrame:NSMakeRect(0, editorH, W, kSearchBarHeight)];
    _findField.placeholderString = @"Find…";
    _findField.autoresizingMask  = NSViewWidthSizable | NSViewMinYMargin;
    _findField.delegate = self;
    // Also fire on every keystroke.
    _findField.target = self;
    _findField.action = @selector(_findFieldDidChange:);
    if (@available(macOS 10.0, *)) {
        ((NSSearchFieldCell *)_findField.cell).sendsSearchStringImmediately = YES;
    }
    [contentView addSubview:_findField];
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

@end
