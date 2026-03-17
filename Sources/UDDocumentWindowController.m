#import "UDDocumentWindowController.h"
#import "UDDocument.h"
#import "UDTextModelTextStorage.h"
#import "UDTextEditorViewController.h"
#import "UDErrorsViewController.h"
#import "UDLSPCoordinator.h"
#import "UDLSPDiagnosticHighlighter.h"
#import "TreeSitterTheme.h"
#import "UDMissingNodeHighlighter.h"
#import "UDParseErrorHighlighter.h"
#import "UDParseErrorCollector.h"
#import "UDDiagnosticStore.h"
#import "UDDiagnosticItem.h"
#import "UDCodeDocument.h"
#import "UDWorkspaceModel.h"
#import "UDLanguageModeRegistry.h"
#import "UDExtension.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// ---------------------------------------------------------------------------
// MARK: - Module-level constants
// ---------------------------------------------------------------------------

static CGFloat const kErrorsPaneWidth = 180.0;

static NSToolbarItemIdentifier const kToolbarAddTab    = @"addEditorTab";
static NSToolbarItemIdentifier const kToolbarOpenInTab = @"openFileInNewTab";

// ---------------------------------------------------------------------------
// MARK: - UDEditorTabContext  (private — lives entirely in this translation unit)
// ---------------------------------------------------------------------------

/// Encapsulates all per-document state for one editor tab (or a group of tabs
/// that all show the same document).
///
/// The model state (text content, diagnostics, file URL, display name) lives
/// in UDCodeDocument — which is UI-independent and testable.
/// UDEditorTabContext adds the AppKit-specific bridge layer on top:
///   • UDTextModelTextStorage (NSTextStorage backed by the document's textModel)
///   • tree-sitter parse highlighters and error collectors
///   • document services (LSP, RNG validators, etc.)
///
/// Multiple UDTextEditorViewControllers may be wired to the same context: each
/// adds its own NSLayoutManager to the shared UDTextModelTextStorage, so edits
/// in any view appear immediately in all others.
///
/// Lifecycle:
///   1. -initWithDocument:             — create before any editor VC loads.
///   2. -activateWithTheme:…           — call AFTER the first editor VC's
///      -viewDidLoad has run so its layout manager is attached to textStorage
///      before the first tree-sitter parse fires.
///   3. Add document services via -addDocumentService:.
@interface UDEditorTabContext : NSObject

/// Pure model backing this editor tab.
@property (nonatomic, strong, readonly) UDCodeDocument          *document;
/// AppKit text storage wrapping document.textModel.
@property (nonatomic, strong, readonly) UDTextModelTextStorage  *textStorage;

/// Convenience accessors forwarded to document.
@property (nonatomic, readonly) UDDiagnosticStore   *diagnosticStore;
@property (nonatomic, readonly, nullable) NSURL     *fileURL;
@property (nonatomic, readonly) NSString            *tabTitle;

/// All active per-document services (LSP coordinators, RNG validators, etc.).
/// The host fans out lifecycle events to every service in this list.
@property (nonatomic, readonly) NSArray<id<UDDocumentService>> *documentServices;

/// Add a service to the list.  Must be called before the first event is fanned out.
- (void)addDocumentService:(id<UDDocumentService>)service;

- (instancetype)initWithDocument:(UDCodeDocument *)document NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Wire tree-sitter, run the first parse, and start the diagnostic pipeline.
/// MUST be called after at least one editor VC's -viewDidLoad has executed.
- (void)activateWithTheme:(nullable TreeSitterTheme *)theme
             languageMode:(UDLanguageMode *)languageMode;

@end

// ---- Private extension ----

@interface UDEditorTabContext ()
@property (nonatomic, strong) UDMissingNodeHighlighter        *missingNodeHighlighter;
@property (nonatomic, strong) UDParseErrorHighlighter         *parseErrorHighlighter;
@property (nonatomic, strong) UDParseErrorCollector           *parseErrorCollector;
@property (nonatomic, strong) NSMutableArray<id<UDDocumentService>> *mutableDocumentServices;
@end

@implementation UDEditorTabContext

- (instancetype)initWithDocument:(UDCodeDocument *)document {
    self = [super init];
    if (!self) return nil;
    _document                = document;
    // Wrap the document's textModel in the AppKit text-storage bridge.
    _textStorage             = [[UDTextModelTextStorage alloc] initWithTextModel:document.textModel];
    _mutableDocumentServices = [NSMutableArray array];
    return self;
}

- (NSArray<id<UDDocumentService>> *)documentServices {
    return [_mutableDocumentServices copy];
}

- (void)addDocumentService:(id<UDDocumentService>)service {
    [_mutableDocumentServices addObject:service];
}

// Convenience forwarding accessors ----------------------------------------

- (UDDiagnosticStore *)diagnosticStore { return _document.diagnosticStore; }
- (NSURL *)fileURL                     { return _document.fileURL; }
- (NSString *)tabTitle                 { return _document.displayName; }

// --------------------------------------------------------------------------

- (void)activateWithTheme:(TreeSitterTheme *)theme
             languageMode:(UDLanguageMode *)languageMode {
    if (theme) _textStorage.theme = theme;
    if (languageMode.languageFunc) {
        [_textStorage setLanguageFunc:languageMode.languageFunc
                   withHighlightsQuery:languageMode.highlightsQuery ?: @""];
    }

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
                                                      store:_document.diagnosticStore];
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
        UDTreeSitterHighlighter *hl = self->_textStorage.highlighter;
        const void *tree = hl.currentParseTree;
        if (tree) {
            NSArray<NSValue *> *changed   = hl.lastChangedCharRanges;
            UDTextModel        *textModel = self->_textStorage.textModel;
            for (id<UDDocumentService> svc in self->_mutableDocumentServices) {
                if ([svc respondsToSelector:
                        @selector(treeDidUpdateWithNewTree:changedRanges:textModel:)]) {
                    [svc treeDidUpdateWithNewTree:tree
                                   changedRanges:changed
                                       textModel:textModel];
                }
            }
        }
    });
}

@end

// ---------------------------------------------------------------------------
// MARK: - UDDocumentWindowController  (private extension)
// ---------------------------------------------------------------------------

@interface UDDocumentWindowController () <NSTextViewDelegate, NSToolbarDelegate,
                                          UDErrorsViewControllerDelegate>

/// Parallel to _editorTabViewController.tabViewItems: _tabContexts[i] is the
/// context for tab i.  The SAME context may appear at multiple indices (when
/// the user opens a second view of an already-open file).
@property (nonatomic, strong) NSMutableArray<UDEditorTabContext *> *tabContexts;

@property (nonatomic, strong) NSTabViewController    *editorTabViewController;
@property (nonatomic, strong) UDErrorsViewController *errorsViewController;

/// Pure model layer: owns UDCodeDocument objects, one per unique open file.
/// The documents array is the authoritative source of open-document state.
@property (nonatomic, strong) UDWorkspaceModel *workspaceModel;

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
    _workspaceModel = [[UDWorkspaceModel alloc] init];

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

    // Errors panel — no store yet; populated by _refreshErrorsPanel after tabs open.
    _errorsViewController = [[UDErrorsViewController alloc] init];
    _errorsViewController.delegate = self;

    NSSplitViewController *splitVC = [[NSSplitViewController alloc] init];
    NSSplitViewItem *errorsItem =
        [NSSplitViewItem splitViewItemWithViewController:_errorsViewController];
    errorsItem.minimumThickness = kErrorsPaneWidth;
    errorsItem.maximumThickness = kErrorsPaneWidth;
    [splitVC addSplitViewItem:errorsItem];
    [splitVC addSplitViewItem:
        [NSSplitViewItem splitViewItemWithViewController:_editorTabViewController]];
    self.contentViewController = splitVC;

    // 3. Open workspace tabs via workspace model documents (if any were
    //    pre-loaded) or fall back to the legacy initialTabURLs path.
    NSArray<UDCodeDocument *> *preloaded = workspace.workspaceModel.documents;
    if (preloaded.count > 0) {
        // Workspace was opened from a .udworkspace file — documents already
        // loaded by UDWorkspace.readFromURL:ofType:error:.
        for (UDCodeDocument *doc in preloaded) {
            [_workspaceModel addDocumentWithText:[doc.textModel getValue]
                                         fileURL:doc.fileURL];
            [self _openNewTabWithDocument:_workspaceModel.documents.lastObject];
        }
        workspace.primaryTextStorage = _tabContexts.firstObject.textStorage;
    } else if (workspace.initialTabURLs.count > 0) {
        // Plain file(s) opened directly — load via workspace model.
        for (NSURL *url in workspace.initialTabURLs) {
            NSError *err = nil;
            UDCodeDocument *doc = [_workspaceModel addDocumentFromURL:url error:&err];
            if (!doc) {
                NSLog(@"[UDDocumentWindowController] Cannot open %@: %@",
                      url.lastPathComponent, err);
                // Open an empty tab rather than silently dropping it.
                doc = [_workspaceModel addDocumentWithText:@"" fileURL:url];
            }
            [self _openNewTabWithDocument:doc];
        }
        workspace.primaryTextStorage = _tabContexts.firstObject.textStorage;
    } else {
        // Fresh workspace — open one blank editor tab (defaults to JSON mode).
        UDLanguageMode *jsonMode =
            [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"json"];
        UDCodeDocument *doc =
            [_workspaceModel addDocumentWithText:jsonMode.defaultNewDocumentText fileURL:nil];
        [self _openNewTabWithDocument:doc];
    }

    // 4. Populate errors panel with all open documents' stores.
    [self _refreshErrorsPanel];

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
}

// ---------------------------------------------------------------------------
// MARK: - Tab management — public actions
// ---------------------------------------------------------------------------

- (IBAction)addEditorTab:(nullable id)sender {
    // New untitled documents default to JSON mode; use its boilerplate text.
    UDLanguageMode *jsonMode =
        [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"json"];
    UDCodeDocument *doc =
        [_workspaceModel addDocumentWithText:jsonMode.defaultNewDocumentText fileURL:nil];
    [self _openNewTabWithDocument:doc];
}

- (IBAction)openFileInNewTab:(nullable id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles          = YES;
    panel.canChooseDirectories    = NO;
    panel.allowsMultipleSelection = YES;
    // Allow all file extensions supported by registered language modes,
    // plus a generic "all files" fallback.
    if (@available(macOS 11.0, *)) {
        NSMutableArray<UTType *> *types  = [NSMutableArray array];
        NSMutableSet<NSString *> *seenIDs = [NSMutableSet set];
        for (UDLanguageMode *mode in [UDLanguageModeRegistry sharedRegistry].allModes) {
            for (NSString *ext in mode.fileExtensions) {
                UTType *type = [UTType typeWithFilenameExtension:ext];
                if (type && ![seenIDs containsObject:type.identifier]) {
                    [seenIDs addObject:type.identifier];
                    [types addObject:type];
                }
            }
        }
        panel.allowedContentTypes = types.count ? types : @[UTTypeData];
    } else {
        NSMutableArray<NSString *> *exts = [NSMutableArray array];
        NSMutableSet<NSString *>   *seen = [NSMutableSet set];
        for (UDLanguageMode *mode in [UDLanguageModeRegistry sharedRegistry].allModes) {
            for (NSString *ext in mode.fileExtensions) {
                if (![seen containsObject:ext]) {
                    [seen addObject:ext];
                    [exts addObject:ext];
                }
            }
        }
        panel.allowedFileTypes = exts.count ? exts : nil;
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
    UDCodeDocument *existing = [_workspaceModel documentForFileURL:url];
    if (existing) {
        for (UDEditorTabContext *ctx in _tabContexts) {
            if (ctx.document == existing) {
                [self _addViewTabForContext:ctx];
                return;
            }
        }
    }

    // New file — add to workspace model (loads from disk) and open a tab.
    NSError *err = nil;
    UDCodeDocument *doc = [_workspaceModel addDocumentFromURL:url error:&err];
    if (!doc) {
        NSLog(@"[UDDocumentWindowController] Cannot open %@: %@",
              url.lastPathComponent, err);
        return;
    }
    [self _openNewTabWithDocument:doc];
}

// ---------------------------------------------------------------------------
// MARK: - Workspace state (used by UDWorkspace for serialisation)
// ---------------------------------------------------------------------------

- (NSArray<NSURL *> *)currentOpenFileURLs {
    // Delegate to the workspace model — it already de-duplicates by file URL.
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (UDCodeDocument *doc in _workspaceModel.documents) {
        if (doc.fileURL) [urls addObject:doc.fileURL];
    }
    return [urls copy];
}

// ---------------------------------------------------------------------------
// MARK: - Tab management — private helpers
// ---------------------------------------------------------------------------

/// Create a new editor tab backed by document.  Adds the tab to the UI and
/// registers all AppKit-side observers.  The caller must have already added
/// the document to _workspaceModel.
- (void)_openNewTabWithDocument:(UDCodeDocument *)document {
    // a. Build context wrapping the document.
    UDEditorTabContext *ctx = [[UDEditorTabContext alloc] initWithDocument:document];

    // b. Wire an editor VC.  Calling -view forces -viewDidLoad which attaches
    //    a new NSLayoutManager to ctx.textStorage.  This MUST happen before
    //    -activateWithTheme:… fires the first parse.
    UDTextEditorViewController *editorVC =
        [[UDTextEditorViewController alloc] initWithTextStorage:ctx.textStorage];
    [self _configureEditorVC:editorVC languageMode:document.languageMode];     // forces -viewDidLoad

    // c. Activate: first parse, diagnostic pipeline, edit notifications.
    [ctx activateWithTheme:_currentTheme
              languageMode:document.languageMode];

    // d. LSP coordinator.
    [self _setupLSPCoordinatorForContext:ctx];

    // d2. Extension service (optional — only when the extension provides one).
    [self _setupExtensionServiceForContext:ctx];

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
    [self _appendTabItem:document.displayName
          viewController:editorVC
              identifier:document.fileURL.absoluteString
                      ?: [NSString stringWithFormat:@"untitled-%lu",
                              (unsigned long)_editorTabViewController.tabViewItems.count + 1]];

    // g. Refresh the errors panel so the new document appears immediately.
    [self _refreshErrorsPanel];
}

/// Add a second (or further) view of an already-active context.  The new tab
/// shares the context's textStorage, diagnosticStore, and document services;
/// edits in either tab appear immediately in both.
- (void)_addViewTabForContext:(UDEditorTabContext *)ctx {
    UDTextEditorViewController *editorVC =
        [[UDTextEditorViewController alloc] initWithTextStorage:ctx.textStorage];
    [self _configureEditorVC:editorVC
                languageMode:ctx.document.languageMode];  // adds another NSLayoutManager to shared storage

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

/// Rebuild the errors panel from the workspace model so every open document
/// is visible as its own file-group row — like Xcode's Issue Navigator.
- (void)_refreshErrorsPanel {
    NSMutableArray<UDDiagnosticStore *> *stores = [NSMutableArray array];
    NSMutableArray<NSString *>          *names  = [NSMutableArray array];
    for (UDCodeDocument *doc in _workspaceModel.documents) {
        [stores addObject:doc.diagnosticStore];
        [names  addObject:doc.displayName];
    }
    [_errorsViewController setStores:stores displayNames:names];
}

/// Configure a freshly created editor VC:
///   • Forces -viewDidLoad (attaches its NSLayoutManager to textStorage).
///   • Sets this window controller as the text-view delegate (LSP).
///   • Configures the auto-indenter for the document's language.
- (void)_configureEditorVC:(UDTextEditorViewController *)vc
              languageMode:(UDLanguageMode *)mode {
    (void)vc.view;    // triggers -viewDidLoad
    vc.textView.delegate = self;
    if (mode.languageFunc && mode.indentsQuery) {
        [vc.autoIndenter configureWithLanguageFunc:mode.languageFunc
                                      indentsQuery:mode.indentsQuery];
    }
    // Pass language configuration so the auto-indenter uses the correct bracket
    // pairs for electric-pair indentation rather than hard-coded defaults.
    vc.autoIndenter.languageConfiguration = mode.languageConfiguration;
    vc.autoIndenter.languageKeyHandler    = mode.keyHandler;
}

// ---------------------------------------------------------------------------
// MARK: - Extension document service setup
// ---------------------------------------------------------------------------

- (void)_setupExtensionServiceForContext:(UDEditorTabContext *)ctx {
    UDLanguageMode *mode = ctx.document.languageMode;
    id<UDExtension> ext = mode.extension;
    if (!ext) return;

    SEL sel = @selector(documentServiceForDocumentURL:store:);
    if (![ext respondsToSelector:sel]) return;

    id<UDDocumentService> svc =
        [(id<UDExtension>)ext documentServiceForDocumentURL:ctx.fileURL
                                                      store:ctx.diagnosticStore];
    if (!svc) return;
    [ctx addDocumentService:svc];

    // Notify the service that the document is now open (seeds any internal
    // text buffers the service maintains, e.g. the XML gap buffer in the RNG
    // highlighter).
    if ([svc respondsToSelector:@selector(documentDidOpenWithContent:)]) {
        NSString *content = [ctx.textStorage.textModel getValue];
        [svc documentDidOpenWithContent:content];
    }

    // Kick off the initial validation pass with the current parse tree.
    if ([svc respondsToSelector:
            @selector(treeDidUpdateWithNewTree:changedRanges:textModel:)]) {
        UDTreeSitterHighlighter *hl = ctx.textStorage.highlighter;
        const void *tree = hl.currentParseTree;
        if (tree) {
            [svc treeDidUpdateWithNewTree:tree
                            changedRanges:nil  // full parse on open
                               textModel:ctx.textStorage.textModel];
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - LSP setup
// ---------------------------------------------------------------------------

- (void)_setupLSPCoordinatorForContext:(UDEditorTabContext *)ctx {
    UDLanguageMode *mode = ctx.document.languageMode;

    // Skip LSP setup when the extension has not provided a language server command.
    NSArray<NSString *> *serverCommand = mode.languageServerCommand;
    if (!serverCommand.count || !mode.lspLanguageID) return;

    NSString *defaultFilename = [NSString stringWithFormat:@"untitled.%@",
                                 mode.fileExtensions.firstObject ?: @"txt"];
    NSURL *docURL = ctx.fileURL
        ?: [NSURL fileURLWithPath:
               [NSTemporaryDirectory()
                   stringByAppendingPathComponent:defaultFilename]];

    NSString *serverPath = serverCommand.firstObject;
    NSArray<NSString *> *serverArgs = serverCommand.count > 1
        ? [serverCommand subarrayWithRange:NSMakeRange(1, serverCommand.count - 1)]
        : @[];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm isExecutableFileAtPath:serverPath]) {
        NSLog(@"[UDDocumentWindowController] Language server not found at \"%@\"; "
              @"LSP inactive for \"%@\".", serverPath, ctx.tabTitle);
        return;
    }

    UDTextModelTextStorage *ts = ctx.textStorage;
    LSPClient *client =
        [[LSPClient alloc] initWithPath:serverPath
                              arguments:serverArgs
                   currentDirectoryPath:docURL.URLByDeletingLastPathComponent.path
                             languageID:mode.lspLanguageID];

    UDLSPDiagnosticHighlighter *lspHL =
        [[UDLSPDiagnosticHighlighter alloc] initWithTextStorage:ts
                                                     highlighter:ts.highlighter
                                                           store:ctx.diagnosticStore];
    UDLSPCoordinator *lsp =
        [[UDLSPCoordinator alloc] initWithTextStorage:ts
                                               client:client
                                          documentURL:docURL
                                diagnosticHighlighter:lspHL];
    [ctx addDocumentService:lsp];
    [lsp documentDidOpenWithContent:[ts.textModel getValue]];
}

// ---------------------------------------------------------------------------
// MARK: - Save notifications (called by UDWorkspace)
// ---------------------------------------------------------------------------

- (void)documentWillSave {
    for (id<UDDocumentService> svc in _tabContexts.firstObject.documentServices) {
        if ([svc respondsToSelector:@selector(documentWillSave)]) {
            [svc documentWillSave];
        }
    }
}

- (void)documentDidSave:(BOOL)success {
    for (id<UDDocumentService> svc in _tabContexts.firstObject.documentServices) {
        if ([svc respondsToSelector:@selector(documentDidSave)]) {
            [svc documentDidSave];
        }
    }
    if (!success) {
        NSLog(@"[UDDocumentWindowController] File save failed; "
              @"all services have been notified of the save attempt.");
    }
}

// ---------------------------------------------------------------------------
// MARK: - Close
// ---------------------------------------------------------------------------

- (void)close {
    // Close each unique context's LSP coordinator exactly once.
    NSMutableSet<UDEditorTabContext *> *seen = [NSMutableSet set];
    for (UDEditorTabContext *ctx in _tabContexts) {
        if (![seen containsObject:ctx]) {
            for (id<UDDocumentService> svc in ctx.documentServices) {
                [svc closeDocument];
            }
            [seen addObject:ctx];
        }
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super close];
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
    for (id<UDDocumentService> svc in [self _activeContext].documentServices) {
        if ([svc respondsToSelector:
                @selector(textWillChangeInRange:replacementString:)]) {
            [svc textWillChangeInRange:affectedCharRange
                     replacementString:replacementString ?: @""];
        }
    }
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - UDDiagnosticsDidChangeNotification
// ---------------------------------------------------------------------------

- (void)_diagnosticsDidChange:(NSNotification *)note {
    UDDiagnosticStore       *store = (UDDiagnosticStore *)note.object;
    NSArray<UDDiagnosticItem *> *all  = store.allDiagnostics;
    NSArray<NSTabViewItem *>    *items = _editorTabViewController.tabViewItems;

    // The model owns the store→document mapping; the window controller resolves
    // document→tab for the AppKit gutter update.
    UDCodeDocument *doc = [_workspaceModel documentForDiagnosticStore:store];
    if (!doc) return;

    // Update every tab that shows this document (there may be more than one if
    // the same document is open in multiple tabs).
    for (NSUInteger i = 0; i < MIN(_tabContexts.count, items.count); i++) {
        if (_tabContexts[i].document != doc) continue;

        UDTextEditorViewController *editorVC =
            (UDTextEditorViewController *)items[i].viewController;
        [self _updateGutterErrorMarks:all
                           forEditorVC:editorVC
                               context:_tabContexts[i]];
        // _updateGutterErrorMarks: sets errorFractions on the gutter view, which
        // already calls setNeedsDisplay:YES on itself.  Do NOT call
        // invalidateLayoutForCharacterRange: here — diagnostics do not change
        // any text-metric attributes (font, size, etc.), so forcing NSLayoutManager
        // to re-layout the entire document is unnecessary and causes O(N) work
        // (via getCharacters:range: → piece-tree traversal) on every
        // diagnostics update.
    }
}

// ---------------------------------------------------------------------------
// MARK: - UDErrorsViewControllerDelegate — click to navigate
// ---------------------------------------------------------------------------

- (void)errorsViewController:(UDErrorsViewController *)vc
         didSelectDiagnostic:(UDDiagnosticItem *)diagnostic
                     inStore:(UDDiagnosticStore *)store {
    // The model owns the authoritative store→document mapping.
    UDCodeDocument *doc = [_workspaceModel documentForDiagnosticStore:store];
    if (!doc) return;

    // Find the first tab slot for this document and navigate to the diagnostic.
    NSArray<NSTabViewItem *> *items = _editorTabViewController.tabViewItems;
    NSUInteger count = MIN(_tabContexts.count, items.count);
    for (NSUInteger i = 0; i < count; i++) {
        if (_tabContexts[i].document != doc) continue;

        if (_editorTabViewController.selectedTabViewItemIndex != (NSInteger)i) {
            [_editorTabViewController.tabView selectTabViewItemAtIndex:(NSInteger)i];
        }
        UDTextEditorViewController *editorVC =
            (UDTextEditorViewController *)items[i].viewController;
        [self _navigateEditorVC:editorVC
                         toLine:diagnostic.line
                         column:diagnostic.column
                        context:_tabContexts[i]];
        break;
    }
}

/// Scrolls @a editorVC to @a line (1-based) / @a column (0-based) and places
/// the insertion point there.  Uses the text model to map the position to a
/// character offset, then asks the text view to scroll into view.
- (void)_navigateEditorVC:(UDTextEditorViewController *)editorVC
                   toLine:(NSInteger)line
                   column:(NSInteger)column
                  context:(UDEditorTabContext *)ctx {
    UDTextModel *textModel = ctx.textStorage.textModel;

    // column from UDDiagnosticItem is 0-based; getOffsetAt:column: takes 1-based column.
    NSInteger col1 = (column > 0) ? column + 1 : 1;
    NSInteger charOffset = [textModel getOffsetAt:line column:col1];
    if (charOffset < 0) {
        // Fall back to the start of the line.
        charOffset = [textModel getOffsetAt:line column:1];
    }
    if (charOffset < 0) return;

    NSRange charRange = NSMakeRange((NSUInteger)charOffset, 0);
    NSTextView *tv = editorVC.textView;
    [tv scrollRangeToVisible:charRange];
    [tv setSelectedRange:charRange];
    // Give the text view keyboard focus so the user can start editing immediately.
    [tv.window makeFirstResponder:tv];
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
