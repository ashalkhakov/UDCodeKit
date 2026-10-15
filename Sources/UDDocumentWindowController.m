#import "UDDocumentWindowController.h"
#import "UDDocument.h"
#import "UDErrorsViewController.h"
#import "UDWorkspaceModel.h"
#import <UDCodeKit/UDCodeKit.h>
#ifdef __APPLE__
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

// The panes of the window's split view (UDDocumentWindowController.xib).
static const NSInteger UDNavigatorPane = 0;
static const NSInteger UDInspectorPane = 2;

// ---------------------------------------------------------------------------
// MARK: - UDDocumentWindowController  (private extension)
// ---------------------------------------------------------------------------

@interface UDDocumentWindowController () <UDDiagnosticTextViewDelegate, UDErrorsViewControllerDelegate,
                                          UDEditorTabsControllerDelegate, NSTableViewDataSource,
                                          NSTableViewDelegate, NSWindowDelegate>

// The window's layout, all in the XIB.
@property (nonatomic, strong) IBOutlet UDPaneSplitController  *paneSplit;
@property (nonatomic, strong) IBOutlet UDEditorTabsController *editorTabs;
@property (nonatomic, weak) IBOutlet NSSegmentedControl *navigatorControl;
@property (nonatomic, weak) IBOutlet NSTabView          *navigatorTabView;
@property (nonatomic, weak) IBOutlet NSTableView        *filesTable;
@property (nonatomic, weak) IBOutlet NSView             *issuesHost;
@property (nonatomic, weak) IBOutlet NSTextField *inspectorName;
@property (nonatomic, weak) IBOutlet NSTextField *inspectorPath;
@property (nonatomic, weak) IBOutlet NSTextField *inspectorLanguage;
@property (nonatomic, weak) IBOutlet NSTextField *inspectorLines;
@property (nonatomic, weak) IBOutlet NSTextField *inspectorLineEndings;

@property (nonatomic, strong) UDErrorsViewController *errorsViewController;
@property (nonatomic, strong) UDHoverViewController  *hover;
// Where the language server's replies go: the text view that asked.
@property (nonatomic, weak) UDDiagnosticTextView *completionTextView;
@property (nonatomic, weak) UDDiagnosticTextView *hoverTextView;
@property (nonatomic) NSUInteger hoverIndex;

/// Pure model layer: owns UDCodeDocument objects, one per unique open file.
@property (nonatomic, strong) UDWorkspaceModel *workspaceModel;

/// One editor session per open document; a document can show in several
/// tabs, each with its own editor over the session's text storage.
@property (nonatomic, strong) NSMapTable<UDCodeDocument *, UDEditorSession *> *sessions;

/// Cached theme (used when adding new tabs after initial load).
@property (nonatomic, strong) TreeSitterTheme *currentTheme;

@end

// ---------------------------------------------------------------------------

@implementation UDDocumentWindowController

- (instancetype)init {
    return [super initWithWindowNibName:@"UDDocumentWindowController"];
}

// ---------------------------------------------------------------------------
// MARK: - Lifecycle
// ---------------------------------------------------------------------------

- (void)windowDidLoad {
    [super windowDidLoad];

    UDWorkspace *workspace = (UDWorkspace *)self.document;
    _sessions       = [NSMapTable strongToStrongObjectsMapTable];
    _workspaceModel = [[UDWorkspaceModel alloc] init];

#ifdef __APPLE__
    NSAppearanceName best =
        [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [best isEqualToString:NSAppearanceNameDarkAqua];
#else
    BOOL dark = NO;          // GNUstep: no appearances; the light theme
#endif
    _currentTheme = [[TreeSitterTheme alloc] initWithMode:dark];

    // The panes: navigator and inspector keep their widths, the editors take
    // the rest; sizes and visibility are remembered.
    _paneSplit.minimumThicknesses = @[@160, @320, @200];
    _paneSplit.defaultThicknesses = @[@240, @0, @260];
    _paneSplit.autosaveName = @"UDCode Workspace";
    [_paneSplit restoreLayout];

    // The issues navigator, from its own XIB, in its host.
    _errorsViewController = [[UDErrorsViewController alloc] init];
    _errorsViewController.delegate = self;
    NSView *issues = _errorsViewController.view;
    issues.frame = _issuesHost.bounds;
    issues.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_issuesHost addSubview:issues];

    // The documents to show.
    NSArray<UDCodeDocument *> *preloaded = workspace.workspaceModel.documents;
    if (preloaded.count > 0) {
        for (UDCodeDocument *doc in preloaded) {
            [_workspaceModel addDocumentWithText:[doc.textModel getValue] fileURL:doc.fileURL];
            [self _openTabForDocument:_workspaceModel.documents.lastObject];
        }
    } else if (workspace.initialTabURLs.count > 0) {
        for (NSURL *url in workspace.initialTabURLs) {
            NSError *err = nil;
            UDCodeDocument *doc = [_workspaceModel addDocumentFromURL:url error:&err];
            if (!doc) {
                NSLog(@"[UDDocumentWindowController] Cannot open %@: %@", url.lastPathComponent, err);
                doc = [_workspaceModel addDocumentWithText:@"" fileURL:url];
            }
            [self _openTabForDocument:doc];
        }
    } else {
        [self addEditorTab:nil];
    }
    workspace.primaryTextStorage = [self _sessionForDocument:_workspaceModel.documents.firstObject].textStorage;

    self.window.title = workspace.fileURL ? workspace.fileURL.lastPathComponent : @"Untitled Workspace";
}

// ---------------------------------------------------------------------------
// MARK: - Panes (View menu)
// ---------------------------------------------------------------------------

- (IBAction)toggleNavigator:(nullable id)sender {
    [_paneSplit setPane:UDNavigatorPane visible:![_paneSplit isPaneVisible:UDNavigatorPane]];
}

- (IBAction)toggleInspector:(nullable id)sender {
    [_paneSplit setPane:UDInspectorPane visible:![_paneSplit isPaneVisible:UDInspectorPane]];
}

- (IBAction)navigatorChanged:(nullable id)sender {
    [_navigatorTabView selectTabViewItemAtIndex:_navigatorControl.selectedSegment];
}

- (IBAction)showFilesNavigator:(nullable id)sender {
    [_paneSplit setPane:UDNavigatorPane visible:YES];
    _navigatorControl.selectedSegment = 0;
    [self navigatorChanged:nil];
}

- (IBAction)showIssuesNavigator:(nullable id)sender {
    [_paneSplit setPane:UDNavigatorPane visible:YES];
    _navigatorControl.selectedSegment = 1;
    [self navigatorChanged:nil];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(toggleNavigator:)) {
        item.title = [_paneSplit isPaneVisible:UDNavigatorPane] ? @"Hide Navigator" : @"Show Navigator";
    } else if (item.action == @selector(toggleInspector:)) {
        item.title = [_paneSplit isPaneVisible:UDInspectorPane] ? @"Hide Inspector" : @"Show Inspector";
    } else if (item.action == @selector(closeEditorTab:)) {
        return _editorTabs.selectedItem != nil;
    } else if (item.action == @selector(selectNextTab:) || item.action == @selector(selectPreviousTab:)) {
        return _editorTabs.items.count > 1;
    }
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Tabs
// ---------------------------------------------------------------------------

- (IBAction)addEditorTab:(nullable id)sender {
    UDLanguageMode *jsonMode = [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"json"];
    UDCodeDocument *doc = [_workspaceModel addDocumentWithText:jsonMode.defaultNewDocumentText fileURL:nil
                                                  languageMode:jsonMode];
    [self _openTabForDocument:doc];
}

- (IBAction)closeEditorTab:(nullable id)sender {
    [_editorTabs closeSelectedTab:sender];
}

- (IBAction)selectNextTab:(nullable id)sender     { [_editorTabs selectNextTab:sender]; }
- (IBAction)selectPreviousTab:(nullable id)sender { [_editorTabs selectPreviousTab:sender]; }

- (IBAction)openFileInNewTab:(nullable id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles          = YES;
    panel.canChooseDirectories    = NO;
    panel.allowsMultipleSelection = YES;
    // The extensions the language modes know (GNUstep has no UTType).
    NSMutableOrderedSet<NSString *> *extensions = [NSMutableOrderedSet orderedSet];
    for (UDLanguageMode *mode in [UDLanguageModeRegistry sharedRegistry].allModes) {
        [extensions addObjectsFromArray:mode.fileExtensions];
    }
#ifdef __APPLE__
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    for (NSString *ext in extensions) {
        UTType *type = [UTType typeWithFilenameExtension:ext];
        if (type && ![types containsObject:type]) [types addObject:type];
    }
    panel.allowedContentTypes = types.count ? types : @[UTTypeData];
#else
    panel.allowedFileTypes = extensions.count ? extensions.array : nil;
#endif
    if ([panel runModal] != NSModalResponseOK) return;
    for (NSURL *url in panel.URLs) [self openURLInNewTab:url];
}

- (void)openURLInNewTab:(NSURL *)url {
    // A file already open gets another view: both tabs edit one text storage.
    UDCodeDocument *doc = [_workspaceModel documentForFileURL:url];
    if (!doc) {
        NSError *err = nil;
        doc = [_workspaceModel addDocumentFromURL:url error:&err];
        if (!doc) {
            NSLog(@"[UDDocumentWindowController] Cannot open %@: %@", url.lastPathComponent, err);
            return;
        }
    }
    [self _openTabForDocument:doc];
}

- (nullable UDEditorSession *)_sessionForDocument:(nullable UDCodeDocument *)document {
    return document ? [_sessions objectForKey:document] : nil;
}

/// A tab for @a document: its session (made with its first tab), and an
/// editor of its own.
- (void)_openTabForDocument:(UDCodeDocument *)document {
    UDEditorSession *session = [self _sessionForDocument:document];
    BOOL first = session == nil;
    if (first) {
        session = [[UDEditorSession alloc] initWithDocument:document];
        [_sessions setObject:session forKey:document];
    }

    // The editor's view loads first, so its layout manager is attached
    // before the session's first parse.
    UDCodeEditorViewController *editor = [[UDCodeEditorViewController alloc] initWithTextStorage:session.textStorage];
    [editor configureForLanguageMode:document.languageMode];
    editor.textView.delegate = self;

    if (first) {
        [session activateWithTheme:_currentTheme];
        [session startLanguageServer];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_diagnosticsDidChange:)
                                                     name:UDDiagnosticsDidChangeNotification
                                                   object:document.diagnosticStore];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textDidChange:)
                                                     name:UDTextModelDidChangeNotification
                                                   object:document.textModel];
    }

    [self _documentsChanged];      // before the tab selects its row in the files list
    UDTabBarItem *item = [_editorTabs addItemWithTitle:document.displayName
                                     representedObject:document
                                        viewController:editor];
    item.toolTip = document.fileURL.path;
    item.dirty = document.isModified;
}

- (nullable UDCodeEditorViewController *)_selectedEditor {
    UDTabBarItem *item = _editorTabs.selectedItem;
    return item ? (UDCodeEditorViewController *)[_editorTabs viewControllerForItem:item] : nil;
}

- (nullable UDEditorSession *)_activeSession {
    return [self _sessionForDocument:_editorTabs.selectedItem.representedObject];
}

- (NSArray<UDTabBarItem *> *)_itemsForDocument:(UDCodeDocument *)document {
    NSMutableArray *items = [NSMutableArray array];
    for (UDTabBarItem *item in _editorTabs.items) {
        if (item.representedObject == document) [items addObject:item];
    }
    return items;
}

/// The open documents changed: the files navigator and the issues.
- (void)_documentsChanged {
    [_filesTable reloadData];
    NSMutableArray<UDDiagnosticStore *> *stores = [NSMutableArray array];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UDCodeDocument *doc in _workspaceModel.documents) {
        [stores addObject:doc.diagnosticStore];
        [names addObject:doc.displayName];
    }
    [_errorsViewController setStores:stores displayNames:names];
}

// ---------------------------------------------------------------------------
// MARK: - UDEditorTabsControllerDelegate
// ---------------------------------------------------------------------------

/// The last tab of a document with unsaved changes asks first.
- (BOOL)editorTabs:(UDEditorTabsController *)tabs shouldCloseItem:(UDTabBarItem *)item {
    UDCodeDocument *document = item.representedObject;
    if (!document.isModified || [self _itemsForDocument:document].count > 1) return YES;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Close “%@” without saving?", document.displayName];
    alert.informativeText = @"Its changes are lost.";
    [alert addButtonWithTitle:@"Close"];
    [alert addButtonWithTitle:@"Cancel"];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

/// The document's last tab closed: its session and its place in the workspace go.
- (void)editorTabs:(UDEditorTabsController *)tabs didCloseItem:(UDTabBarItem *)item {
    UDCodeDocument *document = item.representedObject;
    if ([self _itemsForDocument:document].count > 0) return;
    [[self _sessionForDocument:document] close];
    [_sessions removeObjectForKey:document];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:document.diagnosticStore];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:document.textModel];
    [_workspaceModel removeDocument:document];
    [self _documentsChanged];
}

- (void)editorTabs:(UDEditorTabsController *)tabs didSelectItem:(nullable UDTabBarItem *)item {
    UDCodeDocument *document = item.representedObject;
    NSUInteger row = document ? [_workspaceModel.documents indexOfObject:document] : NSNotFound;
    if (row != NSNotFound) {
        [_filesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    } else {
        [_filesTable deselectAll:nil];
    }
    [self _updateInspector];
    UDCodeEditorViewController *editor = [self _selectedEditor];
    if (editor) [self.window makeFirstResponder:editor.textView];
}

// ---------------------------------------------------------------------------
// MARK: - Files navigator
// ---------------------------------------------------------------------------

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_workspaceModel.documents.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    UDCodeDocument *document = _workspaceModel.documents[(NSUInteger)row];
    return document.isModified ? [document.displayName stringByAppendingString:@" •"] : document.displayName;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    NSInteger row = _filesTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_workspaceModel.documents.count) return;
    UDTabBarItem *item = [self _itemsForDocument:_workspaceModel.documents[(NSUInteger)row]].firstObject;
    if (item && item != _editorTabs.selectedItem) [_editorTabs selectItem:item];
}

// ---------------------------------------------------------------------------
// MARK: - Inspector
// ---------------------------------------------------------------------------

- (void)_updateInspector {
    UDCodeDocument *document = _editorTabs.selectedItem.representedObject;
    UDTextModel *model = document.textModel;
    _inspectorName.stringValue = document.displayName ?: @"";
    _inspectorPath.stringValue = document.fileURL.path ?: (document ? @"Not saved" : @"");
    _inspectorLanguage.stringValue = document.languageMode.displayName ?: @"";
    _inspectorLines.stringValue = model ? [NSString stringWithFormat:@"%ld", (long)[model getLineCount]] : @"";
    _inspectorLineEndings.stringValue = !model ? @"" : [[model getEOL] isEqualToString:@"\r\n"] ? @"CRLF" : @"LF";
}

// ---------------------------------------------------------------------------
// MARK: - Changes
// ---------------------------------------------------------------------------

/// Edited (or undone back to saved): the tabs' dirty dots, the files list,
/// the inspector.
- (void)_textDidChange:(NSNotification *)note {
    UDCodeDocument *document = nil;
    for (UDCodeDocument *doc in _workspaceModel.documents) {
        if (doc.textModel == note.object) { document = doc; break; }
    }
    if (!document) return;
    for (UDTabBarItem *item in [self _itemsForDocument:document]) item.dirty = document.isModified;
    [_filesTable reloadData];
    if (_editorTabs.selectedItem.representedObject == document) [self _updateInspector];
}

- (void)_diagnosticsDidChange:(NSNotification *)note {
    UDDiagnosticStore *store = note.object;
    UDCodeDocument *doc = [_workspaceModel documentForDiagnosticStore:store];
    if (!doc) return;
    NSInteger totalLines = [doc.textModel getLineCount];
    NSMutableArray<NSNumber *> *fractions = [NSMutableArray array];
    for (UDDiagnosticItem *item in store.allDiagnostics) {
        CGFloat frac = totalLines > 0 ? (CGFloat)(item.line - 1) / (CGFloat)totalLines : 0;
        [fractions addObject:@(MAX(0.0, MIN(1.0, frac)))];
    }
    for (UDTabBarItem *item in [self _itemsForDocument:doc]) {
        UDCodeEditorViewController *editor = (UDCodeEditorViewController *)[_editorTabs viewControllerForItem:item];
        editor.gutterView.errorFractions = fractions;
    }
}

// ---------------------------------------------------------------------------
// MARK: - UDErrorsViewControllerDelegate — click to navigate
// ---------------------------------------------------------------------------

- (void)errorsViewController:(UDErrorsViewController *)vc
         didSelectDiagnostic:(UDDiagnosticItem *)diagnostic
                     inStore:(UDDiagnosticStore *)store {
    UDCodeDocument *doc = [_workspaceModel documentForDiagnosticStore:store];
    UDTabBarItem *item = doc ? [self _itemsForDocument:doc].firstObject : nil;
    if (!item) return;
    [_editorTabs selectItem:item];
    UDCodeEditorViewController *editor = (UDCodeEditorViewController *)[_editorTabs viewControllerForItem:item];
    UDTextModel *model = doc.textModel;
    // The diagnostic's column is 0-based; the model's 1-based.
    NSInteger offset = [model getOffsetAt:diagnostic.line column:MAX(diagnostic.column, 0) + 1];
    if (offset < 0) offset = [model getOffsetAt:diagnostic.line column:1];
    if (offset < 0) return;
    NSRange range = NSMakeRange((NSUInteger)offset, 0);
    [editor.textView scrollRangeToVisible:range];
    editor.textView.selectedRange = range;
    [self.window makeFirstResponder:editor.textView];
}

// ---------------------------------------------------------------------------
// MARK: - Autocomplete and hover (LSP)
// ---------------------------------------------------------------------------

- (void)textViewRequestCompletion:(UDDiagnosticTextView *)textView {
    _completionTextView = textView;
    [[self _activeSession].lspCoordinator completionAtIndex:textView.selectedRange.location
                                                     target:self action:@selector(_didReceiveCompletion:)];
}

- (void)_didReceiveCompletion:(LSPResponse *)response {
    NSArray<LSPCompletionItem *> *items = response.result;
    if (response.error || !items.count) return;
    [self _activeSession].completionList = items;
    [_completionTextView showCompleteList:nil];
}

- (NSArray<NSString *> *)textView:(NSTextView *)textView
                       completions:(NSArray<NSString *> *)words
               forPartialWordRange:(NSRange)charRange
               indexOfSelectedItem:(NSInteger *)index {
    UDEditorSession *session = [self _activeSession];
    if (!session.completionList.count) return @[];
    return [session.completionList valueForKeyPath:@"label"];
}

- (void)textView:(UDDiagnosticTextView *)textView requestTooltipAtIndex:(NSUInteger)characterIndex point:(NSPoint)point {
    _hoverTextView = textView;
    _hoverIndex = characterIndex;
    [[self _activeSession].lspCoordinator hoverAtIndex:characterIndex
                                                target:self action:@selector(_didReceiveHover:)];
}

- (void)textViewHoverDidEnd:(UDDiagnosticTextView *)textView {
    _hoverTextView = nil;     // a reply still on its way finds no one
    [_hover close];
}

- (void)_didReceiveHover:(LSPResponse *)response {
    NSDictionary *contents = [response.result objectForKey:@"contents"];
    NSString *text = [contents isKindOfClass:[NSDictionary class]] ? contents[@"value"] : [contents description];
    if (!text.length || !_hoverTextView) return;
    if (!_hover) _hover = [[UDHoverViewController alloc] init];
    [_hover showText:text atCharacterIndex:_hoverIndex ofTextView:_hoverTextView];
}

// ---------------------------------------------------------------------------
// MARK: - Workspace state and saving (called by UDWorkspace)
// ---------------------------------------------------------------------------

- (NSArray<NSURL *> *)currentOpenFileURLs {
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (UDCodeDocument *doc in _workspaceModel.documents) {
        if (doc.fileURL) [urls addObject:doc.fileURL];
    }
    return [urls copy];
}

- (void)documentWillSave {
    [[self _sessionForDocument:_workspaceModel.documents.firstObject].lspCoordinator documentWillSave];
}

- (void)documentDidSave:(BOOL)success {
    [[self _sessionForDocument:_workspaceModel.documents.firstObject].lspCoordinator documentDidSave];
    if (!success) {
        NSLog(@"[UDDocumentWindowController] File save failed; all services have been notified of the save attempt.");
    }
}

- (void)close {
    // Only what this class observes: NSWindowController (GNUstep's) learns
    // that its window closes by a notification of its own.
    for (UDCodeDocument *doc in _workspaceModel.documents) {
        [[self _sessionForDocument:doc] close];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:doc.diagnosticStore];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:doc.textModel];
    }
    [super close];
}

@end
