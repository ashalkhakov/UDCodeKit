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

@interface UDDocumentWindowController () <NSTextViewDelegate>

// Created in -windowDidLoad.
@property (nonatomic, strong) UDTextModelTextStorage     *textStorage;
@property (nonatomic, strong) UDTextEditorViewController *textEditorViewController;
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

    // 2. Create the text editor VC and force its view to load so that the
    //    layout manager is wired BEFORE the first parse is triggered.
    _textEditorViewController =
        [[UDTextEditorViewController alloc] initWithTextStorage:_textStorage];
    (void)_textEditorViewController.view;   // triggers -viewDidLoad → wires layout manager

    // 3. Now safe to parse — layout chain is complete.
    [_textStorage setLanguageFunc:(LanguageFunc)tree_sitter_json
               withHighlightsQuery:kJSONHighlightsQuery];

    // 4. Wire the text view delegate (needed by LSP coordinator).
    _textEditorViewController.textView.delegate = self;

    // 5. Configure the auto-indenter with the JSON language.
    [_textEditorViewController.autoIndenter
        configureWithLanguageFunc:(LanguageFunc)tree_sitter_json
                     indentsQuery:kJSONIndentsQuery];

    // 6. Window title.
    self.window.title = fileURL ? fileURL.lastPathComponent : @"Untitled";

    // 7. Diagnostic store — shared by the parse-error collector and LSP.
    _diagnosticStore = [[UDDiagnosticStore alloc] init];

    // 8. MISSING-node pill highlighter.
    _missingNodeHighlighter =
        [[UDMissingNodeHighlighter alloc] initWithTextStorage:_textStorage
                                                   highlighter:_textStorage.highlighter];
    [_missingNodeHighlighter update];

    // 9. Parse-error inline pill highlighter.
    _parseErrorHighlighter =
        [[UDParseErrorHighlighter alloc] initWithTextStorage:_textStorage
                                                  highlighter:_textStorage.highlighter];
    [_parseErrorHighlighter update];

    // 10. Parse-error collector → writes to the diagnostic store.
    _parseErrorCollector =
        [[UDParseErrorCollector alloc] initWithTextStorage:_textStorage
                                                highlighter:_textStorage.highlighter
                                                      store:_diagnosticStore];
    [_parseErrorCollector update];

    // 11. Errors panel view controller (loads from UDErrorsView.xib).
    _errorsViewController =
        [[UDErrorsViewController alloc] initWithDiagnosticStore:_diagnosticStore];

    // 12. Build the two-pane layout using NSSplitViewController.
    //     The errors pane is on the left with a fixed width; the editor fills
    //     the rest.  This replaces the window's content view, so no manual
    //     frame layout is needed.
    NSSplitViewController *splitVC = [[NSSplitViewController alloc] init];

    NSSplitViewItem *errorsItem =
        [NSSplitViewItem splitViewItemWithViewController:_errorsViewController];
    errorsItem.minimumThickness = kErrorsPaneWidth;
    errorsItem.maximumThickness = kErrorsPaneWidth;
    [splitVC addSplitViewItem:errorsItem];

    NSSplitViewItem *editorItem =
        [NSSplitViewItem splitViewItemWithViewController:_textEditorViewController];
    [splitVC addSplitViewItem:editorItem];

    self.contentViewController = splitVC;

    // 13. Text-storage edit notification (document-level highlighters only;
    //     the editor VC handles its own folding/bracket-match/find).
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
// MARK: - NSTextViewDelegate (for LSP)
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

    // Update gutter error marks on the right-edge gutter.
    [self _updateGutterErrorMarksWithDiagnostics:all];

    // Force the text view to re-layout and redraw diagnostic pills.
    NSTextView *tv = _textEditorViewController.textView;
    [tv.layoutManager
        invalidateLayoutForCharacterRange:NSMakeRange(0, _textStorage.length)
                     actualCharacterRange:nil];
    [tv setNeedsDisplay:YES];
}

// ---------------------------------------------------------------------------
// MARK: - Gutter error marks
// ---------------------------------------------------------------------------

- (void)_updateGutterErrorMarksWithDiagnostics:(NSArray<UDDiagnosticItem *> *)diagnostics {
    UDTextModel *model      = _textStorage.textModel;
    NSInteger    totalLines = [model getLineCount];
    UDFindResultsGutterView *gutter = _textEditorViewController.gutterView;
    if (totalLines <= 0) { gutter.errorFractions = @[]; return; }

    NSMutableArray<NSNumber *> *fracs =
        [NSMutableArray arrayWithCapacity:diagnostics.count];
    for (UDDiagnosticItem *item in diagnostics) {
        CGFloat frac = (CGFloat)(item.line - 1) / (CGFloat)totalLines;
        [fracs addObject:@(MAX(0.0, MIN(1.0, frac)))];
    }
    gutter.errorFractions = fracs;
}

@end
