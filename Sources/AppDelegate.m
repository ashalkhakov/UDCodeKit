/*---------------------------------------------------------------------------------------------
 *  AppDelegate.m — TestApp entry point.
 *
 *  Demonstrates the new UDPieceTable library features:
 *
 *    • UDTextModel as the text-editing back end (EOL auto-detection, UDPieceTree)
 *    • UDIntervalTree-backed decoration range tracking that survives edits:
 *        the yellow highlights follow the searched text even as you type
 *    • findMatches: / findNextMatch:from: / findPreviousMatch:from:
 *    • deltaDecorations:newDecorations:owner: with AlwaysGrowsWhenTypingAtEdges
 *        stickiness so match highlights expand rather than collapse on insertion
 *    • A search-results gutter (right edge) showing every match as a tick mark
 *--------------------------------------------------------------------------------------------*/

#import <UDPieceTable/UDPieceTable.h>
#import "AppDelegate.h"
#import "UDTextModelTextStorage.h"
#import "UDFindResultsGutterView.h"

// ---------------------------------------------------------------------------
// Initial demo text — intentionally contains repeated words to show off search.
// The first EOL is "\n", so UDTextModel will auto-detect LF.
// ---------------------------------------------------------------------------
static NSString * const kInitialText =
    @"Hello, world!\n\n"
    @"This demo showcases the new UDPieceTable features:\n\n"
    @"  \u2022 EOL auto-detection: this text uses LF (\\n) line endings.\n"
    @"  \u2022 UDIntervalTree decoration tracking: find-match highlights\n"
    @"    stay around the searched text even as you type.\n"
    @"  \u2022 AlwaysGrowsWhenTypingAtEdges stickiness: inserting text\n"
    @"    inside a match expands the highlight rather than collapsing it.\n"
    @"  \u2022 find / Find Next / Find Previous with wrap-around.\n"
    @"  \u2022 A search-results gutter on the right edge.\n\n"
    @"Try searching for 'the' or 'find', then type in the editor.\n"
    @"The yellow highlights and gutter ticks update automatically.";

// ---------------------------------------------------------------------------

@interface AppDelegate ()
@property (strong) IBOutlet NSWindow       *window;

// New model-backed text storage
@property (strong) UDTextModelTextStorage  *textStorage;

// Search state
@property (strong) NSArray<UDFindMatch *>  *findMatches;
@property (nonatomic) NSInteger             currentMatchIndex;

// UI (added programmatically)
@property (strong) NSSearchField           *searchField;
@property (strong) UDFindResultsGutterView *gutterView;
@end

@implementation AppDelegate

// ---------------------------------------------------------------------------
// MARK: - Application lifecycle
// ---------------------------------------------------------------------------

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // 1. Create the UDTextModel-backed text storage.
    self.textStorage       = [[UDTextModelTextStorage alloc] initWithText:kInitialText];
    self.findMatches       = @[];
    self.currentMatchIndex = -1;

    // 2. Replace the text view's layout-manager → text-storage chain.
    //    We keep the existing NSLayoutManager and NSTextContainer (which the
    //    NSTextView already owns) and redirect them to our custom storage.
    NSLayoutManager *lm = [self.textView layoutManager];
    [[lm textStorage] removeLayoutManager:lm];
    [self.textStorage addLayoutManager:lm];

    // 3. Share the window's undo manager so Cmd+Z undoes model edits.
    self.textStorage.textModel.undoManager = self.textView.window.undoManager;

    // 4. Build the search bar and gutter programmatically.
    [self _buildSearchBarAndGutter];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Programmatic UI construction
// ---------------------------------------------------------------------------

- (void)_buildSearchBarAndGutter {
    NSView       *contentView = self.window.contentView;
    NSScrollView *scrollView  = self.textView.enclosingScrollView;
    if (!scrollView || !contentView) { return; }

    const CGFloat kBarH    = 32.0;
    const CGFloat kGutterW = 14.0;

    // ── Resize the scroll view to make room ─────────────────────────────────
    NSRect sv = scrollView.frame;

    NSRect newSV = NSMakeRect(sv.origin.x,
                              sv.origin.y + kBarH,
                              sv.size.width - kGutterW,
                              sv.size.height - kBarH);
    scrollView.frame = newSV;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // ── Gutter: right strip, same height as the scroll view ─────────────────
    self.gutterView = [[UDFindResultsGutterView alloc]
        initWithFrame:NSMakeRect(NSMaxX(newSV),
                                 newSV.origin.y,
                                 kGutterW,
                                 newSV.size.height)];
    self.gutterView.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
    [contentView addSubview:self.gutterView];

    // ── Search bar: horizontal strip at the bottom ───────────────────────────
    NSView *bar = [[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, sv.size.width, kBarH)];
    bar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [contentView addSubview:bar];

    CGFloat fieldW = MAX(sv.size.width - 170.0, 80.0);

    NSSearchField *field = [[NSSearchField alloc]
        initWithFrame:NSMakeRect(8, 4, fieldW, 24)];
    field.autoresizingMask  = NSViewWidthSizable;
    field.placeholderString = @"Find… (type to highlight, ◀ ▶ to step)";
    field.target            = self;
    field.action            = @selector(_searchChanged:);
    [bar addSubview:field];
    self.searchField = field;

    NSButton *prevBtn = [NSButton buttonWithTitle:@"\u25C4 Prev"
                                           target:self
                                           action:@selector(_findPrev:)];
    prevBtn.frame             = NSMakeRect(sv.size.width - 162.0, 4, 76, 24);
    prevBtn.autoresizingMask  = NSViewMinXMargin;
    [bar addSubview:prevBtn];

    NSButton *nextBtn = [NSButton buttonWithTitle:@"Next \u25BA"
                                           target:self
                                           action:@selector(_findNext:)];
    nextBtn.frame             = NSMakeRect(sv.size.width - 82.0, 4, 76, 24);
    nextBtn.autoresizingMask  = NSViewMinXMargin;
    [bar addSubview:nextBtn];
}

// ---------------------------------------------------------------------------
// MARK: - Search actions
// ---------------------------------------------------------------------------

- (IBAction)_searchChanged:(NSSearchField *)sender {
    NSString *query = sender.stringValue;
    if (query.length == 0) {
        [self _clearMatches];
    } else {
        [self _runSearchForQuery:query jumpToFirst:YES];
    }
}

- (IBAction)_findNext:(id)sender {
    NSString *query = self.searchField.stringValue;
    if (query.length == 0) { return; }
    if (self.findMatches.count == 0) {
        [self _runSearchForQuery:query jumpToFirst:YES];
        return;
    }
    NSInteger count        = (NSInteger)self.findMatches.count;
    self.currentMatchIndex = (self.currentMatchIndex + 1) % count;
    [self _scrollToCurrentMatch];
}

- (IBAction)_findPrev:(id)sender {
    NSString *query = self.searchField.stringValue;
    if (query.length == 0) { return; }
    if (self.findMatches.count == 0) {
        [self _runSearchForQuery:query jumpToFirst:NO];
        return;
    }
    NSInteger count        = (NSInteger)self.findMatches.count;
    self.currentMatchIndex = (self.currentMatchIndex - 1 + count) % count;
    [self _scrollToCurrentMatch];
}

// ---------------------------------------------------------------------------
// MARK: - Search internals
// ---------------------------------------------------------------------------

- (void)_runSearchForQuery:(NSString *)query jumpToFirst:(BOOL)jumpToFirst {
    UDTextModel *model = self.textStorage.textModel;

    // Find all matches (case-insensitive, literal string).
    self.findMatches = [model findMatches:query
                                  isRegex:NO
                                matchCase:NO
                           wordSeparators:nil
                         limitResultCount:500];

    // Replace the "find" decoration set in the model.
    // Using AlwaysGrowsWhenTypingAtEdges stickiness so that inserting text
    // inside a highlighted match expands the highlight rather than collapsing it.
    NSArray<NSString *> *oldIDs = [model decorationsForOwner:UDFindDecorationOwner];
    NSMutableArray<UDModelDeltaDecoration *> *newDecors =
        [NSMutableArray arrayWithCapacity:self.findMatches.count];
    for (UDFindMatch *m in self.findMatches) {
        UDDecorationOptions *opts = [[UDDecorationOptions alloc]
            initWithClassName:@"find-match" userInfo:nil];
        UDModelDeltaDecoration *d = [[UDModelDeltaDecoration alloc]
            initWithRange:m.range options:opts];
        d.stickiness = UDTrackedRangeAlwaysGrowsWhenTypingAtEdges;
        [newDecors addObject:d];
    }
    [model deltaDecorations:oldIDs newDecorations:newDecors owner:UDFindDecorationOwner];

    // Apply visual yellow-background highlights.
    [self.textStorage applyDecorationHighlights];

    // Update gutter ticks.
    [self _refreshGutter];

    // Jump to first or last match.
    if (self.findMatches.count > 0) {
        self.currentMatchIndex = jumpToFirst ? 0 : (NSInteger)self.findMatches.count - 1;
        [self _scrollToCurrentMatch];
    } else {
        self.currentMatchIndex = -1;
        self.gutterView.currentMatchIndex = -1;
    }
}

- (void)_clearMatches {
    UDTextModel *model  = self.textStorage.textModel;
    NSArray<NSString *> *oldIDs = [model decorationsForOwner:UDFindDecorationOwner];
    [model deltaDecorations:oldIDs newDecorations:@[] owner:UDFindDecorationOwner];
    [self.textStorage applyDecorationHighlights];

    self.findMatches       = @[];
    self.currentMatchIndex = -1;
    self.gutterView.matchFractions    = @[];
    self.gutterView.currentMatchIndex = -1;
}

- (void)_refreshGutter {
    UDTextModel *model   = self.textStorage.textModel;
    NSInteger    docLen  = [model getLength];
    NSMutableArray<NSNumber *> *fracs =
        [NSMutableArray arrayWithCapacity:self.findMatches.count];
    for (UDFindMatch *m in self.findMatches) {
        NSInteger off  = [model getOffsetAt:m.range.startLineNumber
                                     column:m.range.startColumn];
        double    frac = (docLen > 0) ? (double)off / (double)docLen : 0.0;
        [fracs addObject:@(frac)];
    }
    self.gutterView.matchFractions = fracs;
}

- (void)_scrollToCurrentMatch {
    if (self.currentMatchIndex < 0 ||
        (NSUInteger)self.currentMatchIndex >= self.findMatches.count) { return; }

    UDFindMatch  *match    = self.findMatches[(NSUInteger)self.currentMatchIndex];
    UDTextModel  *model    = self.textStorage.textModel;
    NSInteger     startOff = [model getOffsetAt:match.range.startLineNumber
                                         column:match.range.startColumn];
    NSInteger     endOff   = [model getOffsetAt:match.range.endLineNumber
                                         column:match.range.endColumn];
    NSRange sel = NSMakeRange((NSUInteger)startOff, (NSUInteger)(endOff - startOff));
    [self.textView scrollRangeToVisible:sel];
    [self.textView setSelectedRange:sel];
    [self.gutterView setCurrentMatchIndex:self.currentMatchIndex];
}

@end
