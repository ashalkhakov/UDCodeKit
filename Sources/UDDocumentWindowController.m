#import "UDDocumentWindowController.h"
#import "UDDocument.h"
#import "UDTextModelTextStorage.h"
#import "UDTextEditorViewController.h"
#import "UDErrorsViewController.h"
#import "UDLSPCoordinator.h"
#import "UDLSPDiagnosticHighlighter.h"
#import "UDLSPServerLocator.h"
#import "TreeSitterTheme.h"
#import "UDMissingNodeHighlighter.h"
#import "UDParseErrorHighlighter.h"
#import "UDParseErrorCollector.h"
#import "UDDiagnosticStore.h"
#import "UDDiagnosticItem.h"
#import "tree_sitter_json.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// ---------------------------------------------------------------------------
// MARK: - Module-level constants
// ---------------------------------------------------------------------------

static CGFloat const kErrorsPaneWidth = 180.0;

static NSToolbarItemIdentifier const kToolbarAddTab    = @"addEditorTab";
static NSToolbarItemIdentifier const kToolbarOpenInTab = @"openFileInNewTab";

static void * const kTabSelectionKVOContext = (void *)&kTabSelectionKVOContext;

/// Default content for a blank new-document tab.
static NSString * const kDefaultNewDocumentText =
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
// MARK: - UDEditorTabContext  (private — lives entirely in this translation unit)
// ---------------------------------------------------------------------------

/// Encapsulates all per-document state for one editor tab (or a group of tabs
/// that all show the same document).
///
/// Multiple UDTextEditorViewControllers may be wired to the same context: each
/// adds its own NSLayoutManager to the shared UDTextModelTextStorage, so edits
/// in any view appear immediately in all others.
///
/// Lifecycle:
///   1. -initWithContent:fileURL:        — create before any editor VC loads.
///   2. -activateWithTheme:…             — call AFTER the first editor VC's
///      -viewDidLoad has run so its layout manager is attached to textStorage
///      before the first tree-sitter parse fires.
///   3. Set lspCoordinator if available.
@interface UDEditorTabContext : NSObject

@property (nonatomic, strong, readonly) UDTextModelTextStorage  *textStorage;
@property (nonatomic, strong, readonly) UDDiagnosticStore       *diagnosticStore;
/// File URL this context is editing, or nil for an unsaved scratch buffer.
@property (nonatomic, copy,   readonly, nullable) NSURL         *fileURL;
/// Display title derived from fileURL.lastPathComponent, or "Untitled".
@property (nonatomic, copy,   readonly)           NSString      *tabTitle;
/// Optional LSP coordinator; set by the owner after -activateWithTheme:…
@property (nonatomic, strong, nullable)           UDLSPCoordinator *lspCoordinator;

- (instancetype)initWithContent:(NSString *)content
                        fileURL:(nullable NSURL *)fileURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Wire tree-sitter, run the first parse, and start the diagnostic pipeline.
/// MUST be called after at least one editor VC's -viewDidLoad has executed.
- (void)activateWithTheme:(nullable TreeSitterTheme *)theme
             languageFunc:(LanguageFunc)languageFunc
          highlightsQuery:(NSString *)highlightsQuery;

@end

// ---- Private extension ----

@interface UDEditorTabContext ()
@property (nonatomic, strong) UDMissingNodeHighlighter *missingNodeHighlighter;
@property (nonatomic, strong) UDParseErrorHighlighter  *parseErrorHighlighter;
@property (nonatomic, strong) UDParseErrorCollector    *parseErrorCollector;
@end

@implementation UDEditorTabContext

- (instancetype)initWithContent:(NSString *)content fileURL:(NSURL *)fileURL {
    self = [super init];
    if (!self) return nil;
    _textStorage     = [[UDTextModelTextStorage alloc] initWithText:content ?: @""];
    _diagnosticStore = [[UDDiagnosticStore alloc] init];
    _fileURL         = [fileURL copy];
    _tabTitle        = fileURL.lastPathComponent ?: @"Untitled";
    return self;
}

- (void)activateWithTheme:(TreeSitterTheme *)theme
             languageFunc:(LanguageFunc)languageFunc
          highlightsQuery:(NSString *)highlightsQuery {
    if (theme) _textStorage.theme = theme;
    [_textStorage setLanguageFunc:languageFunc withHighlightsQuery:highlightsQuery];

    UDTreeSitterHighlighter *hl = _textStorage.highlighter;
    _missingNodeHighlighter =
        [[UDMissingNodeHighlighter alloc] initWithTextStorage:_textStorage highlighter:hl];
    [_missingNodeHighlighter update];

    _parseErrorHighlighter =
        [[UDParseErrorHighlighter alloc] initWithTextStorage:_textStorage highlighter:hl];
    [_parseErrorHighlighter update];

    _parseErrorCollector =
        [[UDParseErrorCollector alloc] initWithTextStorage:_textStorage
                                                highlighter:hl
                                                      store:_diagnosticStore];
    [_parseErrorCollector update];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_textStorageDidEdit:)
               name:NSTextStorageDidProcessEditingNotification
             object:_textStorage];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_textStorageDidEdit:(NSNotification *)note {
    NSTextStorage *ts = note.object;
    if (!(ts.editedMask & NSTextStorageEditedCharacters)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_missingNodeHighlighter update];
        [self->_parseErrorHighlighter  update];
        [self->_parseErrorCollector    update];
    });
}

@end

// ---------------------------------------------------------------------------
// MARK: - UDDocumentWindowController  (private extension)
// ---------------------------------------------------------------------------

@interface UDDocumentWindowController () <NSTextViewDelegate, NSToolbarDelegate>

/// Parallel to _editorTabViewController.tabViewItems: _tabContexts[i] is the
/// context for tab i.  The SAME context may appear at multiple indices (when
/// the user opens a second view of an already-open file).
@property (nonatomic, strong) NSMutableArray<UDEditorTabContext *> *tabContexts;

@property (nonatomic, strong) NSTabViewController   *editorTabViewController;
@property (nonatomic, strong) UDErrorsViewController *errorsViewController;

/// Diagnostic stores we have already registered NSNotificationCenter observers
/// for.  Prevents duplicate callbacks when a context appears in more than one tab.
@property (nonatomic, strong) NSMutableSet<UDDiagnosticStore *> *observedStores;

/// Cached theme (used when adding new tabs after initial load).
@property (nonatomic, strong) TreeSitterTheme *currentTheme;

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

    UDWorkspace *workspace = (UDWorkspace *)self.document;

    _tabContexts    = [NSMutableArray array];
    _observedStores = [NSMutableSet set];

    // 1. Resolve the effective colour theme.
    NSAppearanceName best =
        [NSApp.effectiveAppearance
            bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,
                                                NSAppearanceNameDarkAqua]];
    BOOL dark = [best isEqualToString:NSAppearanceNameDarkAqua];
    _currentTheme = [[TreeSitterTheme alloc] initWithMode:dark];

    // 2. Build the tab view controller and the errors panel BEFORE setting
    //    contentViewController, so the view hierarchy is live when the first
    //    editor VC's -viewDidLoad runs.
    _editorTabViewController = [[NSTabViewController alloc] init];
    _editorTabViewController.tabStyle = NSTabViewControllerTabStyleSegmentedControlOnTop;

    // Placeholder diagnostic store for the errors panel; rebound after tabs open.
    _errorsViewController =
        [[UDErrorsViewController alloc] initWithDiagnosticStore:
            [[UDDiagnosticStore alloc] init]];

    NSSplitViewController *splitVC = [[NSSplitViewController alloc] init];
    NSSplitViewItem *errorsItem =
        [NSSplitViewItem splitViewItemWithViewController:_errorsViewController];
    errorsItem.minimumThickness = kErrorsPaneWidth;
    errorsItem.maximumThickness = kErrorsPaneWidth;
    [splitVC addSplitViewItem:errorsItem];
    [splitVC addSplitViewItem:
        [NSSplitViewItem splitViewItemWithViewController:_editorTabViewController]];
    self.contentViewController = splitVC;

    // 3. Open workspace tabs.
    NSArray<NSURL *> *tabURLs = workspace.initialTabURLs;
    if (tabURLs.count > 0) {
        for (NSURL *url in tabURLs) {
            NSError *err = nil;
            NSString *content = [NSString stringWithContentsOfURL:url
                                                         encoding:NSUTF8StringEncoding
                                                            error:&err];
            if (!content) {
                NSLog(@"[UDDocumentWindowController] Cannot open %@: %@",
                      url.lastPathComponent, err);
                content = @"";  // open empty tab rather than silently dropping it
            }
            [self _openNewTabWithContent:content
                                 fileURL:url
                                   label:url.lastPathComponent];
        }
        // Wire the workspace to the first tab's storage so Cmd+S works for
        // the plain-file case (single JSON opened directly).
        workspace.primaryTextStorage = _tabContexts.firstObject.textStorage;
    } else {
        // Fresh workspace — open one blank editor tab.
        [self _openNewTabWithContent:kDefaultNewDocumentText
                             fileURL:nil
                               label:@"Untitled"];
    }

    // 4. Bind the errors panel to the first (active) tab's store.
    UDEditorTabContext *firstCtx = _tabContexts.firstObject;
    [_errorsViewController bindToStore:firstCtx.diagnosticStore
                           displayName:firstCtx.tabTitle];

    // 5. Window title — workspace filename or generic name.
    self.window.title = workspace.fileURL
        ? workspace.fileURL.lastPathComponent
        : @"Untitled Workspace";

    // 6. Toolbar with "New Tab" and "Open in New Tab" items.
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"UDEditorToolbar"];
    toolbar.delegate             = self;
    toolbar.displayMode          = NSToolbarDisplayModeIconOnly;
    toolbar.allowsUserCustomization = NO;
    self.window.toolbar = toolbar;

    // 7. KVO: rebind the errors panel when the active tab changes.
    [_editorTabViewController addObserver:self
                               forKeyPath:@"selectedTabViewItemIndex"
                                  options:NSKeyValueObservingOptionNew
                                  context:kTabSelectionKVOContext];
}

// ---------------------------------------------------------------------------
// MARK: - Tab management — public actions
// ---------------------------------------------------------------------------

- (IBAction)addEditorTab:(nullable id)sender {
    NSUInteger n     = _editorTabViewController.tabViewItems.count + 1;
    NSString  *label = [NSString stringWithFormat:@"Untitled %lu", (unsigned long)n];
    [self _openNewTabWithContent:kDefaultNewDocumentText fileURL:nil label:label];
}

- (IBAction)openFileInNewTab:(nullable id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles          = YES;
    panel.canChooseDirectories    = NO;
    panel.allowsMultipleSelection = YES;
    if (@available(macOS 11.0, *)) {
        panel.allowedContentTypes = @[UTTypeJSON];
    } else {
        panel.allowedFileTypes = @[@"json"];
    }
    [panel beginSheetModalForWindow:self.window
                  completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        for (NSURL *url in panel.URLs) {
            [self openURLInNewTab:url];
        }
    }];
}

- (void)openURLInNewTab:(NSURL *)url {
    // If this file is already open, add a new *view* of the same context so
    // edits in the two tabs are immediately synchronised.
    for (UDEditorTabContext *ctx in _tabContexts) {
        if ([ctx.fileURL isEqual:url]) {
            [self _addViewTabForContext:ctx];
            return;
        }
    }

    // New file — create an independent context.
    NSError  *err     = nil;
    NSString *content = [NSString stringWithContentsOfURL:url
                                                 encoding:NSUTF8StringEncoding
                                                    error:&err];
    if (!content) {
        NSLog(@"[UDDocumentWindowController] Cannot open %@: %@",
              url.lastPathComponent, err);
        return;
    }
    [self _openNewTabWithContent:content fileURL:url label:url.lastPathComponent];
}

// ---------------------------------------------------------------------------
// MARK: - Workspace state (used by UDWorkspace for serialisation)
// ---------------------------------------------------------------------------

- (NSArray<NSURL *> *)currentOpenFileURLs {
    NSMutableArray<NSURL *> *seen = [NSMutableArray array];
    for (UDEditorTabContext *ctx in _tabContexts) {
        if (ctx.fileURL && ![seen containsObject:ctx.fileURL]) {
            [seen addObject:ctx.fileURL];
        }
    }
    return [seen copy];
}

// ---------------------------------------------------------------------------
// MARK: - Tab management — private helpers
// ---------------------------------------------------------------------------

/// Create a brand-new context + editor VC, activate the context, and add a
/// tab.  The caller can immediately access the new tab as the last item in
/// _editorTabViewController.tabViewItems.
- (void)_openNewTabWithContent:(NSString *)content
                       fileURL:(nullable NSURL *)fileURL
                         label:(NSString *)label {
    // a. Build context.
    UDEditorTabContext *ctx =
        [[UDEditorTabContext alloc] initWithContent:content fileURL:fileURL];

    // b. Wire an editor VC.  Calling -view forces -viewDidLoad which attaches
    //    a new NSLayoutManager to ctx.textStorage.  This MUST happen before
    //    -activateWithTheme:… fires the first parse.
    UDTextEditorViewController *editorVC =
        [[UDTextEditorViewController alloc] initWithTextStorage:ctx.textStorage];
    [self _configureEditorVC:editorVC];     // forces -viewDidLoad

    // c. Activate: first parse, diagnostic pipeline, edit notifications.
    [ctx activateWithTheme:_currentTheme
              languageFunc:(LanguageFunc)tree_sitter_json
           highlightsQuery:kJSONHighlightsQuery];

    // d. LSP coordinator.
    [self _setupLSPCoordinatorForContext:ctx];

    // e. Register diagnostics observer (once per unique store).
    if (![_observedStores containsObject:ctx.diagnosticStore]) {
        [_observedStores addObject:ctx.diagnosticStore];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(_diagnosticsDidChange:)
                   name:UDDiagnosticsDidChangeNotification
                 object:ctx.diagnosticStore];
    }

    // f. Track and display.
    [_tabContexts addObject:ctx];
    [self _appendTabItem:label viewController:editorVC identifier:
        fileURL.absoluteString
            ?: [NSString stringWithFormat:@"untitled-%lu",
                (unsigned long)_editorTabViewController.tabViewItems.count + 1]];
}

/// Add a second (or further) view of an already-active context.  The new tab
/// shares the context's textStorage, diagnosticStore, and lspCoordinator;
/// edits in either tab appear immediately in both.
- (void)_addViewTabForContext:(UDEditorTabContext *)ctx {
    UDTextEditorViewController *editorVC =
        [[UDTextEditorViewController alloc] initWithTextStorage:ctx.textStorage];
    [self _configureEditorVC:editorVC];  // adds another NSLayoutManager to shared storage

    [_tabContexts addObject:ctx];        // same context object, new slot

    NSUInteger n = _editorTabViewController.tabViewItems.count + 1;
    [self _appendTabItem:ctx.tabTitle
          viewController:editorVC
              identifier:[NSString stringWithFormat:@"%@-view%lu",
                          ctx.fileURL.absoluteString ?: @"untitled", (unsigned long)n]];
}

/// Low-level: create an NSTabViewItem and append it, then select it.
- (void)_appendTabItem:(NSString *)label
        viewController:(NSViewController *)vc
            identifier:(NSString *)identifier {
    NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:identifier];
    tab.label          = label;
    tab.viewController = vc;
    [_editorTabViewController addTabViewItem:tab];
    _editorTabViewController.selectedTabViewItemIndex =
        (NSInteger)(_editorTabViewController.tabViewItems.count - 1);
}

- (UDEditorTabContext *)_activeContext {
    NSInteger  idx = _editorTabViewController.selectedTabViewItemIndex;
    NSUInteger i   = (idx >= 0) ? (NSUInteger)idx : 0;
    return (i < _tabContexts.count) ? _tabContexts[i] : _tabContexts.firstObject;
}

/// Configure a freshly created editor VC:
///   • Forces -viewDidLoad (attaches its NSLayoutManager to textStorage).
///   • Sets this window controller as the text-view delegate (LSP).
///   • Configures the auto-indenter for JSON.
- (void)_configureEditorVC:(UDTextEditorViewController *)vc {
    (void)vc.view;    // triggers -viewDidLoad
    vc.textView.delegate = self;
    [vc.autoIndenter configureWithLanguageFunc:(LanguageFunc)tree_sitter_json
                                  indentsQuery:kJSONIndentsQuery];
}

// ---------------------------------------------------------------------------
// MARK: - LSP setup
// ---------------------------------------------------------------------------

- (void)_setupLSPCoordinatorForContext:(UDEditorTabContext *)ctx {
    NSURL *docURL = ctx.fileURL
        ?: [NSURL fileURLWithPath:
               [NSTemporaryDirectory()
                   stringByAppendingPathComponent:@"untitled.json"]];

    NSString *serverPath = [UDLSPServerLocator findJSONLanguageServerPath];
    if (!serverPath) {
        NSLog(@"[UDDocumentWindowController] No JSON language server found; "
              @"LSP inactive for \"%@\".", ctx.tabTitle);
        return;
    }

    UDTextModelTextStorage *ts = ctx.textStorage;
    LSPClient *client =
        [[LSPClient alloc] initWithPath:serverPath
                              arguments:@[@"--stdio"]
                   currentDirectoryPath:docURL.URLByDeletingLastPathComponent.path
                             languageID:@"json"];

    UDLSPDiagnosticHighlighter *lspHL =
        [[UDLSPDiagnosticHighlighter alloc] initWithTextStorage:ts
                                                     highlighter:ts.highlighter
                                                           store:ctx.diagnosticStore];
    ctx.lspCoordinator =
        [[UDLSPCoordinator alloc] initWithTextStorage:ts
                                               client:client
                                          documentURL:docURL
                                diagnosticHighlighter:lspHL];
    [ctx.lspCoordinator openDocument:[ts.textModel getValue]];
}

// ---------------------------------------------------------------------------
// MARK: - Save notifications (called by UDWorkspace)
// ---------------------------------------------------------------------------

- (void)documentWillSave {
    [_tabContexts.firstObject.lspCoordinator documentWillSave];
}

- (void)documentDidSave:(BOOL)success {
    [_tabContexts.firstObject.lspCoordinator documentDidSave];
    if (!success) {
        NSLog(@"[UDDocumentWindowController] File save failed; "
              @"LSP server has been notified of the save attempt.");
    }
}

// ---------------------------------------------------------------------------
// MARK: - Close
// ---------------------------------------------------------------------------

- (void)close {
    // Remove KVO before any other teardown to avoid callbacks during shutdown.
    @try {
        [_editorTabViewController removeObserver:self
                                      forKeyPath:@"selectedTabViewItemIndex"
                                         context:kTabSelectionKVOContext];
    } @catch (NSException *) {}

    // Close each unique context's LSP coordinator exactly once.
    NSMutableSet<UDEditorTabContext *> *seen = [NSMutableSet set];
    for (UDEditorTabContext *ctx in _tabContexts) {
        if (![seen containsObject:ctx]) {
            [ctx.lspCoordinator closeDocument];
            [seen addObject:ctx];
        }
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super close];
}

// ---------------------------------------------------------------------------
// MARK: - KVO  (tab selection → rebind errors panel)
// ---------------------------------------------------------------------------

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if (context == kTabSelectionKVOContext) {
        UDEditorTabContext *ctx = [self _activeContext];
        if (ctx) [_errorsViewController bindToStore:ctx.diagnosticStore
                                        displayName:ctx.tabTitle];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

// ---------------------------------------------------------------------------
// MARK: - NSTextViewDelegate  (LSP pre-change tracking)
// ---------------------------------------------------------------------------

// The window controller is the NSTextViewDelegate for ALL editor text views.
// Only the focused (active) tab's view can have focus, so we forward to the
// active context's coordinator.  All tabs share the same storage, so changes
// from any tab are visible everywhere.
- (BOOL)textView:(NSTextView *)textView
    shouldChangeTextInRange:(NSRange)affectedCharRange
          replacementString:(nullable NSString *)replacementString {
    [[self _activeContext].lspCoordinator
        textWillChangeInRange:affectedCharRange
            replacementString:replacementString ?: @""];
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - UDDiagnosticsDidChangeNotification
// ---------------------------------------------------------------------------

- (void)_diagnosticsDidChange:(NSNotification *)note {
    UDDiagnosticStore       *store = (UDDiagnosticStore *)note.object;
    NSArray<UDDiagnosticItem *> *all  = store.allDiagnostics;
    NSArray<NSTabViewItem *>    *items = _editorTabViewController.tabViewItems;

    // Update every tab that uses this store (there may be more than one if the
    // same document is open in multiple tabs).
    for (NSUInteger i = 0; i < MIN(_tabContexts.count, items.count); i++) {
        if (_tabContexts[i].diagnosticStore != store) continue;

        UDTextEditorViewController *editorVC =
            (UDTextEditorViewController *)items[i].viewController;
        [self _updateGutterErrorMarks:all
                           forEditorVC:editorVC
                               context:_tabContexts[i]];

        NSTextView *tv = editorVC.textView;
        [tv.layoutManager
            invalidateLayoutForCharacterRange:NSMakeRange(0, _tabContexts[i].textStorage.length)
                         actualCharacterRange:nil];
        [tv setNeedsDisplay:YES];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Gutter error marks
// ---------------------------------------------------------------------------

- (void)_updateGutterErrorMarks:(NSArray<UDDiagnosticItem *> *)diagnostics
                     forEditorVC:(UDTextEditorViewController *)editorVC
                         context:(UDEditorTabContext *)ctx {
    NSInteger    totalLines = [ctx.textStorage.textModel getLineCount];
    UDFindResultsGutterView *gutter = editorVC.gutterView;
    if (totalLines <= 0) { gutter.errorFractions = @[]; return; }

    NSMutableArray<NSNumber *> *fracs =
        [NSMutableArray arrayWithCapacity:diagnostics.count];
    for (UDDiagnosticItem *item in diagnostics) {
        CGFloat frac = (CGFloat)(item.line - 1) / (CGFloat)totalLines;
        [fracs addObject:@(MAX(0.0, MIN(1.0, frac)))];
    }
    gutter.errorFractions = fracs;
}

// ---------------------------------------------------------------------------
// MARK: - NSToolbarDelegate
// ---------------------------------------------------------------------------

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {

    if ([itemIdentifier isEqualToString:kToolbarAddTab]) {
        NSToolbarItem *item =
            [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label        = @"New Tab";
        item.paletteLabel = @"New Editor Tab";
        item.toolTip      = @"Open a new blank editor tab";
        item.image        = [NSImage imageWithSystemSymbolName:@"plus.square"
                                       accessibilityDescription:@"New tab"];
        item.target       = self;
        item.action       = @selector(addEditorTab:);
        return item;
    }

    if ([itemIdentifier isEqualToString:kToolbarOpenInTab]) {
        NSToolbarItem *item =
            [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label        = @"Open in Tab";
        item.paletteLabel = @"Open File in New Tab";
        item.toolTip      = @"Open a file in a new editor tab";
        item.image        = [NSImage imageWithSystemSymbolName:@"plus.rectangle.on.folder"
                                       accessibilityDescription:@"Open file in new tab"];
        item.target       = self;
        item.action       = @selector(openFileInNewTab:);
        return item;
    }

    return nil;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarFlexibleSpaceItemIdentifier, kToolbarOpenInTab, kToolbarAddTab];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[kToolbarAddTab, kToolbarOpenInTab,
             NSToolbarFlexibleSpaceItemIdentifier, NSToolbarSpaceItemIdentifier];
}

@end
