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

// ---------------------------------------------------------------------------
// MARK: - Constants
// ---------------------------------------------------------------------------

static CGFloat const kErrorsPaneWidth = 180.0;

static NSToolbarItemIdentifier const kToolbarAddEditorTab = @"addEditorTab";

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

@interface UDDocumentWindowController () <NSTextViewDelegate, NSToolbarDelegate>

// Created in -windowDidLoad.
@property (nonatomic, strong) UDTextModelTextStorage     *textStorage;
/// The NSTabViewController that hosts one or more UDTextEditorViewController tabs
/// in the right-hand (editor) pane of the split view.
@property (nonatomic, strong) NSTabViewController        *editorTabViewController;
@property (nonatomic, strong) UDErrorsViewController     *errorsViewController;
@property (nonatomic, strong) UDMissingNodeHighlighter   *missingNodeHighlighter;
@property (nonatomic, strong) UDParseErrorHighlighter    *parseErrorHighlighter;
@property (nonatomic, strong) UDParseErrorCollector      *parseErrorCollector;
@property (nonatomic, strong) UDDiagnosticStore          *diagnosticStore;
@property (nonatomic, strong, nullable) UDLSPCoordinator *lspCoordinator;

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

    UDDocument *doc = (UDDocument *)self.document;
    NSURL      *fileURL = doc.fileURL;

    // 1. Build text storage and apply the theme.
    _textStorage = [[UDTextModelTextStorage alloc] initWithText:doc.initialContent];
    doc.textStorage = _textStorage;

    NSAppearanceName best =
        [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
             @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [best isEqualToString:NSAppearanceNameDarkAqua];
    _textStorage.theme = [[TreeSitterTheme alloc] initWithMode:dark];

    // 2. Create the first editor VC and force view load so the layout manager
    //    is wired BEFORE the first parse is triggered.
    UDTextEditorViewController *firstEditorVC =
        [[UDTextEditorViewController alloc] initWithTextStorage:_textStorage];
    [self _configureEditorVC:firstEditorVC];

    // 3. Now safe to parse — the layout chain is complete.
    [_textStorage setLanguageFunc:(LanguageFunc)tree_sitter_json
               withHighlightsQuery:kJSONHighlightsQuery];

    // 4. Window title.
    self.window.title = fileURL ? fileURL.lastPathComponent : @"Untitled";

    // 5. Diagnostic store — shared by the parse-error collector and LSP.
    _diagnosticStore = [[UDDiagnosticStore alloc] init];

    // 6. MISSING-node pill highlighter.
    _missingNodeHighlighter =
        [[UDMissingNodeHighlighter alloc] initWithTextStorage:_textStorage
                                                   highlighter:_textStorage.highlighter];
    [_missingNodeHighlighter update];

    // 7. Parse-error inline pill highlighter.
    _parseErrorHighlighter =
        [[UDParseErrorHighlighter alloc] initWithTextStorage:_textStorage
                                                  highlighter:_textStorage.highlighter];
    [_parseErrorHighlighter update];

    // 8. Parse-error collector → writes to the diagnostic store.
    _parseErrorCollector =
        [[UDParseErrorCollector alloc] initWithTextStorage:_textStorage
                                                highlighter:_textStorage.highlighter
                                                      store:_diagnosticStore];
    [_parseErrorCollector update];

    // 9. Errors panel view controller.
    _errorsViewController =
        [[UDErrorsViewController alloc] initWithDiagnosticStore:_diagnosticStore];

    // 10. Build the tab view controller that holds all editor tabs.
    //     Using NSTabViewControllerTabStyleTopmost gives a tab bar at the top
    //     of the editor pane.  Each tab item wraps one UDTextEditorViewController;
    //     all tabs share the same UDTextModelTextStorage (via independent
    //     NSLayoutManagers added to the shared storage in -viewDidLoad).
    _editorTabViewController = [[NSTabViewController alloc] init];
    _editorTabViewController.tabStyle =
        NSTabViewControllerTabStyleTopmost;

    NSTabViewItem *firstTab =
        [[NSTabViewItem alloc] initWithIdentifier:@"editor-1"];
    firstTab.label          = @"Editor 1";
    firstTab.viewController = firstEditorVC;
    [_editorTabViewController addTabViewItem:firstTab];

    // 11. Build the two-pane split: errors (left, fixed) + tab editor (right).
    NSSplitViewController *splitVC = [[NSSplitViewController alloc] init];

    NSSplitViewItem *errorsItem =
        [NSSplitViewItem splitViewItemWithViewController:_errorsViewController];
    errorsItem.minimumThickness = kErrorsPaneWidth;
    errorsItem.maximumThickness = kErrorsPaneWidth;
    [splitVC addSplitViewItem:errorsItem];

    NSSplitViewItem *editorItem =
        [NSSplitViewItem splitViewItemWithViewController:_editorTabViewController];
    [splitVC addSplitViewItem:editorItem];

    self.contentViewController = splitVC;

    // 12. Toolbar with "New Editor Tab" button.
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"UDEditorToolbar"];
    toolbar.delegate     = self;
    toolbar.displayMode  = NSToolbarDisplayModeIconOnly;
    toolbar.allowsUserCustomization = NO;
    self.window.toolbar = toolbar;

    // 13. Text-storage edit notification (document-level highlighters only;
    //     the editor VCs each handle their own folding/bracket-match/find).
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_textStorageDidEdit:)
               name:NSTextStorageDidProcessEditingNotification
             object:_textStorage];

    // 14. Diagnostic-store change notification.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_diagnosticsDidChange:)
               name:UDDiagnosticsDidChangeNotification
             object:_diagnosticStore];

    // 15. LSP coordinator.
    [self _setupLSPCoordinator:doc.initialContent documentURL:fileURL];
}

// ---------------------------------------------------------------------------
// MARK: - Tab management
// ---------------------------------------------------------------------------

- (IBAction)addEditorTab:(nullable id)sender {
    NSUInteger n = _editorTabViewController.tabViewItems.count + 1;

    UDTextEditorViewController *newVC =
        [[UDTextEditorViewController alloc] initWithTextStorage:_textStorage];
    [self _configureEditorVC:newVC];

    NSTabViewItem *tab = [[NSTabViewItem alloc]
        initWithIdentifier:[NSString stringWithFormat:@"editor-%lu", (unsigned long)n]];
    tab.label          = [NSString stringWithFormat:@"Editor %lu", (unsigned long)n];
    tab.viewController = newVC;

    [_editorTabViewController addTabViewItem:tab];

    // Switch to the new tab immediately.
    _editorTabViewController.selectedTabViewItemIndex =
        (NSInteger)(_editorTabViewController.tabViewItems.count - 1);
}

/// Returns all UDTextEditorViewController instances currently open as tabs.
- (NSArray<UDTextEditorViewController *> *)_allEditorViewControllers {
    NSMutableArray<UDTextEditorViewController *> *result = [NSMutableArray array];
    for (NSTabViewItem *item in _editorTabViewController.tabViewItems) {
        if ([item.viewController isKindOfClass:[UDTextEditorViewController class]]) {
            [result addObject:(UDTextEditorViewController *)item.viewController];
        }
    }
    return result;
}

/// Shared setup called for every new editor tab VC.
/// Forces the view to load (wires its layout manager to _textStorage),
/// sets this window controller as the NSTextViewDelegate (needed by LSP),
/// and configures the auto-indenter for JSON.
- (void)_configureEditorVC:(UDTextEditorViewController *)vc {
    (void)vc.view; // triggers -viewDidLoad → adds layout manager to _textStorage
    vc.textView.delegate = self;
    [vc.autoIndenter
        configureWithLanguageFunc:(LanguageFunc)tree_sitter_json
                     indentsQuery:kJSONIndentsQuery];
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
// MARK: - NSTextViewDelegate (for LSP pre-change tracking)
// ---------------------------------------------------------------------------

// Called for whichever editor tab's text view has focus.  Since all tabs share
// the same UDTextModelTextStorage the change is reflected in every tab.
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

    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_missingNodeHighlighter update];
        [self->_parseErrorHighlighter update];
        [self->_parseErrorCollector update];
    });
}

// ---------------------------------------------------------------------------
// MARK: - UDDiagnosticsDidChangeNotification
// ---------------------------------------------------------------------------

- (void)_diagnosticsDidChange:(NSNotification *)note {
    NSArray<UDDiagnosticItem *> *all = _diagnosticStore.allDiagnostics;

    // Refresh every open editor tab.
    for (UDTextEditorViewController *editorVC in [self _allEditorViewControllers]) {
        [self _updateGutterErrorMarks:all forEditorVC:editorVC];

        // Force re-layout so diagnostic pills redraw in this tab's text view.
        NSTextView *tv = editorVC.textView;
        [tv.layoutManager
            invalidateLayoutForCharacterRange:NSMakeRange(0, _textStorage.length)
                         actualCharacterRange:nil];
        [tv setNeedsDisplay:YES];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Gutter error marks
// ---------------------------------------------------------------------------

- (void)_updateGutterErrorMarks:(NSArray<UDDiagnosticItem *> *)diagnostics
                     forEditorVC:(UDTextEditorViewController *)editorVC {
    UDTextModel *model      = _textStorage.textModel;
    NSInteger    totalLines = [model getLineCount];
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
    if ([itemIdentifier isEqualToString:kToolbarAddEditorTab]) {
        NSToolbarItem *item =
            [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label        = @"New Editor Tab";
        item.paletteLabel = @"New Editor Tab";
        item.toolTip      = @"Open a new tab showing the same document";
        item.image        = [NSImage imageWithSystemSymbolName:@"plus.rectangle.on.rectangle"
                                       accessibilityDescription:@"New editor tab"];
        item.target       = self;
        item.action       = @selector(addEditorTab:);
        return item;
    }
    return nil;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarFlexibleSpaceItem, kToolbarAddEditorTab];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[kToolbarAddEditorTab, NSToolbarFlexibleSpaceItem, NSToolbarSpaceItem];
}

@end
