#import "UDDocumentWindowController.h"
#import "UDDocument.h"
#import <UDCodeKit/UDErrorsViewController.h>
#import "UDWorkspaceModel.h"
#import "UDDemoDebugAdapter.h"
#import <objc/runtime.h>
#import <UDCodeKit/UDCodeKit.h>
#import "AppDelegate.h"
#ifdef __APPLE__
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

// The panes of the window's split view (UDDocumentWindowController.xib).
static const NSInteger UDNavigatorPane = 0;
static const NSInteger UDInspectorPane = 2;
// The editors' split: the debug area below them.
static const NSInteger UDDebugAreaPane = 1;
// The navigator's segments.
static const NSInteger UDSourceControlNavigatorSegment = 1;
static const NSInteger UDFindNavigatorSegment = 2;
static const NSInteger UDIssuesNavigatorSegment = 3;
static const NSInteger UDTestNavigatorSegment = 4;
static const NSInteger UDDebugNavigatorSegment = 5;
static const NSInteger UDBreakpointNavigatorSegment = 6;
static const NSInteger UDBuildNavigatorSegment = 7;
// What follows a build.
static const NSInteger UDAfterBuildNothing = 0;
static const NSInteger UDAfterBuildRun = 1;
static const NSInteger UDAfterBuildDebug = 2;
static const NSInteger UDAfterBuildDebugTests = 3;

// ---------------------------------------------------------------------------
// MARK: - UDDocumentWindowController  (private extension)
// ---------------------------------------------------------------------------

@interface UDDocumentWindowController () <UDDiagnosticTextViewDelegate, UDErrorsViewControllerDelegate,
                                          UDEditorTabsControllerDelegate, UDDebugSessionDelegate,
                                          UDBreakpointNavigatorDelegate, UDFileNavigatorDelegate, UDBuildRunnerDelegate,
                                          UDFileWatcherDelegate, UDSearchResultsDelegate, UDSourceControlNavigatorDelegate, UDHistoryDelegate, UDCodeEditorSourceControlDelegate, UDSourceControlHost, UDJumpBarControllerDelegate, UDWorkbench, UDWorkspaceEditDocuments, UDOpenQuicklyDelegate, UDLinkedEditingDelegate, UDIssuePopupDelegate, UDTestNavigatorDelegate,
                                          UDCodeEditorLinkDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>

// The window's layout, all in the XIB.
@property (nonatomic, strong) IBOutlet UDPaneSplitController  *paneSplit;
@property (nonatomic, strong) IBOutlet UDEditorTabsController *editorTabs;
@property (nonatomic, weak) IBOutlet NSSegmentedControl *navigatorControl;
@property (nonatomic, weak) IBOutlet NSTabView          *navigatorTabView;
@property (nonatomic, weak) IBOutlet NSTableView        *filesTable;
@property (nonatomic, weak) IBOutlet NSView             *projectHost;
@property (nonatomic, weak) IBOutlet NSView             *buildLogHost;
@property (nonatomic, weak) IBOutlet NSView             *findHost;
@property (nonatomic, weak) IBOutlet NSView             *sourceControlHost;
/// The project's source control (an extension's: git's; nil: none), and
/// Xcode's navigator of it.
@property (nonatomic, strong, readwrite, nullable) id<UDSourceControl> sourceControl;
@property (nonatomic, strong) UDSourceControlNavigatorViewController *sourceControlNavigator;
@property (nonatomic, weak) IBOutlet NSPopUpButton      *schemePopUp;
@property (nonatomic, weak) IBOutlet NSTextField        *activityLabel;
@property (nonatomic, strong, readwrite) UDSearchResultsViewController *searchResults;
@property (nonatomic, strong, readwrite, nullable) UDOpenQuicklyController *openQuickly;
@property (nonatomic, strong, nullable) UDLinkedEditing *rename;
@property (nonatomic, strong, nullable) NSDictionary *renameEdit;
@property (nonatomic, weak, nullable) UDLSPCoordinator *renameCoordinator;
@property (nonatomic) NSUInteger renameIndex;
@property (nonatomic, weak, nullable) UDTextModel *formattingModel;
@property (nonatomic, readwrite, copy, nullable) NSArray<NSDictionary *> *codeActions;
@property (nonatomic, weak, nullable) UDLSPCoordinator *codeActionCoordinator;
@property (nonatomic, strong, nullable) UDIssuePopupController *issuePopup;
@property (nonatomic, copy, nullable) NSString *issueMessage;
@property (nonatomic) NSUInteger issueIndex;
@property (nonatomic, strong, nullable) UDHoverViewController *signatureHelp;
@property (nonatomic, weak, nullable) UDDiagnosticTextView *signatureTextView;
@property (nonatomic) NSUInteger signatureIndex;
@property (nonatomic, strong, readwrite, nullable) UDBuildRunner *buildRunner;
@property (nonatomic, strong) UDBuildLogViewController *buildLog;
/// The project's files, watched: what changes elsewhere shows here.
@property (nonatomic, strong, nullable) UDFileWatcher *fileWatcher;
@property (nonatomic, strong, readwrite, nullable) UDProjectSettingsController *projectSettings;
/// Run waits for the settings sheet that names its program.
@property (nonatomic) NSInteger afterSettings;
/// The launch configuration a build is for (launch.json's), nil for the project's own run.
@property (nonatomic, strong, nullable) UDLaunchConfiguration *pendingConfiguration;
/// What follows the build: nothing, running the program, or debugging it.
@property (nonatomic) NSInteger afterBuild;
/// The build's diagnostics' stores for files no tab has, listed in Issues.
@property (nonatomic, copy) NSArray<NSString *> *buildIssuePaths;
@property (nonatomic, strong, readwrite, nullable) UDProject *project;
/// The extensions' navigators: each its view controller and segment.
@property (nonatomic, strong, nullable) NSMapTable<id, NSArray *> *extensionNavigators;
@property (nonatomic, strong, readwrite, nullable) UDFileNavigatorViewController *fileNavigator;
/// The project's language servers, one per command, which its documents share
/// (one clangd for the project, as VS Code has it).
@property (nonatomic, strong) NSMutableDictionary<NSArray<NSString *> *, LSPClient *> *projectServers;
@property (nonatomic, weak) IBOutlet NSView             *issuesHost;
@property (nonatomic, weak) IBOutlet NSView             *testsHost;
@property (nonatomic, strong, readwrite) UDTestNavigatorViewController *testNavigator;
@property (nonatomic, strong, nullable) UDTestCatalog *testCatalogStore;
/// A test run is what the build runner runs: its output read for its tests.
@property (nonatomic) BOOL testing;
/// The last the runner ran was tests (the activity view says how they went).
@property (nonatomic) BOOL testsRan;
/// Tests being debugged: built, then debugged.
@property (nonatomic, strong, nullable) UDTestDebugPlan *pendingTestPlan;
/// What runs them once the debugger waits for it (an Xcode project's).
@property (nonatomic, copy, nullable) NSString *pendingAttachedTestCommand;
@property (nonatomic, weak) IBOutlet NSView             *debugNavigatorHost;
@property (nonatomic, weak) IBOutlet NSView             *breakpointNavigatorHost;
@property (nonatomic, strong) IBOutlet UDPaneSplitController *debugSplit;
@property (nonatomic, weak) IBOutlet NSView             *debugBarHost;
@property (nonatomic, weak) IBOutlet NSView             *debugAreaHost;
@property (nonatomic, weak) IBOutlet NSView             *terminalHost;
@property (nonatomic, weak) IBOutlet NSSegmentedControl *bottomAreaControl;
/// Source | Preview, at the tab bar's right: the selected tab's, for a mode
/// that renders its text (Markdown's).
@property (nonatomic, weak) IBOutlet NSSegmentedControl *previewControl;
@property (nonatomic, weak) IBOutlet NSButton *reviewButton;
@property (nonatomic, strong, readwrite, nullable) UDTerminalViewController *terminal;
@property (nonatomic, weak) IBOutlet NSTextField *inspectorName;
@property (nonatomic, weak) IBOutlet NSTextField *inspectorPath;
@property (nonatomic, weak) IBOutlet NSTextField *inspectorLanguage;
@property (nonatomic, weak) IBOutlet NSTextField *inspectorLines;
@property (nonatomic, weak) IBOutlet NSTextField *inspectorLineEndings;

@property (nonatomic, strong) UDErrorsViewController *errorsViewController;
@property (nonatomic, strong) UDHoverViewController  *hover;
@property (nonatomic, strong) UDDebugNavigatorViewController *debugNavigator;
@property (nonatomic, strong) UDBreakpointNavigatorViewController *breakpointNavigator;
@property (nonatomic, strong) UDDebugBarViewController       *debugBar;
@property (nonatomic, strong) UDDebugAreaViewController      *debugArea;
@property (nonatomic, strong) UDBreakpointStore              *breakpoints;
@property (nonatomic, strong, nullable) UDDebugSession       *debugSession;
// Where the language server's replies go: the text view that asked.
@property (nonatomic, weak) UDDiagnosticTextView *completionTextView;
@property (nonatomic, weak) UDDiagnosticTextView *hoverTextView;
@property (nonatomic) NSUInteger hoverIndex;

/// Pure model layer: owns UDCodeDocument objects, one per unique open file.
@property (nonatomic, strong) UDWorkspaceModel *workspaceModel;

/// One editor session per open document; a document can show in several
/// tabs, each with its own editor over the session's text storage.
@property (nonatomic, strong) NSMapTable<UDCodeDocument *, UDEditorSession *> *sessions;
/// A diff tab's original side; its modified side is the tab's document.
@property (nonatomic, strong) NSMapTable<UDTabBarItem *, UDCodeDocument *> *diffOriginals;
/// Compare with Saved's originals: the file each is the saved text of.
@property (nonatomic, strong) NSMapTable<UDCodeDocument *, NSURL *> *savedCopies;
/// Code Review's originals in a repository: the file each is the text at HEAD of.
@property (nonatomic, strong) NSMapTable<UDCodeDocument *, NSString *> *headCopies;
/// Texts shown only to read (a file at a commit): no language server, nothing to save.
@property (nonatomic, strong) NSHashTable<UDCodeDocument *> *scratchDocuments;
/// History tabs: the ref each shows.
@property (nonatomic, strong) NSMapTable<UDTabBarItem *, NSString *> *historyTabs;
/// The file navigator's Select for Compare.
@property (nonatomic, copy, nullable) NSURL *selectedForCompare;

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
    _diffOriginals  = [NSMapTable strongToStrongObjectsMapTable];
    _savedCopies    = [NSMapTable strongToStrongObjectsMapTable];
    _headCopies     = [NSMapTable strongToStrongObjectsMapTable];
    _scratchDocuments = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory];
    _historyTabs    = [NSMapTable strongToStrongObjectsMapTable];
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
    [self _putView:_errorsViewController.view inHost:_issuesHost];

    // The debugger: its navigator, and below the editors its bar and area,
    // each from its XIB. The area shows when a session starts (and as it
    // was left, after the first).
    // The breakpoints, the watch expressions and the exception filters are
    // the workspace's, kept in the user defaults by its file's path.
    _breakpoints = [[UDBreakpointStore alloc] init];
    _breakpoints.autosaveName = [@"UDCode Debugger " stringByAppendingString:workspace.fileURL.path ?: @"Untitled"];
    _debugNavigator = [[UDDebugNavigatorViewController alloc] init];
    [self _putView:_debugNavigator.view inHost:_debugNavigatorHost];
    _breakpointNavigator = [[UDBreakpointNavigatorViewController alloc] init];
    _breakpointNavigator.breakpoints = _breakpoints;
    _breakpointNavigator.delegate = self;
    [self _putView:_breakpointNavigator.view inHost:_breakpointNavigatorHost];
    _debugBar = [[UDDebugBarViewController alloc] init];
    [self _putView:_debugBar.view inHost:_debugBarHost];
    _debugArea = [[UDDebugAreaViewController alloc] init];
    _debugArea.breakpoints = _breakpoints;
    [self _putView:_debugArea.view inHost:_debugAreaHost];
    _debugSplit.flexiblePaneIndex = 0;
    _debugSplit.minimumThicknesses = @[@200, @120];
    _debugSplit.defaultThicknesses = @[@0, @220];
    BOOL debugAreaSaved = [[NSUserDefaults standardUserDefaults] objectForKey:@"UDPaneSplit UDCode Debug Area"] != nil;
    _debugSplit.autosaveName = @"UDCode Debug Area";
    [_debugSplit restoreLayout];
    if (!debugAreaSaved) [_debugSplit setPane:UDDebugAreaPane visible:NO];
    NSView *debugPane = _debugBarHost.superview;
    debugPane.postsFrameChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_debugPaneDidResize:)
                                                 name:NSViewFrameDidChangeNotification object:debugPane];
    [self _layoutDebugPane];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_editorPreviewDidChange:)
                                                 name:UDCodeEditorPreviewDidChangeNotification object:nil];
    [self _updatePreviewControl];

    // A project: its files in the Files tab, instead of the open files' list.
    _project = workspace.project;
    if (_project) {
        _fileNavigator = [[UDFileNavigatorViewController alloc] init];
        _fileNavigator.delegate = self;
        _fileNavigator.folderURL = _project.folderURL;
        [self _putView:_fileNavigator.view inHost:_projectHost];
        _projectHost.hidden = NO;
        _filesTable.enclosingScrollView.hidden = YES;
        _breakpoints.autosaveName = [@"UDCode Debugger " stringByAppendingString:_project.folderURL.path];
        _project.preferredProgram = [[NSUserDefaults standardUserDefaults] stringForKey:[self _programDefaultsKey]];
        _buildRunner = [[UDBuildRunner alloc] initWithProject:_project];
        _fileWatcher = [[UDFileWatcher alloc] initWithFolderURL:_project.folderURL ignoredNames:nil];
        _fileWatcher.delegate = self;
    }
    _sourceControlNavigator = [[UDSourceControlNavigatorViewController alloc] init];
    _sourceControlNavigator.delegate = self;
    [self _putView:_sourceControlNavigator.view inHost:_sourceControlHost];
    [self reloadSourceControl];
    [self _addExtensionNavigators];
    _testNavigator = [[UDTestNavigatorViewController alloc] init];
    _testNavigator.delegate = self;
    [self _putView:_testNavigator.view inHost:_testsHost];
    _searchResults = [[UDSearchResultsViewController alloc] init];
    _searchResults.delegate = self;
    _searchResults.folderURL = _project.folderURL;
    [self _putView:_searchResults.view inHost:_findHost];
    _buildLog = [[UDBuildLogViewController alloc] init];
    [self _putView:_buildLog.view inHost:_buildLogHost];
    _buildLog.forward = self;
    _buildLog.runner = _buildRunner;

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
    } else if (!_project) {
        [self addEditorTab:nil];
    }
    workspace.primaryTextStorage = [self _sessionForDocument:_workspaceModel.documents.firstObject].textStorage;

    self.window.title = _project ? _project.name
                      : workspace.fileURL ? workspace.fileURL.lastPathComponent : @"Untitled Workspace";
#ifdef __APPLE__
    if (_project) self.window.representedURL = _project.folderURL;
#endif
    [self _updateSchemePopUp];
    [self _updateActivity];
}

/// The project's window is named for it, not for an untitled document.
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName {
    return _project ? _project.name : displayName;
}

/// A document of the project's: the language server the project (or the
/// language's bundle) names, one process for all the project's documents,
/// rooted at its folder; clangd told how to compile a file the project has
/// no compile commands for. NO for a document outside a project.
- (BOOL)_startProjectLanguageServerOf:(UDEditorSession *)session document:(UDCodeDocument *)document {
    UDLanguageMode *mode = document.languageMode;
    NSString *folder = [_project.folderURL.path stringByAppendingString:@"/"];
    if (!_project || !document.fileURL || !mode.lspLanguageID || ![document.fileURL.path hasPrefix:folder]) return NO;
    NSArray<NSString *> *command = [_project languageServerCommandForIdentifier:mode.identifier] ?: mode.languageServerCommand;
    if (!command.count) return NO;
    if (!_projectServers) _projectServers = [NSMutableDictionary dictionary];
    LSPClient *client = _projectServers[command];
    if (!client) {
        NSString *path = command.firstObject.isAbsolutePath ? command.firstObject
                                                            : [UDToolLocator pathOfTool:command.firstObject];
        if (!path) return NO;
        client = [[LSPClient alloc] initWithPath:path
                                       arguments:[command subarrayWithRange:NSMakeRange(1, command.count - 1)]
                            currentDirectoryPath:_project.folderURL.path
                                      languageID:mode.lspLanguageID];
        client.rootURL = _project.folderURL;
        // the extensions' (clangd's fallbackFlags, from CFamily)
        client.initializationOptions = [_project initializationOptionsForLanguageServer:
                                        [@[ path ] arrayByAddingObjectsFromArray:[command subarrayWithRange:NSMakeRange(1, command.count - 1)]]];
        _projectServers[command] = client;
    }
    [session startLanguageServerWithClient:client documentURL:document.fileURL];
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Saving, building
// ---------------------------------------------------------------------------

/// A project's tabs are files of its own, each saved as itself; a window of
/// files alone saves as its document does.
- (IBAction)saveDocument:(nullable id)sender {
    UDCodeDocument *document = _editorTabs.selectedItem.representedObject;
    if (!_project) {
        [self.document saveDocument:sender];
        return;
    }
    if (document.fileURL) [self _save:document];
}

- (IBAction)saveAllDocuments:(nullable id)sender {
    for (UDCodeDocument *document in _workspaceModel.documents) {
        if (document.fileURL && document.isModified) [self _save:document];
    }
}

- (void)_save:(UDCodeDocument *)document {
    UDEditorSession *session = [self _sessionForDocument:document];
    [session.lspCoordinator documentWillSave];
    NSError *error = nil;
    BOOL saved = [document saveToURL:document.fileURL error:&error];
    [session.lspCoordinator documentDidSave];
    if (saved) [self _refreshSavedCopiesOfURL:document.fileURL];
    if (!saved && error) [self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
    [self _documentsChanged];
}

/// The build: tasks.json's build task (and what it depends on), else the
/// project's command.
- (nullable NSString *)_buildCommandLine {
    UDTasks *tasks = [self tasks];
    UDTask *task = tasks.buildTask;
    return task ? [tasks commandLineRunning:task] : _project.buildCommand;
}

- (IBAction)build:(nullable id)sender {
    [self _build:[self _buildCommandLine] then:UDAfterBuildNothing];
}

- (UDTasks *)tasks {
    if (!_project) return nil;
    UDCodeDocument *document = _editorTabs.selectedItem.representedObject;
    return [[UDTasks alloc] initWithFolderURL:_project.folderURL currentFileURL:document.fileURL];
}

- (NSString *)_launchConfigurationDefaultsKey {
    return [@"UDCode Launch Configuration " stringByAppendingString:_project.folderURL.path ?: @""];
}

- (NSString *)selectedLaunchConfiguration {
    NSArray<UDLaunchConfiguration *> *configurations = [self tasks].configurations;
    NSString *chosen = [[NSUserDefaults standardUserDefaults] stringForKey:[self _launchConfigurationDefaultsKey]];
    for (UDLaunchConfiguration *configuration in configurations) {
        if ([configuration.name isEqualToString:chosen]) return chosen;
    }
    return configurations.firstObject.name;
}

- (void)setSelectedLaunchConfiguration:(NSString *)name {
    if (name) [[NSUserDefaults standardUserDefaults] setObject:name forKey:[self _launchConfigurationDefaultsKey]];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:[self _launchConfigurationDefaultsKey]];
}

- (IBAction)selectLaunchConfiguration:(nullable id)sender {
    if ([sender isKindOfClass:[NSPopUpButton class]]) sender = [sender selectedItem];
    id name = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    if ([name isKindOfClass:[NSString class]]) self.selectedLaunchConfiguration = name;
    [self _updateSchemePopUp];
}

- (NSString *)_programDefaultsKey {
    return [@"UDCode Program " stringByAppendingString:_project.folderURL.path ?: @""];
}

/// The program the scheme pop-up chose, among the project's (UDQuakeTools'
/// apps and tools), kept with the project.
- (void)setSelectedProgram:(nullable NSString *)program {
    _project.preferredProgram = program;
    if (program) [[NSUserDefaults standardUserDefaults] setObject:program forKey:[self _programDefaultsKey]];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:[self _programDefaultsKey]];
    [self _updateSchemePopUp];
}

- (nullable NSString *)selectedProgram {
    return _project.inferredProgram;
}

- (IBAction)selectProgram:(nullable id)sender {
    if ([sender isKindOfClass:[NSPopUpButton class]]) sender = [sender selectedItem];
    id program = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    if ([program isKindOfClass:[NSString class]]) self.selectedProgram = program;
}

// ---------------------------------------------------------------------------
// MARK: - Tests (Debug › Test, the Test navigator)
// ---------------------------------------------------------------------------

/// The project's tests, as its sources have them; what the last runs left
/// marked stays marked.
- (UDTestCatalog *)testCatalog {
    if (!_testCatalogStore) [self reloadTests];
    return _testCatalogStore;
}

- (void)reloadTests {
    if (!_project) return;
    UDTestCatalog *catalog = [_project testCatalog];
    for (UDTest *test in catalog.allTests) {
        UDTest *before = [_testCatalogStore testNamed:test.name inSuite:test.suite.name];
        if (!before) continue;
        test.status = before.status;
        [test.failures addObjectsFromArray:before.failures];
    }
    _testCatalogStore = catalog;
    _testNavigator.catalog = catalog;
}

/// Debug › Test (⌘U): all the tests.
- (IBAction)test:(nullable id)sender {
    [self runTests:nil debugging:NO];
}

- (void)testNavigator:(UDTestNavigatorViewController *)navigator showPath:(NSString *)path line:(NSInteger)line {
    [self _showURL:[NSURL fileURLWithPath:path] line:line column:0 length:0];
}

- (void)testNavigator:(UDTestNavigatorViewController *)navigator runTests:(NSArray<UDTest *> *)tests debugging:(BOOL)debugging {
    [self runTests:tests debugging:debugging];
}

- (void)runTests:(nullable NSArray<UDTest *> *)tests debugging:(BOOL)debugging {
    if (!_project || !_buildRunner || _buildRunner.running) {
        NSBeep();
        return;
    }
    UDTestCatalog *catalog = self.testCatalog;
    [catalog resetTests:tests];
    [_testNavigator reload];
    [self showTestNavigator:nil];
    if (debugging) {
        [self _debugTests:tests];
        return;
    }
    NSString *command = [catalog commandRunningTests:tests];
    if (!command) {
        [self _tell:@"No tests to run"
             detail:@"UDCode runs a GNUstep project's XCTest bundles with xctest, an Xcode project's with xcodebuild test, "
                    @"CMake's with ctest, a Makefile's check or test target, or tasks.json's test task; "
                    @"or the \"test\" command in Debug › Project Settings."];
        return;
    }
    [self saveAllDocuments:nil];
    _testing = YES;
    _testsRan = YES;
    if (![_buildRunner runCommand:command]) {
        _testing = NO;
        NSBeep();
        return;
    }
    _buildLog.runner = _buildRunner;
    [self _showBuildIssues];
    [self _updateActivity];
}

/// Debugs @a tests (nil: all), as their runner says: built, then what runs
/// them under the debugger (or, an Xcode project's, the debugger waiting to
/// attach to what xcodebuild then starts).
- (void)_debugTests:(nullable NSArray<UDTest *> *)tests {
    NSString *reason = nil;
    UDTestDebugPlan *plan = [self.testCatalog debugPlanForTests:tests reason:&reason];
    if (!plan) {
        [self _tell:@"These tests can't be debugged here" detail:reason ?: @""];
        return;
    }
    _pendingTestPlan = plan;
    [self _build:plan.buildCommand then:UDAfterBuildDebugTests];
}

/// A test run's line: its tests marked; a failure an issue at its place.
- (void)buildRunner:(UDBuildRunner *)runner didReadLine:(NSString *)line {
    if (!_testing) return;
    UDTestFailure *failure = [_testCatalogStore readLine:line];
    if (failure && !failure.compilerStyle) {
        // GNUstep's: the file as the bundle's makefile compiled it
        NSString *path = [_testCatalogStore pathOfFile:failure.file] ?: failure.test.path;
        if (path) {
            NSString *name = failure.test ? [NSString stringWithFormat:@"-[%@ %@]: ", failure.test.suite.name, failure.test.name] : @"";
            [runner addDiagnostic:[[UDDiagnosticItem alloc] initWithLine:MAX(failure.line, 1) column:1
                                                                 message:[name stringByAppendingString:failure.message]
                                                                severity:UDDiagnosticSeverityError source:UDDiagnosticSourceBuild]
                           atPath:path.stringByStandardizingPath];
        }
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:_testNavigator selector:@selector(reload) object:nil];
    [_testNavigator performSelector:@selector(reload) withObject:nil afterDelay:0.1
                            inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode ]];
}

- (NSString *)_testsActivity {
    UDTestCatalog *catalog = _testCatalogStore;
    NSUInteger passed = catalog.passedCount, failed = catalog.failedCount;
    if (_buildRunner.running) return @"Testing…";
    if (!failed && _buildRunner.succeeded) return [NSString stringWithFormat:@"Tests Succeeded | %lu passed", (unsigned long)passed];
    if (!failed && !passed) return _buildRunner.errorCount ? @"Build Failed" : @"Tests Failed";
    return [NSString stringWithFormat:@"Tests Failed | %lu failed, %lu passed", (unsigned long)failed, (unsigned long)passed];
}

// ---------------------------------------------------------------------------
// MARK: - The toolbar: the scheme, and what is going on (Xcode's activity view)
// ---------------------------------------------------------------------------

/// The scheme pop-up: launch.json's configurations, the chosen one shown;
/// without them, the project; without a project, the window's documents.
- (void)_updateSchemePopUp {
    if (!_schemePopUp) return;
    [_schemePopUp removeAllItems];
    NSArray<UDLaunchConfiguration *> *configurations = [self tasks].configurations;
    if (configurations.count) {
        for (UDLaunchConfiguration *configuration in configurations) {
            [_schemePopUp addItemWithTitle:configuration.name];
            _schemePopUp.lastItem.representedObject = configuration.name;
        }
        [_schemePopUp selectItemWithTitle:self.selectedLaunchConfiguration];
        _schemePopUp.enabled = configurations.count > 1;
        _schemePopUp.action = @selector(selectLaunchConfiguration:);
    } else if (_project.programs.count > 1) {
        // what the project builds that runs: Xcode's schemes, as it were
        for (NSString *program in _project.programs) {
            [_schemePopUp addItemWithTitle:program.lastPathComponent.stringByDeletingPathExtension];
            _schemePopUp.lastItem.representedObject = program;
            _schemePopUp.lastItem.toolTip = program;
        }
        NSInteger chosen = [_schemePopUp indexOfItemWithRepresentedObject:_project.inferredProgram];
        if (chosen >= 0) [_schemePopUp selectItemAtIndex:chosen];
        _schemePopUp.enabled = YES;
        _schemePopUp.action = @selector(selectProgram:);
    } else {
        [_schemePopUp addItemWithTitle:_project ? _project.name : self.window.title];
        _schemePopUp.enabled = NO;
    }
    _schemePopUp.target = self;
}

/// What the program run is called: the configuration's, else the project's program.
- (NSString *)_programName {
    UDLaunchConfiguration *configuration = [self _launchConfiguration];
    NSString *program = configuration.program ?: _project.runProgram;
    return program.lastPathComponent.length ? program.lastPathComponent : (_project.name ?: @"the program");
}

- (NSString *)activityText {
    NSString *name = _project.name ?: self.window.title;
    NSString *status = @"Ready";
    UDDebugSessionState state = _debugSession.state;
    if (_testsRan && (_buildRunner.running || !_debugSession) && _buildRunner.command) {
        status = [self _testsActivity];
    } else if (_buildRunner.running) {
        status = [NSString stringWithFormat:@"Building %@…", name];
    } else if (_debugSession && state != UDDebugSessionStateEnded) {
        status = state == UDDebugSessionStateStopped ? [NSString stringWithFormat:@"Paused %@", [self _programName]]
                                                     : [NSString stringWithFormat:@"Running %@", [self _programName]];
    } else if (_debugSession) {
        status = [NSString stringWithFormat:@"Finished running %@", [self _programName]];
    } else if (_buildRunner.command) {
        status = _buildRunner.succeeded && !_buildRunner.errorCount ? @"Build Succeeded" : @"Build Failed";
    }
    NSMutableArray<NSString *> *counts = [NSMutableArray array];
    if (_buildRunner.command && !_buildRunner.running && !_testsRan) {
        NSUInteger errors = _buildRunner.errorCount, warnings = _buildRunner.warningCount;
        if (errors) [counts addObject:[NSString stringWithFormat:@"%lu error%@", (unsigned long)errors, errors == 1 ? @"" : @"s"]];
        if (warnings) [counts addObject:[NSString stringWithFormat:@"%lu warning%@", (unsigned long)warnings, warnings == 1 ? @"" : @"s"]];
    }
    NSString *text = [NSString stringWithFormat:@"%@ | %@", name, status];
    return counts.count ? [text stringByAppendingFormat:@" | %@", [counts componentsJoinedByString:@", "]] : text;
}

- (void)_updateActivity {
    _activityLabel.stringValue = self.activityText;
}

- (void)_debugSessionDidChangeState:(NSNotification *)note {
    if (note.object == _debugSession) [self _updateActivity];
}

/// The toolbar's buttons enabled as their menu items are.
- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem {
    NSMenuItem *probe = [[NSMenuItem alloc] initWithTitle:@"" action:toolbarItem.action keyEquivalent:@""];
    return [self validateMenuItem:probe];
}

- (IBAction)runTask:(nullable id)sender {
    id label = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    UDTasks *tasks = [self tasks];
    UDTask *task = [label isKindOfClass:[NSString class]] ? [tasks taskLabelled:label] : nil;
    if (!task) {
        NSBeep();
        return;
    }
    [self _build:[tasks commandLineRunning:task] then:UDAfterBuildNothing];
}

/// launch.json's configuration Run uses, nil when the folder has none.
- (nullable UDLaunchConfiguration *)_launchConfiguration {
    NSString *name = self.selectedLaunchConfiguration;
    for (UDLaunchConfiguration *configuration in [self tasks].configurations) {
        if ([configuration.name isEqualToString:name]) return configuration;
    }
    return nil;
}

/// Run (debugging or not): launch.json's configuration, its preLaunchTask
/// first; else the project's build, then its program.
- (void)_buildAndRun:(NSInteger)then {
    UDLaunchConfiguration *configuration = [self _launchConfiguration];
    _pendingConfiguration = configuration;
    if (!configuration) {
        [self _build:[self _buildCommandLine] then:then];
        return;
    }
    UDTasks *tasks = [self tasks];
    UDTask *before = configuration.preLaunchTask ? [tasks taskLabelled:configuration.preLaunchTask] : nil;
    [self _build:before ? [tasks commandLineRunning:before] : nil then:then];
}

- (IBAction)clean:(nullable id)sender {
    [self _build:_project.cleanCommand then:UDAfterBuildNothing];
}

- (IBAction)runWithoutDebugging:(nullable id)sender {
    [self _buildAndRun:UDAfterBuildRun];
}

/// Saved, then built (when there is a build command), then run or debugged
/// (@a then). Without a command, that at once.
- (void)_build:(nullable NSString *)command then:(NSInteger)then {
    if (!_buildRunner || _buildRunner.running) {
        NSBeep();
        return;
    }
    [self saveAllDocuments:nil];
    _afterBuild = then;
    if (!command.length) {
        if (then != UDAfterBuildNothing) [self _afterBuildSucceeded];
        else NSBeep();
        return;
    }
    if (![_buildRunner runCommand:command]) {
        NSBeep();
        return;
    }
    _testsRan = NO;
    _buildLog.runner = _buildRunner;
    [self showBuildNavigator:nil];
    [self _showBuildIssues];
    [self _updateActivity];
}

- (void)buildRunner:(UDBuildRunner *)runner didOutput:(NSString *)text {
    [self _showBuildIssues];
}

- (void)buildRunnerDidFinish:(UDBuildRunner *)runner {
    if (_testing) {
        // the tests' end: their marks, what failed, how it went
        _testing = NO;
        [self _showBuildIssues];
        [_testNavigator reload];
        [self _updateActivity];
        [_fileNavigator reload];
        if (!_testCatalogStore.failedCount && !_testCatalogStore.passedCount && runner.errorCount) [self showIssuesNavigator:nil];
        return;
    }
    [self _showBuildIssues];
    [self _updateActivity];
    [_fileNavigator reload];
    if (runner.errorCount > 0 || !runner.succeeded) {
        _afterBuild = UDAfterBuildNothing;
        if (runner.errorCount > 0) [self showIssuesNavigator:nil];
        return;
    }
    if (_afterBuild != UDAfterBuildNothing) [self _afterBuildSucceeded];
}

- (void)_afterBuildSucceeded {
    NSInteger then = _afterBuild;
    _afterBuild = UDAfterBuildNothing;
    if (then == UDAfterBuildRun) [self _runProgramDebugging:NO];
    else if (then == UDAfterBuildDebug) [self _runProgramDebugging:YES];
    else if (then == UDAfterBuildDebugTests && _pendingTestPlan) {
        UDTestDebugPlan *plan = _pendingTestPlan;
        _pendingTestPlan = nil;
        [self _run:plan.configuration debugging:YES];
        if (plan.testCommand) {
            // what runs the tests, started once the debugger waits for it
            // (lldb-dap says so; a process started before it waits isn't
            // the one it waits for), or in a while if it doesn't say
            _pendingAttachedTestCommand = plan.testCommand;
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_debuggerSaid:)
                                                         name:UDDebugSessionDidOutputNotification object:self.debugSession];
            [self performSelector:@selector(_startAttachedTests) withObject:nil afterDelay:10];
        }
    }
}

- (void)_debuggerSaid:(NSNotification *)notification {
    if (![notification.userInfo[UDDebugSessionOutputKey] containsString:@"Waiting to attach"]) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_startAttachedTests) object:nil];
    [self performSelector:@selector(_startAttachedTests) withObject:nil afterDelay:0.5];
}

- (void)_startAttachedTests {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_startAttachedTests) object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UDDebugSessionDidOutputNotification object:nil];
    NSString *command = _pendingAttachedTestCommand;
    _pendingAttachedTestCommand = nil;
    if (!command || self.debugSession.state == UDDebugSessionStateEnded) return;
    _testing = YES;
    _testsRan = YES;
    if (![_buildRunner runCommand:command]) _testing = NO;
    [self _updateActivity];
}

/// The build's diagnostics: an open file's in its own store (where its
/// editor shows them), the others' listed in Issues as they are.
- (void)_showBuildIssues {
    NSDictionary<NSString *, UDDiagnosticStore *> *found = _buildRunner.diagnostics;
    NSMutableArray<NSString *> *notOpen = [NSMutableArray array];
    for (UDCodeDocument *document in _workspaceModel.documents) {
        NSString *path = document.fileURL.path.stringByStandardizingPath;
        UDDiagnosticStore *built = path ? found[path] : nil;
        NSArray *items = [built.allDiagnostics filteredArrayUsingPredicate:
                          [NSPredicate predicateWithFormat:@"source == %@", UDDiagnosticSourceBuild]];
        [document.diagnosticStore setDiagnostics:items ?: @[] forSource:UDDiagnosticSourceBuild];
    }
    for (NSString *path in [found.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (![_workspaceModel documentForFileURL:[NSURL fileURLWithPath:path]] && found[path].allDiagnostics.count) {
            [notOpen addObject:path];
        }
    }
    _buildIssuePaths = notOpen;
    [self _documentsChanged];
}

/// Files changed elsewhere (a build, git, another editor): the navigator
/// lists them again; an open file with no edits of its own is read again (as
/// VS Code does; with edits, its edits stay); the language servers are told.
- (void)fileWatcher:(UDFileWatcher *)watcher didSeeChangesAtPaths:(NSSet<NSString *> *)paths {
    [_fileNavigator reload];
    [_sourceControl filesDidChangeAtPaths:paths];
    [self _updateSchemePopUp];      // launch.json may have changed
    // the tests again when their sources changed (not what a build made)
    BOOL sources = NO;
    for (NSString *path in paths) sources = sources || [@[ @"m", @"mm", @"h" ] containsObject:path.pathExtension];
    if (sources && _testCatalogStore && !_buildRunner.running) [self reloadTests];
    NSMutableSet<NSString *> *changed = [NSMutableSet set];
    for (NSString *path in paths) [changed addObject:path.stringByStandardizingPath];
    for (UDCodeDocument *document in _workspaceModel.documents) {
        if (document.fileURL && [changed containsObject:document.fileURL.path.stringByStandardizingPath]) {
            [document reloadFromFileIfUnmodified];
            [self _refreshSavedCopiesOfURL:document.fileURL];
        }
    }
    NSMutableArray *changes = [NSMutableArray array];
    for (NSString *path in paths) {
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
        [changes addObject:@{ @"uri": [NSURL fileURLWithPath:path].absoluteString, @"type": exists ? @2 : @3 }];
    }
    for (LSPClient *client in _projectServers.allValues) {
        [client sendNotification:@"workspace/didChangeWatchedFiles" params:@{ @"changes": changes }];
    }
    [self _documentsChanged];
}

// ---------------------------------------------------------------------------
// MARK: - The language's: definitions, references, workspace search (LSP)
// ---------------------------------------------------------------------------

/// UDWorkspaceEditDocuments: an open file's model, for an edit to go through its editor.
- (nullable UDTextModel *)textModelForFileURL:(NSURL *)url {
    return [self _documentOfFileURL:url].textModel;
}

/// The open document of the file at @a url, by its path (URLs of one file can differ).
- (nullable UDCodeDocument *)_documentOfFileURL:(NSURL *)url {
    NSString *path = url.path.stringByStandardizingPath;
    for (UDCodeDocument *document in _workspaceModel.documents) {
        if ([document.fileURL.path.stringByStandardizingPath isEqualToString:path]) return document;
    }
    return nil;
}

/// @a url's tab, its LSP range (or a line and column) selected.
- (void)_showURL:(NSURL *)url line:(NSInteger)line column:(NSInteger)column length:(NSInteger)length {
    [self _showFile:url.path];
    UDCodeDocument *document = [self _documentOfFileURL:url];
    UDCodeEditorViewController *editor = [self _selectedEditor];
    if (!document || !editor) return;
    // the model's lines and columns are 1-based; a column past the line's end, its end
    NSInteger offset = [document.textModel getOffsetAt:line column:column + 1];
    if (offset < 0) offset = [document.textModel getOffsetAt:line column:1];
    if (offset < 0) return;
    NSRange range = NSMakeRange((NSUInteger)offset, (NSUInteger)MAX(length, 0));
    if (NSMaxRange(range) > editor.textView.string.length) range.length = 0;
    [editor.textView scrollRangeToVisible:range];
    editor.textView.selectedRange = range;
    [self.window makeFirstResponder:editor.textView];
}

/// The text of line @a line (1-based) of @a url: an open file's, else on disk.
- (NSString *)_lineText:(NSInteger)line ofURL:(NSURL *)url {
    UDTextModel *model = [self textModelForFileURL:url];
    NSString *text = model ? [model getValue] : [UDCodeDocument textOfURL:url error:NULL];
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    return line >= 1 && (NSUInteger)line <= lines.count ? lines[(NSUInteger)line - 1] : @"";
}

/// An LSP Location or LocationLink as a search result.
- (nullable UDSearchResult *)_resultOfLocation:(NSDictionary *)location {
    if (![location isKindOfClass:[NSDictionary class]]) return nil;
    NSString *uri = location[@"uri"] ?: location[@"targetUri"];
    NSDictionary *range = location[@"range"] ?: location[@"targetSelectionRange"] ?: location[@"targetRange"];
    NSURL *url = [uri isKindOfClass:[NSString class]] ? [NSURL URLWithString:uri] : nil;
    if (!url || ![range isKindOfClass:[NSDictionary class]]) return nil;
    NSInteger line = [range[@"start"][@"line"] integerValue] + 1;
    NSInteger column = [range[@"start"][@"character"] integerValue];
    NSInteger endLine = [range[@"end"][@"line"] integerValue] + 1;
    NSInteger length = endLine == line ? [range[@"end"][@"character"] integerValue] - column : 0;
    return [[UDSearchResult alloc] initWithURL:url line:line column:column length:length lineText:[self _lineText:line ofURL:url]];
}

/// Navigate > Jump to Definition (⌃⌘J): where the language server says.
- (IBAction)jumpToDefinition:(nullable id)sender {
    UDCodeEditorViewController *editor = [self _selectedEditor];
    UDLSPCoordinator *lsp = [self _activeSession].lspCoordinator;
    if (!editor || ![lsp definitionAtIndex:editor.textView.selectedRange.location target:self action:@selector(_didFindDefinition:)]) NSBeep();
}

- (void)_didFindDefinition:(LSPResponse *)response {
    id result = response.result;
    NSDictionary *location = [result isKindOfClass:[NSArray class]] ? [result firstObject] : result;
    UDSearchResult *found = [self _resultOfLocation:location];
    if (!found) {
        NSBeep();
        return;
    }
    [self _showURL:found.url line:found.line column:found.column length:found.length];
}

/// Navigate > Find References (⇧⌃⌘F): in the Find navigator.
- (IBAction)findReferences:(nullable id)sender {
    UDCodeEditorViewController *editor = [self _selectedEditor];
    UDLSPCoordinator *lsp = [self _activeSession].lspCoordinator;
    NSRange selected = editor.textView.selectedRange;
    if (!editor || ![lsp request:@"textDocument/references" atIndex:selected.location
                           extra:@{ @"context": @{ @"includeDeclaration": @YES } }
                          target:self action:@selector(_didFindReferences:)]) {
        NSBeep();
    }
}

/// The identifier at the caret (letters, digits, underscores, as code's
/// are; not the text system's idea of a word): what a search is for.
- (NSString *)_wordAtCaret {
    NSTextView *textView = [self _selectedEditor].textView;
    if (!textView) return @"";
    NSString *string = textView.string;
    NSRange selected = textView.selectedRange;
    if (selected.length) return [string substringWithRange:selected];
    NSMutableCharacterSet *identifier = [NSMutableCharacterSet alphanumericCharacterSet];
    [identifier addCharactersInString:@"_"];
    NSUInteger start = MIN(selected.location, string.length), end = start;
    while (start > 0 && [identifier characterIsMember:[string characterAtIndex:start - 1]]) start--;
    while (end < string.length && [identifier characterIsMember:[string characterAtIndex:end]]) end++;
    return [string substringWithRange:NSMakeRange(start, end - start)];
}

- (void)_didFindReferences:(LSPResponse *)response {
    NSMutableArray<UDSearchResult *> *results = [NSMutableArray array];
    for (NSDictionary *location in [response.result isKindOfClass:[NSArray class]] ? response.result : @[]) {
        UDSearchResult *result = [self _resultOfLocation:location];
        if (result) [results addObject:result];
    }
    NSString *word = [self _wordAtCaret];
    [_searchResults showResults:results title:word.length ? [NSString stringWithFormat:@"References to “%@”", word] : @"References"];
    [self showFindNavigator:nil];
}

/// Edit > Find > Find in Workspace (⇧⌘F): the selection's text, or what is typed.
- (IBAction)findInWorkspace:(nullable id)sender {
    [self showFindNavigator:nil];
    NSTextView *textView = [self _selectedEditor].textView;
    NSRange selected = textView.selectedRange;
    if (selected.length && selected.length < 200) {
        [_searchResults searchFor:[textView.string substringWithRange:selected]];
    } else {
        [self.window makeFirstResponder:_searchResults.searchField];
    }
}

- (void)searchResults:(UDSearchResultsViewController *)controller showResult:(UDSearchResult *)result {
    [self _showURL:result.url line:result.line column:result.column length:result.length];
}

/// Open Quickly's choice: a file, or a symbol's place.
- (void)openQuickly:(UDOpenQuicklyController *)controller showResult:(UDSearchResult *)result {
    if (result.line > 0) [self _showURL:result.url line:result.line column:result.column length:result.length];
    else [self _showFile:result.url.path];
}

/// Navigate > Open Quickly (⇧⌘O): the project's files, the server's symbols.
- (IBAction)openQuickly:(nullable id)sender {
    if (!_openQuickly) {
        _openQuickly = [[UDOpenQuicklyController alloc] init];
        _openQuickly.delegate = self;
    }
    _openQuickly.folderURL = _project.folderURL;
    _openQuickly.client = [self _activeSession].lspCoordinator.client ?: _projectServers.allValues.firstObject;
    [_openQuickly beginSheetForWindow:self.window];
}

// ---------------------------------------------------------------------------
// MARK: - The language's: rename, format, fixes, signatures, occurrences (LSP)
// ---------------------------------------------------------------------------

/// A WorkspaceEdit applied: open files through their editors, the others on disk.
- (BOOL)_applyWorkspaceEdit:(NSDictionary *)edit {
    NSError *error = nil;
    NSArray<NSURL *> *changed = [UDWorkspaceEdit applyEdit:edit documents:self error:&error];
    if (error) [self _tell:@"Some files could not be changed." detail:error.localizedDescription];
    return changed.count > 0;
}

/// Editor > Rename Symbol (⌃⌘E), as Xcode's: the symbol edited where it
/// stands, every place it is in this file with it; Return, and the other
/// files take the name too; Escape puts it back.
///
/// The places come first, from a rename to a stand-in name: where a rename
/// edits does not depend on the name it gives.
- (IBAction)renameSymbol:(nullable id)sender {
    UDCodeEditorViewController *editor = [self _selectedEditor];
    UDLSPCoordinator *lsp = [self _activeSession].lspCoordinator;
    NSString *word = [self _wordAtCaret];
    if (!editor || !lsp.ready || !word.length || _rename.active) {
        NSBeep();
        return;
    }
    _renameCoordinator = lsp;
    _renameIndex = editor.textView.selectedRange.location;
    NSString *standIn = @"udcodeRenameStandIn";
    if (![lsp request:@"textDocument/rename" atIndex:_renameIndex extra:@{ @"newName": standIn }
               target:self action:@selector(_didFindRenamePlaces:)]) {
        NSBeep();
    }
}

- (void)_didFindRenamePlaces:(LSPResponse *)response {
    UDLSPCoordinator *lsp = _renameCoordinator;
    NSDictionary *edit = [response.result isKindOfClass:[NSDictionary class]] ? response.result : nil;
    UDCodeEditorViewController *editor = [self _selectedEditor];
    if (response.error || !edit || !lsp || [self _activeSession].lspCoordinator != lsp) {
        if (response.error) [self _tell:@"The symbol can't be renamed." detail:response.error.localizedDescription];
        else NSBeep();
        return;
    }
    // this file's places: the one at the caret first
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    for (NSDictionary *textEdit in [UDWorkspaceEdit textEditsOfFileURL:lsp.documentURL inEdit:edit]) {
        NSRange range = [lsp characterRangeOfLSPRange:textEdit[@"range"]];
        if (range.location == NSNotFound) continue;
        BOOL atCaret = _renameIndex >= range.location && _renameIndex <= NSMaxRange(range);
        if (atCaret) [ranges insertObject:[NSValue valueWithRange:range] atIndex:0];
        else [ranges addObject:[NSValue valueWithRange:range]];
    }
    if (!ranges.count) {
        NSBeep();
        return;
    }
    _renameEdit = edit;
    _rename = [[UDLinkedEditing alloc] initWithTextView:editor.textView
                                            textStorage:[self _activeSession].textStorage ranges:ranges];
    _rename.delegate = self;
    [self.window makeFirstResponder:editor.textView];
    [_rename begin];
}

/// Return or Escape while renaming: its end. With the Fix-its up: Return
/// applies the one selected, the arrows choose, Escape puts them away.
- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    if (_issuePopup.shown) {
        if (sel_isEqual(command, @selector(insertNewline:))) {
            [_issuePopup chooseSelectedFix];
            return YES;
        }
        if (sel_isEqual(command, @selector(moveDown:)) || sel_isEqual(command, @selector(moveUp:))) {
            NSUInteger index = _issuePopup.selectedIndex;
            _issuePopup.selectedIndex = sel_isEqual(command, @selector(moveDown:)) ? index + 1 : (index ? index - 1 : 0);
            return YES;
        }
        if (sel_isEqual(command, @selector(cancelOperation:))) {
            [_issuePopup close];
            return YES;
        }
    }
    if (!_rename.active) return NO;
    if (sel_isEqual(command, @selector(insertNewline:))) {
        [_rename commit];
        return YES;
    }
    if (sel_isEqual(command, @selector(cancelOperation:))) {
        [_rename cancel];
        return YES;
    }
    return NO;
}

/// Renamed in this file: the other files take the name the same way.
- (void)linkedEditing:(UDLinkedEditing *)editing didEndWithText:(NSString *)text cancelled:(BOOL)cancelled {
    // kept until the next rename: this is called from inside it
    NSDictionary *edit = _renameEdit;
    NSURL *here = _renameCoordinator.documentURL;
    _renameEdit = nil;
    if (cancelled || [text isEqualToString:editing.originalText] || !edit) return;
    NSDictionary *others = [UDWorkspaceEdit edit:edit withNewText:text excludingFileURL:here];
    NSError *error = nil;
    [UDWorkspaceEdit applyEdit:others documents:self error:&error];
    if (error) [self _tell:@"Some files could not be changed." detail:error.localizedDescription];
}

/// The rename under way, if one is.
- (nullable UDLinkedEditing *)renaming {
    return _rename.active ? _rename : nil;
}

/// Editor > Format Document (⌃⇧I): the server's formatting, one undoable edit.
- (IBAction)formatDocument:(nullable id)sender {
    UDLSPCoordinator *lsp = [self _activeSession].lspCoordinator;
    NSDictionary *options = @{ @"options": @{ @"tabSize": @4, @"insertSpaces": @YES } };
    _formattingModel = [self _activeSession].textStorage.textModel;
    if (![lsp request:@"textDocument/formatting" extra:options target:self action:@selector(_didFormat:)]) NSBeep();
}

- (void)_didFormat:(LSPResponse *)response {
    UDTextModel *model = _formattingModel;
    _formattingModel = nil;
    if (response.error) {
        [self _tell:@"The document could not be formatted." detail:response.error.localizedDescription];
        return;
    }
    NSArray *edits = [response.result isKindOfClass:[NSArray class]] ? response.result : nil;
    if (model && edits.count) [UDWorkspaceEdit applyTextEdits:edits toTextModel:model];
}

/// Editor > Fix Issue at Cursor (⌃⌥⌘F), as Xcode's Fix-its: the caret's
/// issue and the server's fixes for it (its code actions, the fixes first,
/// then refactorings), in a panel at the issue.
- (IBAction)fixIssue:(nullable id)sender {
    UDCodeEditorViewController *editor = [self _selectedEditor];
    UDLSPCoordinator *lsp = [self _activeSession].lspCoordinator;
    NSRange selected = editor.textView.selectedRange;
    if (!editor || !lsp.ready) {
        NSBeep();
        return;
    }
    // the caret's line, when nothing is selected: a fix is for its diagnostic
    NSRange range = selected;
    if (!range.length) range = [editor.textView.string lineRangeForRange:selected];
    NSDictionary *params = @{ @"range": [lsp LSPRangeOfCharacterRange:selected],
                              @"context": @{ @"diagnostics": [lsp diagnosticsInCharacterRange:range] } };
    _codeActionCoordinator = lsp;
    NSArray<NSDictionary *> *diagnostics = params[@"context"][@"diagnostics"];
    _issueMessage = [diagnostics.firstObject[@"message"] isKindOfClass:[NSString class]] ? diagnostics.firstObject[@"message"] : nil;
    _issueIndex = diagnostics.count ? [lsp characterRangeOfLSPRange:diagnostics.firstObject[@"range"]].location : selected.location;
    if (_issueIndex == NSNotFound) _issueIndex = selected.location;
    if (![lsp request:@"textDocument/codeAction" extra:params target:self action:@selector(_didFindCodeActions:)]) NSBeep();
}

- (void)_didFindCodeActions:(LSPResponse *)response {
    NSMutableArray<NSDictionary *> *actions = [NSMutableArray array];
    for (NSDictionary *action in [response.result isKindOfClass:[NSArray class]] ? response.result : @[]) {
        if ([action isKindOfClass:[NSDictionary class]] && [action[@"title"] isKindOfClass:[NSString class]]) [actions addObject:action];
    }
    // the preferred, then the quick fixes, then the rest (refactorings)
    [actions sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger ra = [a[@"isPreferred"] boolValue] ? 0 : [a[@"kind"] isEqual:@"quickfix"] ? 1 : 2;
        NSInteger rb = [b[@"isPreferred"] boolValue] ? 0 : [b[@"kind"] isEqual:@"quickfix"] ? 1 : 2;
        return ra < rb ? NSOrderedAscending : ra > rb ? NSOrderedDescending : NSOrderedSame;
    }];
    _codeActions = actions;
    NSTextView *textView = [self _selectedEditor].textView;
    if (!actions.count || !textView) {
        NSBeep();
        return;
    }
    if (!_issuePopup) {
        _issuePopup = [[UDIssuePopupController alloc] init];
        _issuePopup.delegate = self;
    }
    BOOL fixes = [actions.firstObject[@"kind"] isEqual:@"quickfix"] || [actions.firstObject[@"isPreferred"] boolValue];
    NSString *message = _issueMessage ?: (fixes ? @"Fixes" : @"Refactorings");
    [_issuePopup showMessage:message fixes:[actions valueForKey:@"title"] atCharacterIndex:_issueIndex ofTextView:textView];
}

- (void)issuePopup:(UDIssuePopupController *)popup didChooseFixAtIndex:(NSUInteger)index {
    if (index < _codeActions.count) [self _performCodeAction:_codeActions[index]];
}

/// The Fix-its panel, while it is up.
- (nullable UDIssuePopupController *)issuePopup {
    return _issuePopup.shown ? _issuePopup : nil;
}

/// A code action chosen: its edit, then its command (which may send its own
/// edit back, workspace/applyEdit).
- (void)_performCodeAction:(NSDictionary *)action {
    LSPClient *client = _codeActionCoordinator.client;
    // a bare Command, or a CodeAction with an edit and/or a command
    NSDictionary *command = [action[@"command"] isKindOfClass:[NSString class]] ? action
                          : [action[@"command"] isKindOfClass:[NSDictionary class]] ? action[@"command"] : nil;
    if ([action[@"edit"] isKindOfClass:[NSDictionary class]]) [self _applyWorkspaceEdit:action[@"edit"]];
    if (command && client) {
        NSMutableDictionary *params = [@{ @"command": command[@"command"] } mutableCopy];
        if ([command[@"arguments"] isKindOfClass:[NSArray class]]) params[@"arguments"] = command[@"arguments"];
        [client sendRequest:@"workspace/executeCommand" params:params target:nil action:NULL];
    }
}

/// The code actions the last Fix Issue found (for tests: performed by index).
- (NSArray<NSDictionary *> *)codeActions {
    return _codeActions ?: @[];
}

- (void)performCodeActionAtIndex:(NSUInteger)index {
    if (index < _codeActions.count) [self _performCodeAction:_codeActions[index]];
}

/// Typed: after "(" or ",", the signature of the call, its parameter there;
/// after ")", gone.
- (void)_requestSignatureHelp {
    UDCodeEditorViewController *editor = [self _selectedEditor];
    NSTextView *textView = editor.textView;
    NSUInteger caret = textView.selectedRange.location;
    if (!textView || !caret || caret > textView.string.length) return;
    unichar typed = [textView.string characterAtIndex:caret - 1];
    if (typed == ')') {
        [_signatureHelp close];
        return;
    }
    if (typed != '(' && typed != ',') return;
    UDLSPCoordinator *lsp = [self _activeSession].lspCoordinator;
    _signatureTextView = (UDDiagnosticTextView *)textView;
    _signatureIndex = caret;
    [lsp request:@"textDocument/signatureHelp" atIndex:caret extra:nil target:self action:@selector(_didReceiveSignatureHelp:)];
}

- (void)_didReceiveSignatureHelp:(LSPResponse *)response {
    NSDictionary *help = [response.result isKindOfClass:[NSDictionary class]] ? response.result : nil;
    NSArray *signatures = [help[@"signatures"] isKindOfClass:[NSArray class]] ? help[@"signatures"] : nil;
    if (!signatures.count || !_signatureTextView) {
        [_signatureHelp close];
        return;
    }
    NSUInteger active = MIN((NSUInteger)MAX([help[@"activeSignature"] integerValue], 0), signatures.count - 1);
    NSDictionary *signature = signatures[active];
    NSString *text = signature[@"label"] ?: @"";
    NSArray *parameters = [signature[@"parameters"] isKindOfClass:[NSArray class]] ? signature[@"parameters"] : @[];
    NSInteger parameter = [(signature[@"activeParameter"] ?: help[@"activeParameter"]) integerValue];
    if (parameter >= 0 && (NSUInteger)parameter < parameters.count) {
        id label = parameters[(NSUInteger)parameter][@"label"];
        // a parameter's label: its text, or its [start, end] in the signature's
        if ([label isKindOfClass:[NSArray class]] && [label count] == 2) {
            NSUInteger from = [label[0] unsignedIntegerValue], to = [label[1] unsignedIntegerValue];
            label = to <= text.length && from < to ? [text substringWithRange:NSMakeRange(from, to - from)] : nil;
        }
        if ([label isKindOfClass:[NSString class]]) text = [text stringByAppendingFormat:@"\n\n**%@**", label];
    }
    if (!_signatureHelp) _signatureHelp = [[UDHoverViewController alloc] init];
    [_signatureHelp showText:text atCharacterIndex:_signatureIndex ofTextView:_signatureTextView];
}

/// The text the signature help shows (for tests); nil when it is not shown.
- (nullable NSString *)signatureHelpText {
    return _signatureHelp.shown ? _signatureHelp.textView.string : nil;
}

/// The caret moved: the symbol under it, highlighted where it occurs;
/// away from the call, its signature gone.
- (void)textViewDidChangeSelection:(NSNotification *)note {
    NSTextView *textView = note.object;
    if (textView != [self _selectedEditor].textView) return;
    [[self _activeSession].lspCoordinator highlightOccurrencesAtIndex:textView.selectedRange.location];
    [_issuePopup close];
    if (_signatureHelp.shown && _signatureTextView == textView) {
        NSUInteger caret = textView.selectedRange.location;
        NSString *string = textView.string;
        NSRange between = caret >= _signatureIndex ? NSMakeRange(_signatureIndex, caret - _signatureIndex)
                                                   : NSMakeRange(caret, _signatureIndex - caret);
        if (caret < _signatureIndex - 1 || NSMaxRange(between) > string.length ||
            [[string substringWithRange:between] rangeOfString:@"\n"].location != NSNotFound) {
            [_signatureHelp close];
        }
    }
}

/// A file chosen in the project's files: its tab.
- (void)fileNavigator:(UDFileNavigatorViewController *)navigator openFileAtURL:(NSURL *)url {
    [self _showFile:url.path];
}

/// A view from its own XIB, filling the host the window's XIB has for it.
- (void)_putView:(NSView *)view inHost:(NSView *)host {
    view.frame = host.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [host addSubview:view];
}

/// The debug bar on top of the debug pane, the area under it: laid out
/// here rather than by autoresizing, as the pane is nothing high while it is
/// hidden, and what autoresizing loses then it does not get back.
- (void)_layoutDebugPane {
    NSRect bounds = _debugBarHost.superview.bounds;
    CGFloat bar = NSHeight(_debugBarHost.frame);
    if (NSHeight(bounds) < bar + 20) return;
    // the bar, and at its right the Debug | Terminal switch
    NSRect control = _bottomAreaControl.frame;
    control.origin.x = NSWidth(bounds) - NSWidth(control) - 4;
    control.origin.y = NSMaxY(bounds) - bar + floor((bar - NSHeight(control)) / 2);
    _bottomAreaControl.frame = control;
    _debugBarHost.frame = NSMakeRect(0, NSMaxY(bounds) - bar, MAX(0, NSMinX(control) - 4), bar);
    NSRect area = NSMakeRect(0, 0, NSWidth(bounds), NSHeight(bounds) - bar);
    _debugAreaHost.frame = area;
    _terminalHost.frame = area;
}

// ---------------------------------------------------------------------------
// MARK: - The terminal, in the bottom area
// ---------------------------------------------------------------------------

/// The bottom area's switch: the debugger's (0) or the terminal (1).
- (IBAction)bottomAreaChanged:(nullable id)sender {
    if (_bottomAreaControl.selectedSegment == 1) [self showTerminal:sender];
    else [self _showBottomArea:0];
}

- (void)_showBottomArea:(NSInteger)which {
    [_bottomAreaControl setSelectedSegment:which];
    [_debugAreaHost setHidden:which != 0];
    [_terminalHost setHidden:which != 1];
    [_debugSplit setPane:UDDebugAreaPane visible:YES];
}

/// The terminal's folder: the project's, else the selected file's, else home.
- (NSString *)_terminalDirectory {
    if (_project) return _project.folderURL.path;
    UDCodeDocument *document = _editorTabs.selectedItem.representedObject;
    return document.fileURL ? document.fileURL.path.stringByDeletingLastPathComponent : NSHomeDirectory();
}

/// View > Terminal (⌃`): the bottom area's terminal, a shell started in it
/// (the project's environment, GNUstep's included) when none runs.
- (IBAction)showTerminal:(nullable id)sender {
    if (!_terminal) {
        _terminal = [[UDTerminalViewController alloc] init];
        [self _putView:_terminal.view inHost:_terminalHost];
    }
    [self _showBottomArea:1];
    [self _layoutDebugPane];
    if (!_terminal.running) {
        NSDictionary *environment = _project ? _project.buildEnvironment : nil;
        NSString *shell = _project ? _project.shell : [UDProject userShell];
        if (![_terminal startShell:shell inDirectory:[self _terminalDirectory] environment:environment]) NSBeep();
    }
    [self.window makeFirstResponder:_terminal.terminalView];
}

- (void)_debugPaneDidResize:(NSNotification *)note {
    [self _layoutDebugPane];
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
    _navigatorControl.selectedSegment = UDIssuesNavigatorSegment;
    [self navigatorChanged:nil];
}

- (IBAction)showSourceControlNavigator:(nullable id)sender {
    [_paneSplit setPane:UDNavigatorPane visible:YES];
    _navigatorControl.selectedSegment = UDSourceControlNavigatorSegment;
    [self navigatorChanged:nil];
}

- (IBAction)showFindNavigator:(nullable id)sender {
    [_paneSplit setPane:UDNavigatorPane visible:YES];
    _navigatorControl.selectedSegment = UDFindNavigatorSegment;
    [self navigatorChanged:nil];
}

- (IBAction)showTestNavigator:(nullable id)sender {
    [_paneSplit setPane:UDNavigatorPane visible:YES];
    _navigatorControl.selectedSegment = UDTestNavigatorSegment;
    [self navigatorChanged:nil];
    if (!_testCatalogStore) [self reloadTests];
}

- (IBAction)showDebugNavigator:(nullable id)sender {
    [_paneSplit setPane:UDNavigatorPane visible:YES];
    _navigatorControl.selectedSegment = UDDebugNavigatorSegment;
    [self navigatorChanged:nil];
}

- (IBAction)showBuildNavigator:(nullable id)sender {
    [_paneSplit setPane:UDNavigatorPane visible:YES];
    _navigatorControl.selectedSegment = UDBuildNavigatorSegment;
    [self navigatorChanged:nil];
}

- (IBAction)showBreakpointNavigator:(nullable id)sender {
    [_paneSplit setPane:UDNavigatorPane visible:YES];
    _navigatorControl.selectedSegment = UDBreakpointNavigatorSegment;
    [self navigatorChanged:nil];
}

- (IBAction)toggleDebugArea:(nullable id)sender {
    [_debugSplit setPane:UDDebugAreaPane visible:![_debugSplit isPaneVisible:UDDebugAreaPane]];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    // sel_isEqual: a menu item's selector, from its XIB, is untyped on
    // GNUstep's runtime, and not the same pointer as a typed @selector.
    SEL action = item.action;
    if (sel_isEqual(action, @selector(build:)) || sel_isEqual(action, @selector(clean:))) {
        return _buildRunner != nil && !_buildRunner.running;
    } else if (sel_isEqual(action, @selector(runWithoutDebugging:))) {
        return _buildRunner != nil && !_buildRunner.running && (!_debugSession || _debugSession.state == UDDebugSessionStateEnded);
    } else if (sel_isEqual(action, @selector(selectLaunchConfiguration:))) {
        item.state = [item.representedObject isEqual:self.selectedLaunchConfiguration] ? NSControlStateValueOn : NSControlStateValueOff;
        return _project != nil;
    } else if (sel_isEqual(action, @selector(test:))) {
        return _buildRunner != nil && !_buildRunner.running && (!_debugSession || _debugSession.state == UDDebugSessionStateEnded);
    } else if (sel_isEqual(action, @selector(runTask:))) {
        return _buildRunner != nil && !_buildRunner.running;
    } else if (sel_isEqual(action, @selector(showProjectSettings:))) {
        return _project != nil && !_projectSettings;
    } else if (sel_isEqual(action, @selector(saveAllDocuments:))) {
        return _project != nil;
    } else if (sel_isEqual(action, @selector(startDebugging:)) && _project) {
        return !_buildRunner.running && (!_debugSession || _debugSession.state == UDDebugSessionStateEnded);
    } else if (sel_isEqual(action, @selector(startDebugging:))) {
        UDCodeDocument *document = _editorTabs.selectedItem.representedObject;
        return document.fileURL && (!_debugSession || _debugSession.state == UDDebugSessionStateEnded);
    } else if (sel_isEqual(action, @selector(stopDebugging:))) {
        return _debugSession.canStop || _buildRunner.running;
    } else if (sel_isEqual(action, @selector(debugContinueOrPause:))) {
        item.title = _debugSession.canPause ? @"Pause" : @"Continue";
        return [_debugBar canPerformAction:@selector(continueOrPause:)];
    } else if (sel_isEqual(action, @selector(debugStepOver:)) || sel_isEqual(action, @selector(debugStepInto:)) ||
               sel_isEqual(action, @selector(debugStepOut:))) {
        return [_debugBar canPerformAction:@selector(stepOver:)];
    } else if (sel_isEqual(action, @selector(debugStepBack:))) {
        // Hidden but for an adapter that steps back (as VS Code's); GNUstep's
        // menu items do not hide, and are only disabled.
        if ([item respondsToSelector:@selector(setHidden:)]) [(id)item setHidden:!_debugSession.client.supportsStepBack];
        return [_debugBar canPerformAction:@selector(stepBack:)];
    } else if (sel_isEqual(action, @selector(runToCursor:)) || sel_isEqual(action, @selector(jumpToCursor:))) {
        return [[self _selectedEditor] validateMenuItem:item];
    } else if (sel_isEqual(action, @selector(toggleBreakpoint:))) {
        return [self _selectedEditor].breakpointFile != nil;
    } else if (sel_isEqual(action, @selector(toggleAuthors:))) {
        UDCodeEditorViewController *editor = [self _selectedEditor];
        item.state = editor.showsAuthors ? NSControlStateValueOn : NSControlStateValueOff;
        return editor && [_sourceControl respondsToSelector:@selector(blameOfPath:target:action:)] &&
               [_sourceControl containsPath:[self _documentOfEditor:editor].fileURL.path];
    } else if (sel_isEqual(action, @selector(commitChanges:))) {
        return _sourceControl != nil;
    } else if (sel_isEqual(action, @selector(toggleCodeReview:))) {
        UDDiffEditorViewController *review = [self _selectedDiffEditor];
        item.title = review ? @"Hide Code Review" : @"Show Code Review";
        return review ? review.modifiedOnLeft : [_editorTabs.selectedItem.representedObject fileURL] != nil;
    } else if (sel_isEqual(action, @selector(goToNextChange:)) || sel_isEqual(action, @selector(goToPreviousChange:))) {
        return [self _selectedDiffEditor].diff.changes.count > 0;
    } else if (sel_isEqual(action, @selector(togglePreview:))) {
        UDCodeEditorViewController *editor = [self _selectedEditor];
        return editor && [editor validateMenuItem:item];
    } else if (sel_isEqual(action, @selector(toggleDebugArea:))) {
        item.title = [_debugSplit isPaneVisible:UDDebugAreaPane] ? @"Hide Debug Area" : @"Show Debug Area";
    }
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
    // a file an extension opens itself (a database's), not as text
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if ([extension respondsToSelector:@selector(workbench:openURL:)] && [extension workbench:self openURL:url]) return;
    }
    // by its real path, as the project's folder is known: a file reached by
    // another (a link, Windows' C:/Users/ARTYOM~1) is still the project's,
    // and its language server's
    if (url.isFileURL) url = [NSURL fileURLWithPath:UDRealPath(url.path)];
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

/// @a document's session, made when it has none (*first then YES); started
/// by -_startSession:ofDocument: once a view of it has loaded.
- (UDEditorSession *)_sessionOpeningDocument:(UDCodeDocument *)document first:(BOOL *)first {
    UDEditorSession *session = [self _sessionForDocument:document];
    *first = session == nil;
    if (*first) {
        session = [[UDEditorSession alloc] initWithDocument:document];
        [_sessions setObject:session forKey:document];
    }
    return session;
}

/// Highlighting, and a file's language server; a saved copy (Compare with
/// Saved's) has only the first.
- (void)_startSession:(UDEditorSession *)session ofDocument:(UDCodeDocument *)document {
    [session activateWithTheme:_currentTheme];
    if ([self _isCopy:document]) return;
    if (![self _startProjectLanguageServerOf:session document:document]) [session startLanguageServer];
    session.lspCoordinator.editDocuments = self;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_diagnosticsDidChange:)
                                                 name:UDDiagnosticsDidChangeNotification
                                               object:document.diagnosticStore];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textDidChange:)
                                                 name:UDTextModelDidChangeNotification
                                               object:document.textModel];
}

/// An editor of @a document's, as its tabs have: links, hovers, breakpoints.
- (void)_configureEditor:(UDCodeEditorViewController *)editor ofDocument:(UDCodeDocument *)document {
    editor.previewBaseURL = document.fileURL;
    editor.linkDelegate = self;
    editor.sourceControlDelegate = self;
    editor.textView.delegate = self;
    [self _updateQuickDiffOfDocument:document];
    if (document.fileURL) [editor showBreakpointsOfStore:_breakpoints forFile:document.fileURL.path];
}

/// A tab for @a document: its session (made with its first tab), and an
/// editor of its own.
- (void)_openTabForDocument:(UDCodeDocument *)document {
    BOOL first = NO;
    UDEditorSession *session = [self _sessionOpeningDocument:document first:&first];

    // The editor's view loads first, so its layout manager is attached
    // before the session's first parse.
    UDCodeEditorViewController *editor = [[UDCodeEditorViewController alloc] initWithTextStorage:session.textStorage];
    [editor configureForLanguageMode:document.languageMode];
    [self _configureEditor:editor ofDocument:document];
    if (first) [self _startSession:session ofDocument:document];
    // Xcode's jump bar: the project's folders, the file, its symbols
    UDJumpBarController *jumpBar = [[UDJumpBarController alloc] initWithEditor:editor session:session rootURL:_project.folderURL];
    jumpBar.delegate = self;
    jumpBar.hiddenNames = _fileNavigator.hiddenNames;
    editor.jumpBarController = jumpBar;
    editor.showsJumpBar = YES;

    [self _documentsChanged];      // before the tab selects its row in the files list
    UDTabBarItem *item = [_editorTabs addItemWithTitle:document.displayName
                                     representedObject:document
                                        viewController:editor];
    item.toolTip = document.fileURL.path;
    item.dirty = document.isModified;
}

/// A diff tab: @a original on the left, @a modified (the tab's document)
/// on the right, as VS Code's diff editor.
- (void)_openDiffOfOriginal:(UDCodeDocument *)original modified:(UDCodeDocument *)modified
                      title:(NSString *)title originalEditable:(BOOL)originalEditable {
    BOOL originalFirst = NO, modifiedFirst = NO;
    UDEditorSession *originalSession = [self _sessionOpeningDocument:original first:&originalFirst];
    UDEditorSession *modifiedSession = [self _sessionOpeningDocument:modified first:&modifiedFirst];
    UDDiffEditorViewController *diff = [[UDDiffEditorViewController alloc] initWithOriginalTextStorage:originalSession.textStorage
                                                                                  modifiedTextStorage:modifiedSession.textStorage];
    diff.originalEditable = originalEditable;
    [diff configureForLanguageMode:modified.languageMode];
    [self _configureEditor:diff.modifiedEditor ofDocument:modified];
    if (originalFirst) [self _startSession:originalSession ofDocument:original];
    if (modifiedFirst) [self _startSession:modifiedSession ofDocument:modified];

    [self _documentsChanged];
    UDTabBarItem *item = [_editorTabs addItemWithTitle:title representedObject:modified viewController:diff];
    [_diffOriginals setObject:original forKey:item];
    item.toolTip = [NSString stringWithFormat:@"%@ ↔ %@", original.fileURL.path ?: original.displayName,
                                                          modified.fileURL.path ?: modified.displayName];
    item.dirty = modified.isModified;
    [diff computeDiff];
}

/// Xcode's Code Review of the selected tab's file: its editor (as it is) on
/// the left, the file as saved on the right (read-only, following the file);
/// again, the editor alone. A comparison of two files is a tab of its own.
- (IBAction)toggleCodeReview:(nullable id)sender {
    UDTabBarItem *item = _editorTabs.selectedItem;
    id controller = item ? [_editorTabs viewControllerForItem:item] : nil;
    if ([controller isKindOfClass:[UDDiffEditorViewController class]]) {
        UDDiffEditorViewController *review = controller;
        if (!review.modifiedOnLeft) return;
        UDCodeDocument *copy = [_diffOriginals objectForKey:item];
        UDCodeEditorViewController *editor = review.modifiedEditor;
        [review invalidate];
        [_editorTabs setViewController:editor forItem:item];
        [_diffOriginals removeObjectForKey:item];
        if (copy) [self _closeDocumentIfUnshown:copy];
        [self.window makeFirstResponder:editor.textView];
    } else if ([controller isKindOfClass:[UDCodeEditorViewController class]]) {
        UDCodeDocument *document = item.representedObject;
        if (!document.fileURL) return;
        NSError *error = nil;
        NSString *saved = [UDCodeDocument textOfURL:document.fileURL error:&error];
        if (!saved) {
            if (error) [self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
            return;
        }
        UDCodeEditorViewController *editor = controller;
        editor.showsPreview = NO;
        // the source control's (Xcode's: the last commit's), else the saved file's
        NSString *reviewed = [_sourceControl codeReviewTextOfPath:document.fileURL.path];
        BOOL inRepository = reviewed != nil;
        if (inRepository) saved = reviewed;
        UDCodeDocument *copy = [[UDCodeDocument alloc] initWithText:saved fileURL:nil languageMode:document.languageMode];
        if (inRepository) [_headCopies setObject:document.fileURL.path forKey:copy];
        else [_savedCopies setObject:document.fileURL forKey:copy];
        BOOL first = NO;
        UDEditorSession *copySession = [self _sessionOpeningDocument:copy first:&first];
        UDDiffEditorViewController *review = [[UDDiffEditorViewController alloc] initWithOriginalTextStorage:copySession.textStorage
                                                                                              modifiedEditor:editor];
        review.modifiedOnLeft = YES;
        [review configureForLanguageMode:document.languageMode];
        [self _startSession:copySession ofDocument:copy];
        [_diffOriginals setObject:copy forKey:item];
        [_editorTabs setViewController:review forItem:item];
        [review computeDiff];
        [self.window makeFirstResponder:editor.textView];
    }
    [self _updatePreviewControl];
}

/// The file navigator's Select for Compare, then Compare with Selected: the
/// one selected first on the left, both editable (VS Code's Explorer).
- (void)_selectForCompare:(NSMenuItem *)sender {
    self.selectedForCompare = sender.representedObject;
}

- (void)_compareWithSelected:(NSMenuItem *)sender {
    NSURL *originalURL = self.selectedForCompare, *modifiedURL = sender.representedObject;
    if (!originalURL || !modifiedURL) return;
    UDCodeDocument *original = [self _documentOpeningURL:originalURL], *modified = [self _documentOpeningURL:modifiedURL];
    if (!original || !modified) return;
    [self _openDiffOfOriginal:original modified:modified
                        title:[NSString stringWithFormat:@"%@ ↔ %@", original.displayName, modified.displayName] originalEditable:YES];
}

/// @a url's document in the workspace, read when it is not there yet.
- (nullable UDCodeDocument *)_documentOpeningURL:(NSURL *)url {
    url = [NSURL fileURLWithPath:UDRealPath(url.path)];
    UDCodeDocument *document = [_workspaceModel documentForFileURL:url];
    if (document) return document;
    NSError *error = nil;
    document = [_workspaceModel addDocumentFromURL:url error:&error];
    if (!document) NSLog(@"[UDDocumentWindowController] Cannot open %@: %@", url.lastPathComponent, error);
    return document;
}

- (NSArray<NSMenuItem *> *)fileNavigator:(UDFileNavigatorViewController *)navigator menuItemsForURL:(NSURL *)url {
    BOOL folder = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&folder] || folder) return @[];
    NSMenuItem *select = [[NSMenuItem alloc] initWithTitle:@"Select for Compare" action:@selector(_selectForCompare:) keyEquivalent:@""];
    select.target = self;
    select.representedObject = url;
    NSMutableArray<NSMenuItem *> *items = [NSMutableArray arrayWithObject:select];
    if (self.selectedForCompare && ![self.selectedForCompare isEqual:url]) {
        NSMenuItem *compare = [[NSMenuItem alloc]
            initWithTitle:[NSString stringWithFormat:@"Compare with “%@”", self.selectedForCompare.lastPathComponent]
                   action:@selector(_compareWithSelected:) keyEquivalent:@""];
        compare.target = self;
        compare.representedObject = url;
        [items addObject:compare];
    }
    return items;
}

- (nullable UDDiffEditorViewController *)_selectedDiffEditor {
    UDTabBarItem *item = _editorTabs.selectedItem;
    id controller = item ? [_editorTabs viewControllerForItem:item] : nil;
    return [controller isKindOfClass:[UDDiffEditorViewController class]] ? controller : nil;
}

- (IBAction)goToNextChange:(nullable id)sender {
    [[self _selectedDiffEditor] goToNextChange:sender];
}

- (IBAction)goToPreviousChange:(nullable id)sender {
    [[self _selectedDiffEditor] goToPreviousChange:sender];
}

/// Compare with Saved's originals of @a url's file: its text again.
- (void)_refreshSavedCopiesOfURL:(nullable NSURL *)url {
    if (!url) return;
    NSString *path = url.path.stringByStandardizingPath;
    for (UDCodeDocument *copy in [_savedCopies keyEnumerator].allObjects) {
        if (![[[_savedCopies objectForKey:copy] path].stringByStandardizingPath isEqualToString:path]) continue;
        NSString *saved = [UDCodeDocument textOfURL:url error:NULL];
        UDTextModel *model = copy.textModel;
        if (!saved || [saved isEqualToString:[model getValue]]) continue;
        NSInteger lines = [model getLineCount];
        [model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 1, lines, [model getLineMaxColumn:lines])
                                                                text:saved] ]];
    }
}

/// The tab's editor: a diff's, its modified side's (its document's); none
/// of a history's.
- (nullable UDCodeEditorViewController *)_editorOfItem:(nullable UDTabBarItem *)item {
    id controller = item ? [_editorTabs viewControllerForItem:item] : nil;
    if ([controller isKindOfClass:[UDDiffEditorViewController class]]) return [controller modifiedEditor];
    return [controller isKindOfClass:[UDCodeEditorViewController class]] ? controller : nil;
}

- (nullable UDCodeEditorViewController *)_selectedEditor {
    return [self _editorOfItem:_editorTabs.selectedItem];
}

- (nullable UDEditorSession *)_activeSession {
    return [self _sessionForDocument:_editorTabs.selectedItem.representedObject];
}

/// @a document's tabs: its editors', then the diffs it is a side of.
- (NSArray<UDTabBarItem *> *)_itemsForDocument:(UDCodeDocument *)document {
    NSMutableArray *items = [NSMutableArray array], *diffs = [NSMutableArray array];
    for (UDTabBarItem *item in _editorTabs.items) {
        if ([_diffOriginals objectForKey:item]) {
            if (item.representedObject == document || [_diffOriginals objectForKey:item] == document) [diffs addObject:item];
        } else if (item.representedObject == document) {
            [items addObject:item];
        }
    }
    [items addObjectsFromArray:diffs];
    return items;
}

/// The documents @a item shows: a diff's two; a history's none.
- (NSArray<UDCodeDocument *> *)_documentsOfItem:(UDTabBarItem *)item {
    NSMutableArray<UDCodeDocument *> *documents = [NSMutableArray array];
    if ([item.representedObject isKindOfClass:[UDCodeDocument class]]) [documents addObject:item.representedObject];
    UDCodeDocument *original = [_diffOriginals objectForKey:item];
    if (original) [documents addObject:original];
    return documents;
}

/// A text of the window's own, not a file's: Code Review's and history's.
- (BOOL)_isCopy:(UDCodeDocument *)document {
    return [_savedCopies objectForKey:document] || [_headCopies objectForKey:document] || [_scratchDocuments containsObject:document];
}

/// @a before beside @a after (the text of @a path's file at two commits,
/// say), both read-only, in a tab of their own.
- (void)_openReadOnlyDiffOf:(NSString *)before and:(NSString *)after path:(NSString *)path title:(NSString *)title {
    UDLanguageMode *mode = [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:[NSURL fileURLWithPath:path]];
    UDCodeDocument *original = [[UDCodeDocument alloc] initWithText:before fileURL:nil languageMode:mode];
    UDCodeDocument *modified = [[UDCodeDocument alloc] initWithText:after fileURL:nil languageMode:mode];
    [_scratchDocuments addObject:original];
    [_scratchDocuments addObject:modified];
    [self _openDiffOfOriginal:original modified:modified title:title originalEditable:NO];
    UDDiffEditorViewController *diff = [self _selectedDiffEditor];
    diff.modifiedEditor.textView.editable = NO;
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
    // the build's, for files no tab has
    NSString *folder = [_project.folderURL.path stringByAppendingString:@"/"];
    for (NSString *path in _buildIssuePaths) {
        UDDiagnosticStore *store = _buildRunner.diagnostics[path];
        if (!store) continue;
        [stores addObject:store];
        [names addObject:[path hasPrefix:folder] ? [path substringFromIndex:folder.length] : path];
    }
    [_errorsViewController setStores:stores displayNames:names];
}

// ---------------------------------------------------------------------------
// MARK: - UDEditorTabsControllerDelegate
// ---------------------------------------------------------------------------

/// The last tab of a document with unsaved changes asks first.
- (BOOL)editorTabs:(UDEditorTabsController *)tabs shouldCloseItem:(UDTabBarItem *)item {
    for (UDCodeDocument *document in [self _documentsOfItem:item]) {
        if ([self _isCopy:document]) continue;            // the file's own text, nothing to lose
        if (!document.isModified || [self _itemsForDocument:document].count > 1) continue;
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Close “%@” without saving?", document.displayName];
        alert.informativeText = @"Its changes are lost.";
        [alert addButtonWithTitle:@"Close"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return NO;
    }
    return YES;
}

/// A document's last tab closed: its session and its place in the workspace go.
- (void)editorTabs:(UDEditorTabsController *)tabs didCloseItem:(UDTabBarItem *)item {
    NSArray<UDCodeDocument *> *documents = [self _documentsOfItem:item];
    [_diffOriginals removeObjectForKey:item];
    [_historyTabs removeObjectForKey:item];
    for (UDCodeDocument *document in documents) [self _closeDocumentIfUnshown:document];
}

/// @a document, in no tab now: its session and its place in the workspace go.
- (void)_closeDocumentIfUnshown:(UDCodeDocument *)document {
    if ([self _itemsForDocument:document].count > 0) return;
    [[self _sessionForDocument:document] close];
    [_sessions removeObjectForKey:document];
    [_savedCopies removeObjectForKey:document];
    [_headCopies removeObjectForKey:document];
    [_scratchDocuments removeObject:document];
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
    [self _updatePreviewControl];
    UDCodeEditorViewController *editor = [self _selectedEditor];
    if (editor) [self.window makeFirstResponder:editor.showsPreview ? editor.previewTextView : editor.textView];
}

// ---------------------------------------------------------------------------
// MARK: - Source | Preview
// ---------------------------------------------------------------------------

/// The switch follows the selected tab: shown for a mode with a preview, the
/// tab bar taking the room otherwise.
- (void)_updatePreviewControl {
    UDCodeEditorViewController *editor = [self _selectedEditor];
    UDCodeDocument *document = _editorTabs.selectedItem.representedObject;
    if (document.fileURL) editor.previewBaseURL = document.fileURL;   // saved as another file since
    UDDiffEditorViewController *diff = [self _selectedDiffEditor];
    BOOL reviewShown = document.fileURL && (!diff || diff.modifiedOnLeft);
    BOOL previewShown = editor.canShowPreview && !diff;
    _previewControl.hidden = !previewShown;
    [_previewControl setSelectedSegment:editor.showsPreview ? 1 : 0];
    _reviewButton.hidden = !reviewShown;
    _reviewButton.state = diff ? NSControlStateValueOn : NSControlStateValueOff;

    // right to left, at the bar's right: Code Review, Source | Preview, then the tabs
    UDTabBarView *bar = _editorTabs.tabBar;
    CGFloat right = NSWidth(bar.superview.bounds) - 4;
    if (reviewShown) {
        NSRect frame = _reviewButton.frame;
        frame.origin.x = right - NSWidth(frame);
        _reviewButton.frame = frame;
        right = NSMinX(frame) - 4;
    }
    if (previewShown) {
        NSRect frame = _previewControl.frame;
        frame.origin.x = right - NSWidth(frame);
        _previewControl.frame = frame;
        right = NSMinX(frame) - 4;
    }
    NSRect frame = bar.frame;
    frame.size.width = MAX(0, (reviewShown || previewShown ? right : NSWidth(bar.superview.bounds)) - NSMinX(frame));
    bar.frame = frame;
}

- (void)_editorPreviewDidChange:(NSNotification *)note {
    if (note.object == [self _selectedEditor]) [self _updatePreviewControl];
}

- (IBAction)previewControlChanged:(nullable id)sender {
    [self _selectedEditor].showsPreview = _previewControl.selectedSegment == 1;
}

/// A link in a preview to a file of ours: its tab (a new one, or the one it
/// has), read in Preview, or ⌘: its text, to edit. Anything else (a web
/// page, an image, a folder) opens as any link does.
- (BOOL)codeEditor:(UDCodeEditorViewController *)editor openLink:(NSURL *)url editing:(BOOL)editing {
    if (!url.isFileURL) return NO;
    BOOL folder = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&folder]) {
        NSBeep();                      // a link to nothing: nothing to open
        return YES;
    }
    if (folder || ![self _isTextFile:url]) return NO;
    [self _showFile:url.path];
    UDCodeDocument *document = _editorTabs.selectedItem.representedObject;
    UDCodeEditorViewController *shown = [self _selectedEditor];
    if (!shown || !document.fileURL || ![UDRealPath(document.fileURL.path) isEqualToString:UDRealPath(url.path)]) {
        return YES;                    // it would not open (logged)
    }
    if (editing || !shown.canShowPreview) {
        [shown followPreviewLink:url editing:YES];     // its text, at the line a #L12 names
    } else {
        shown.showsPreview = YES;
        if (url.fragment.length) [shown revealPreviewAnchor:url.fragment];
        [self.window makeFirstResponder:shown.previewTextView];
    }
    return YES;
}

/// A file for a tab: one a language mode knows, else text (no NUL in its
/// first 4 KB).
- (BOOL)_isTextFile:(NSURL *)url {
    UDLanguageMode *mode = [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:url];
    if (![mode.identifier isEqualToString:@"plaintext"]) return YES;
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:url.path];
    NSData *head = [file readDataOfLength:4096];
    [file closeFile];
    return head && memchr(head.bytes, 0, head.length) == NULL;
}

/// View > Show Preview (⌥⌘↩), wherever the focus is.
- (IBAction)togglePreview:(nullable id)sender {
    [[self _selectedEditor] togglePreview:sender];
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
    if (_editorTabs.selectedItem.representedObject == document) {
        [self _updateInspector];
        // once the text view has the edit and its caret
        [self performSelector:@selector(_requestSignatureHelp) withObject:nil afterDelay:0
                      inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode ]];
    }
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
        if (item.representedObject != doc) continue;          // (a diff's original side)
        [self _editorOfItem:item].gutterView.errorFractions = fractions;
    }
}

// ---------------------------------------------------------------------------
// MARK: - UDErrorsViewControllerDelegate — click to navigate
// ---------------------------------------------------------------------------

- (void)errorsViewController:(UDErrorsViewController *)vc
         didSelectDiagnostic:(UDDiagnosticItem *)diagnostic
                     inStore:(UDDiagnosticStore *)store {
    UDCodeDocument *doc = [_workspaceModel documentForDiagnosticStore:store];
    if (!doc) {
        // the build's, of a file no tab has: its tab
        NSString *path = [_buildRunner.diagnostics allKeysForObject:store].firstObject;
        if (!path) return;
        [self _showFile:path];
        doc = [_workspaceModel documentForFileURL:[NSURL fileURLWithPath:path]];
    }
    UDTabBarItem *item = doc ? [self _itemsForDocument:doc].firstObject : nil;
    if (!item) return;
    [_editorTabs selectItem:item];
    UDCodeEditorViewController *editor = [self _editorOfItem:item];
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
// MARK: - Source control (UDSourceControl: an extension's, git's; Xcode's look)
// ---------------------------------------------------------------------------

/// The project's source control: the first extension's that has one for its folder.
- (void)reloadSourceControl {
    id<UDSourceControl> sourceControl = nil;
    for (id<UDExtension> extension in _project ? [UDLanguageModeRegistry sharedRegistry].extensions : @[]) {
        if (![extension respondsToSelector:@selector(sourceControlForFolder:)]) continue;
        sourceControl = [extension sourceControlForFolder:_project.folderURL.path];
        if (sourceControl) break;
    }
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_sourceControl) [center removeObserver:self name:UDSourceControlDidChangeNotification object:_sourceControl];
    _sourceControl = sourceControl;
    sourceControl.host = self;
    _sourceControlNavigator.sourceControl = sourceControl;
    [self _rebuildIntegrateMenu];
    [_fileNavigator badgesDidChange];
    if (!sourceControl) return;
    [center addObserver:self selector:@selector(_sourceControlDidChange:) name:UDSourceControlDidChangeNotification object:sourceControl];
    [sourceControl refresh];
}

- (void)_sourceControlDidChange:(NSNotification *)note {
    [_fileNavigator badgesDidChange];
    for (UDCodeDocument *document in _workspaceModel.documents) [self _updateQuickDiffOfDocument:document];
    for (UDTabBarItem *item in _editorTabs.items) {
        // Authors, after a commit
        UDCodeEditorViewController *editor = [self _editorOfItem:item];
        UDCodeDocument *document = item.representedObject;
        if (editor.showsAuthors && [document isKindOfClass:[UDCodeDocument class]] && document.fileURL) {
            [_sourceControl blameOfPath:document.fileURL.path target:self action:@selector(_didReadBlame:)];
        }
    }
    // Code Review's last commit, after a commit
    for (UDCodeDocument *copy in [_headCopies keyEnumerator].allObjects) {
        [self _replaceTextOf:copy with:[_sourceControl codeReviewTextOfPath:[_headCopies objectForKey:copy]] ?: @""];
    }
}

// MARK: The Integrate menu: Commit… (the editor's), then the source control's and the extensions'

/// The contributed items' tag.
static const NSInteger UDContributedMenuItemTag = 0x5C;

- (nullable NSMenu *)_integrateMenu {
    return [[NSApp mainMenu] itemWithTitle:@"Integrate"].submenu;
}

- (void)_rebuildIntegrateMenu {
    NSMenu *menu = [self _integrateMenu];
    if (!menu) return;
    for (NSMenuItem *item in [menu.itemArray copy]) {
        if (item.tag == UDContributedMenuItemTag) [menu removeItem:item];
    }
    NSMutableArray<NSArray<NSMenuItem *> *> *sections = [NSMutableArray array];
    if (_sourceControl) [sections addObject:[_sourceControl integrateMenuItems]];
    NSMutableArray<NSMenuItem *> *global = [NSMutableArray array];
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if (![extension respondsToSelector:@selector(sourceControlMenuItemsForHost:folder:)]) continue;
        [global addObjectsFromArray:[extension sourceControlMenuItemsForHost:self folder:_project.folderURL.path]];
    }
    [sections addObject:global];
    for (NSArray<NSMenuItem *> *section in sections) {
        if (section.count == 0) continue;
        NSMutableArray *items = [NSMutableArray arrayWithObject:[NSMenuItem separatorItem]];
        [items addObjectsFromArray:section];
        for (NSMenuItem *item in items) {
            item.tag = UDContributedMenuItemTag;
            [menu addItem:item];
        }
    }
}

- (void)windowDidBecomeKey:(NSNotification *)note {
    [self _rebuildIntegrateMenu];
    [self _rebuildEditorMenu];
}

// ---------------------------------------------------------------------------
// MARK: - The workbench (UDWorkbench): what extensions contribute to the window
// ---------------------------------------------------------------------------

/// Each extension's navigator: a segment after the window's own, its view in
/// a tab of the navigator's.
- (void)_addExtensionNavigators {
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if (![extension respondsToSelector:@selector(navigatorViewControllerForWorkbench:)]) continue;
        NSViewController *navigator = [extension navigatorViewControllerForWorkbench:self];
        if (!navigator) continue;
        if (!_extensionNavigators) _extensionNavigators = [NSMapTable strongToStrongObjectsMapTable];
        NSInteger segment = _navigatorControl.segmentCount;
        _navigatorControl.segmentCount = segment + 1;
        NSImage *image = [extension respondsToSelector:@selector(navigatorImage)] ? [extension navigatorImage] : nil;
        if (image) [_navigatorControl setImage:image forSegment:segment];
        else [_navigatorControl setLabel:@"•" forSegment:segment];
        [_navigatorControl.cell setToolTip:navigator.title ?: @"" forSegment:segment];
        [_navigatorControl.cell setTag:segment forSegment:segment];
        NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:navigator.title ?: @"extension"];
        NSView *host = [[NSView alloc] initWithFrame:_navigatorTabView.contentRect];
        item.view = host;
        [_navigatorTabView addTabViewItem:item];
        [self _putView:navigator.view inHost:host];
        [_extensionNavigators setObject:@[ navigator, @(segment) ] forKey:extension];
    }
    // the segments shared out over the control's width, as Xcode's
    CGFloat width = floor(NSWidth(_navigatorControl.frame) / MAX(_navigatorControl.segmentCount, 1)) - 1;
    for (NSInteger segment = 0; segment < _navigatorControl.segmentCount; segment++) {
        [_navigatorControl setWidth:width forSegment:segment];
    }
}

- (void)showNavigatorOfExtension:(id<UDExtension>)extension {
    NSArray *entry = [_extensionNavigators objectForKey:extension];
    if (!entry) return;
    [_paneSplit setPane:UDNavigatorPane visible:YES];
    _navigatorControl.selectedSegment = [entry[1] integerValue];
    [self navigatorChanged:nil];
}

- (nullable UDCodeDocument *)selectedDocument {
    UDTabBarItem *item = _editorTabs.selectedItem;
    if ([_diffOriginals objectForKey:item]) return nil;
    return [item.representedObject isKindOfClass:[UDCodeDocument class]] ? item.representedObject : nil;
}

- (nullable UDCodeEditorViewController *)selectedEditor {
    return [_diffOriginals objectForKey:_editorTabs.selectedItem] ? nil : [self _selectedEditor];
}

- (void)showURL:(NSURL *)url {
    [self _showFile:url.path];
}

- (void)openUntitledDocumentWithText:(NSString *)text languageMode:(NSString *)identifier {
    UDLanguageMode *mode = [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:identifier];
    UDCodeDocument *document = [_workspaceModel addDocumentWithText:text fileURL:nil languageMode:mode];
    [self _openTabForDocument:document];
}

- (NSArray<UDCodeEditorViewController *> *)editorsOfDocument:(UDCodeDocument *)document {
    NSMutableArray *editors = [NSMutableArray array];
    for (UDTabBarItem *item in [self _itemsForDocument:document]) {
        UDCodeEditorViewController *editor = [_diffOriginals objectForKey:item] ? nil : [self _editorOfItem:item];
        if (editor) [editors addObject:editor];
    }
    return editors;
}

/// The extensions' Editor menu items (Run Statement…), after the menu's own.
- (void)_rebuildEditorMenu {
    NSMenu *menu = [[NSApp mainMenu] itemWithTitle:@"Editor"].submenu;
    if (!menu) return;
    for (NSMenuItem *item in [menu.itemArray copy]) {
        if (item.tag == UDContributedMenuItemTag) [menu removeItem:item];
    }
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if (![extension respondsToSelector:@selector(editorMenuItemsForWorkbench:)]) continue;
        NSArray<NSMenuItem *> *items = [extension editorMenuItemsForWorkbench:self];
        if (!items.count) continue;
        NSMutableArray *section = [NSMutableArray arrayWithObject:[NSMenuItem separatorItem]];
        [section addObjectsFromArray:items];
        for (NSMenuItem *item in section) {
            item.tag = UDContributedMenuItemTag;
            [menu addItem:item];
        }
    }
}

- (IBAction)commitChanges:(nullable id)sender {
    [self showSourceControlNavigator:nil];
    [_sourceControlNavigator focusCommitMessage];
}

// MARK: The source control's host

- (void)sourceControl:(nullable id<UDSourceControl>)sourceControl didFail:(UDSourceControlResult *)result {
    if (!self.window) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"The operation didn't succeed.";
    alert.informativeText = result.message ?: @"";
    [alert beginSheetModalForWindow:self.window modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
}

/// The files the Integrate menu's "Selected Files" are: the Changes'
/// selection when it has the focus, else the project navigator's, else the tab's.
- (NSArray<NSString *> *)selectedPathsForSourceControl:(id<UDSourceControl>)sourceControl {
    if (self.window.firstResponder == _sourceControlNavigator.changesView) {
        NSMutableArray *paths = [NSMutableArray array];
        for (UDSourceControlResource *resource in _sourceControlNavigator.selectedResources) [paths addObject:resource.path];
        return paths;
    }
    if (self.window.firstResponder == _fileNavigator.outlineView) {
        NSURL *url = [_fileNavigator URLOfRow:_fileNavigator.outlineView.selectedRow];
        return url ? @[ url.path ] : @[];
    }
    UDCodeDocument *document = _editorTabs.selectedItem.representedObject;
    return [document isKindOfClass:[UDCodeDocument class]] && document.fileURL ? @[ document.fileURL.path ] : @[];
}

- (void)sourceControl:(id<UDSourceControl>)sourceControl showHistoryOfRef:(NSString *)ref title:(NSString *)title {
    [self _showHistoryOfRef:ref title:title];
}

- (void)sourceControl:(nullable id<UDSourceControl>)sourceControl openFolder:(NSURL *)folder {
    [(AppDelegate *)NSApp.delegate openFolderAtURL:folder];
}

// MARK: The project navigator's badges

- (NSString *)fileNavigator:(UDFileNavigatorViewController *)navigator badgeForURL:(NSURL *)url {
    return [_sourceControl resourceAtPath:url.path].letter;
}

- (BOOL)fileNavigator:(UDFileNavigatorViewController *)navigator folderContainsChangesAtURL:(NSURL *)url {
    return [_sourceControl folderContainsChanges:url.path];
}

// MARK: The Source Control navigator's

- (void)sourceControlNavigator:(UDSourceControlNavigatorViewController *)navigator openChange:(UDSourceControlResource *)resource {
    if (resource.deleted || ![[NSFileManager defaultManager] fileExistsAtPath:resource.path]) {
        // gone: what it was, beside nothing
        [self _openReadOnlyDiffOf:[_sourceControl codeReviewTextOfPath:resource.path] ?: @"" and:@"" path:resource.path
                            title:[NSString stringWithFormat:@"%@ (Deleted)", resource.path.lastPathComponent]];
        return;
    }
    [self _showFile:resource.path];
    if (![self _selectedDiffEditor]) [self toggleCodeReview:nil];
}

- (void)sourceControlNavigator:(UDSourceControlNavigatorViewController *)navigator revealInProjectNavigator:(NSString *)path {
    [self showFilesNavigator:nil];
    [_fileNavigator revealURL:[NSURL fileURLWithPath:path]];
}

// MARK: Change bars (VS Code's quick diff)

/// @a document's editors' change bars: against the source control's
/// original (git's index), when it has the file.
- (void)_updateQuickDiffOfDocument:(UDCodeDocument *)document {
    NSString *path = document.fileURL.path;
    if (!path) return;
    if (!_sourceControl || ![_sourceControl containsPath:path]) {
        [self _setQuickDiffOriginal:nil ofPath:path];
        return;
    }
    [_sourceControl originalTextOfPath:path target:self action:@selector(_didReadOriginalText:)];
}

- (void)_didReadOriginalText:(UDSourceControlResult *)result {
    [self _setQuickDiffOriginal:[result.value isKindOfClass:[NSString class]] ? result.value : nil ofPath:result.context];
}

- (void)_setQuickDiffOriginal:(nullable NSString *)original ofPath:(nullable NSString *)path {
    if (!path) return;
    for (UDTabBarItem *item in _editorTabs.items) {
        UDCodeDocument *document = item.representedObject;
        if (![document isKindOfClass:[UDCodeDocument class]] || ![document.fileURL.path isEqualToString:path]) continue;
        [self _editorOfItem:item].quickDiffOriginal = original;
    }
}

- (void)codeEditor:(UDCodeEditorViewController *)editor stageText:(NSString *)indexText {
    NSString *path = [self _documentOfEditor:editor].fileURL.path;
    if (path) [_sourceControl stageText:indexText ofPath:path target:nil action:NULL];
}

- (void)codeEditorShowChanges:(UDCodeEditorViewController *)editor {
    UDCodeDocument *document = [self _documentOfEditor:editor];
    if (!document.fileURL) return;
    [self _showFile:document.fileURL.path];
    if (![self _selectedDiffEditor]) [self toggleCodeReview:nil];
}

- (nullable UDCodeDocument *)_documentOfEditor:(UDCodeEditorViewController *)editor {
    for (UDTabBarItem *item in _editorTabs.items) {
        if ([self _editorOfItem:item] == editor) return item.representedObject;
    }
    return nil;
}

/// A copy's text replaced (a read-only side's: its file changed).
- (void)_replaceTextOf:(UDCodeDocument *)copy with:(NSString *)text {
    UDTextModel *model = copy.textModel;
    if ([text isEqualToString:[model getValue]]) return;
    NSInteger lines = [model getLineCount];
    [model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 1, lines, [model getLineMaxColumn:lines]) text:text] ]];
}

// MARK: The jump bar's

- (void)jumpBarController:(UDJumpBarController *)controller openURL:(NSURL *)url {
    [self _showFile:url.path];
}

// MARK: Authors (Xcode's: blame beside the text)

/// Editor > Authors (⌃⇧⌘A): who last changed the file's lines, beside them.
- (IBAction)toggleAuthors:(nullable id)sender {
    UDCodeEditorViewController *editor = [self _selectedEditor];
    NSString *path = [self _documentOfEditor:editor].fileURL.path;
    if (!editor || !path || ![_sourceControl containsPath:path] ||
        ![_sourceControl respondsToSelector:@selector(blameOfPath:target:action:)]) {
        return;
    }
    if (editor.showsAuthors) {
        editor.showsAuthors = NO;
        return;
    }
    editor.showsAuthors = YES;
    [_sourceControl blameOfPath:path target:self action:@selector(_didReadBlame:)];
}

- (void)_didReadBlame:(UDSourceControlResult *)result {
    NSArray<UDSourceControlBlameRange *> *ranges = [result.value isKindOfClass:[NSArray class]] ? result.value : @[];
    for (UDTabBarItem *item in _editorTabs.items) {
        UDCodeDocument *document = item.representedObject;
        UDCodeEditorViewController *editor = [self _editorOfItem:item];
        if (editor.showsAuthors && [document isKindOfClass:[UDCodeDocument class]] &&
            [document.fileURL.path isEqualToString:result.context]) {
            editor.blameRanges = ranges;
        }
    }
}

// MARK: History

/// @a ref's history in a tab (its own, when it has one), as Xcode shows it in
/// the editor when a branch or tag is selected.
- (void)_showHistoryOfRef:(NSString *)ref title:(NSString *)title {
    if (!_sourceControl) return;
    for (UDTabBarItem *item in _editorTabs.items) {
        if (![[_historyTabs objectForKey:item] isEqualToString:ref]) continue;
        [(UDHistoryViewController *)[_editorTabs viewControllerForItem:item] reload];
        [_editorTabs selectItem:item];
        return;
    }
    UDHistoryViewController *history = [[UDHistoryViewController alloc] initWithSourceControl:_sourceControl ref:ref];
    history.delegate = self;
    UDTabBarItem *item = [_editorTabs addItemWithTitle:[NSString stringWithFormat:@"%@ (History)", title]
                                     representedObject:nil viewController:history];
    [_historyTabs setObject:ref forKey:item];
}

/// A file a commit changed: as it was before it, beside it after.
- (void)history:(UDHistoryViewController *)history openFile:(UDSourceControlCommitFile *)file ofCommit:(UDSourceControlCommit *)commit {
    if (![_sourceControl respondsToSelector:@selector(textOfPath:atCommit:)]) return;
    NSString *root = _sourceControl.rootPath;
    NSString *path = [root stringByAppendingPathComponent:file.path];
    NSString *before = @"", *after = @"";
    if (![file.letter isEqualToString:@"A"] && commit.parents.count) {
        NSString *was = [root stringByAppendingPathComponent:file.originalPath ?: file.path];
        before = [_sourceControl textOfPath:was atCommit:commit.parents.firstObject] ?: @"";
    }
    if (![file.letter isEqualToString:@"D"]) after = [_sourceControl textOfPath:path atCommit:commit.identifier] ?: @"";
    [self _openReadOnlyDiffOf:before and:after path:path
                        title:[NSString stringWithFormat:@"%@ (%@)", file.path.lastPathComponent, commit.shortIdentifier]];
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
    if (success) [self _refreshSavedCopiesOfURL:_workspaceModel.documents.firstObject.fileURL];
    if (!success) {
        NSLog(@"[UDDocumentWindowController] File save failed; all services have been notified of the save attempt.");
    }
}

// ---------------------------------------------------------------------------
// MARK: - Debugging (Debug menu)
// ---------------------------------------------------------------------------

- (NSArray<NSString *> *)debugAdapterCommand {
    if (!_debugAdapterCommand) {
        NSString *udcode = [[NSBundle mainBundle] executablePath];
        _debugAdapterCommand = udcode ? @[ udcode, UDDemoDebugAdapterOption ] : @[];
    }
    return _debugAdapterCommand;
}

- (void)setDebugSession:(UDDebugSession *)session {
    _debugSession.delegate = nil;
    _debugSession = session;
    session.delegate = self;
    _debugBar.session = session;
    _debugNavigator.session = session;
    _debugArea.session = session;
    if (session) [self _showBottomArea:0];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UDDebugSessionDidChangeStateNotification object:nil];
    if (session) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_debugSessionDidChangeState:)
                                                     name:UDDebugSessionDidChangeStateNotification object:session];
    }
    [self _updateActivity];
}

- (IBAction)startDebugging:(nullable id)sender {
    // a project: built, then its program debugged
    if (_project) {
        if (_debugSession && _debugSession.state != UDDebugSessionStateEnded) {
            NSBeep();
            return;
        }
        [self _buildAndRun:UDAfterBuildDebug];
        return;
    }
    UDCodeDocument *document = _editorTabs.selectedItem.representedObject;
    if (!document.fileURL || (_debugSession && _debugSession.state != UDDebugSessionStateEnded)) {
        NSBeep();
        return;
    }
    // The adapter the language's bundle gives, or the demo's.
    UDLanguageMode *mode = document.languageMode;
    NSArray<NSString *> *command = mode.debugAdapterCommand;
    NSDictionary *arguments = [mode debugLaunchArgumentsForFileURL:document.fileURL];
    NSString *adapterID = mode.identifier;
    if (!command.count) {
        command = self.debugAdapterCommand;
        arguments = @{ @"program": document.fileURL.path };
        adapterID = @"udcode-demo";
    }
    UDDebugSession *session =
        [[UDDebugSession alloc] initWithAdapterCommand:command
                                  currentDirectoryPath:document.fileURL.URLByDeletingLastPathComponent.path
                                           breakpoints:_breakpoints];
    session.adapterID = adapterID;
    self.debugSession = session;
    [_debugSplit setPane:UDDebugAreaPane visible:YES];
    [self showDebugNavigator:nil];
    [session launchWithArguments:arguments];
}

/// The project's program, under its debugger (lldb-dap, else gdb's own,
/// or what the project names), debugged or (@a debugging NO) run as VS Code
/// runs without debugging: the same launch, with noDebug.
- (void)_runProgramDebugging:(BOOL)debugging {
    UDLaunchConfiguration *configuration = _pendingConfiguration;
    _pendingConfiguration = nil;
    if (configuration) {
        [self _run:configuration debugging:debugging];
        return;
    }
    NSString *program = _project.runProgram;
    if (!program) {
        // what to run: asked once, then kept with the project
        _afterSettings = debugging ? UDAfterBuildDebug : UDAfterBuildRun;
        [self showProjectSettings:nil];
        return;
    }
    // the file the build made (on Windows hello.exe for hello)
    NSString *executable = UDExecutableAtPath(program);
    if (!executable) {
        [self _tell:@"The program isn't there" detail:[NSString stringWithFormat:@"%@ wasn't made by the build.", program]];
        return;
    }
    NSArray<NSString *> *command = [UDDebugger adapterCommandForDebugger:_project.debugger];
    if (!command) {
        [self _tell:@"No debugger" detail:[NSString stringWithFormat:@"None of the debuggers UDCode knows (%@) was found. "
                                           @"Install one, or name a debug adapter in the project's settings (\"debugger\").",
                                           [self _debuggerNames]]];
        return;
    }
    Class debugger = [UDDebugger classOfAdapterCommand:command] ?: [UDDebugger class];
    NSMutableDictionary *arguments = [[debugger launchArgumentsForProgram:executable arguments:_project.runArguments
                                                                directory:_project.runDirectory
                                                              environment:_project.buildEnvironment] mutableCopy];
    if (!debugging) arguments[@"noDebug"] = @YES;
    // run alone: no breakpoints for it to stop at (not every adapter honours noDebug)
    UDDebugSession *session = [[UDDebugSession alloc] initWithAdapterCommand:command
                                                        currentDirectoryPath:_project.folderURL.path
                                                                 breakpoints:debugging ? _breakpoints : [[UDBreakpointStore alloc] init]];
    session.adapterID = debugger != [UDDebugger class] ? [debugger name] : @"udcode";
    self.debugSession = session;
    [_debugSplit setPane:UDDebugAreaPane visible:YES];
    if (debugging) [self showDebugNavigator:nil];
    [session launchWithArguments:arguments];
}

- (IBAction)showProjectSettings:(nullable id)sender {
    if (!_project || _projectSettings) {
        NSBeep();
        return;
    }
    _projectSettings = [[UDProjectSettingsController alloc] init];
    [_projectSettings beginSheetForWindow:self.window project:_project target:self action:@selector(_projectSettingsDidEnd:)];
}

/// Saved: what was waiting on it (a Run) goes on.
- (void)_projectSettingsDidEnd:(UDProjectSettingsController *)sheet {
    NSInteger then = _afterSettings;
    _afterSettings = UDAfterBuildNothing;
    _projectSettings = nil;
    if (sheet.returnCode == NSModalResponseOK && then != UDAfterBuildNothing && _project.runProgram) {
        [self _runProgramDebugging:then == UDAfterBuildDebug];
    }
}

/// launch.json's configuration: its debugger (its type's, or the one it
/// names), its program, arguments, folder and environment; an attach's process.
- (void)_run:(UDLaunchConfiguration *)configuration debugging:(BOOL)debugging {
    BOOL attach = [configuration.request isEqualToString:@"attach"];
    if (!attach && !configuration.program) {
        [self _tell:[NSString stringWithFormat:@"“%@” runs nothing", configuration.name]
             detail:@"Its launch configuration names no program."];
        return;
    }
    // its debugger's adapter, from where it says (miDebuggerPath), or as found
    Class named = configuration.debugger ? [UDDebugger classNamed:configuration.debugger] : Nil;
    NSArray<NSString *> *command = configuration.debuggerPath && named
        ? [named adapterCommandWithExecutable:configuration.debuggerPath]
        : [UDDebugger adapterCommandForDebugger:configuration.debugger ?: _project.debugger];
    if (!command) {
        [self _tell:@"No debugger" detail:[NSString stringWithFormat:@"“%@” wants %@, which wasn't found.", configuration.name,
                                           configuration.debugger ?: [self _debuggerNames]]];
        return;
    }
    Class debugger = [UDDebugger classOfAdapterCommand:command] ?: [UDDebugger class];
    NSMutableDictionary *environment = [_project.buildEnvironment mutableCopy];
    [environment addEntriesFromDictionary:configuration.environment];
    NSMutableDictionary *arguments = nil;
    if (attach) {
        arguments = configuration.waitFor ? [@{ @"waitFor": @YES } mutableCopy]
                                          : [@{ @"pid": @(configuration.processID) } mutableCopy];
        if (configuration.program) arguments[@"program"] = configuration.program;
    } else {
        arguments = [[debugger launchArgumentsForProgram:configuration.program arguments:configuration.arguments
                                               directory:configuration.directory ?: _project.folderURL.path
                                             environment:environment] mutableCopy];
    }
    if (!debugging) arguments[@"noDebug"] = @YES;
    UDDebugSession *session = [[UDDebugSession alloc] initWithAdapterCommand:command
                                                        currentDirectoryPath:_project.folderURL.path
                                                                 breakpoints:debugging ? _breakpoints : [[UDBreakpointStore alloc] init]];
    session.adapterID = debugger != [UDDebugger class] ? [debugger name] : configuration.type;
    self.debugSession = session;
    [_debugSplit setPane:UDDebugAreaPane visible:YES];
    if (debugging) [self showDebugNavigator:nil];
    if (attach) [session attachWithArguments:arguments];
    else [session launchWithArguments:arguments];
}

/// The debuggers known, as the settings sheet names them ("LLDB or GDB").
- (NSString *)_debuggerNames {
    NSArray *names = [[UDDebugger classes] valueForKey:@"displayName"];
    return names.count ? [names componentsJoinedByString:@" or "] : @"none";
}

/// A sheet saying what went wrong.
- (void)_tell:(NSString *)message detail:(NSString *)detail {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = detail;
    [alert beginSheetModalForWindow:self.window modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
}

- (IBAction)stopDebugging:(nullable id)sender {
    if (_buildRunner.running) {
        _afterBuild = UDAfterBuildNothing;
        [_buildRunner stop];
        return;
    }
    [_debugSession stop];
}
- (IBAction)debugContinueOrPause:(nullable id)sender { [_debugBar continueOrPause:sender]; }
- (IBAction)debugStepOver:(nullable id)sender      { [_debugBar stepOver:sender]; }
- (IBAction)debugStepInto:(nullable id)sender      { [_debugBar stepInto:sender]; }
- (IBAction)debugStepOut:(nullable id)sender       { [_debugBar stepOut:sender]; }
- (IBAction)debugStepBack:(nullable id)sender      { [_debugBar stepBack:sender]; }

/// Run to Cursor and Jump to Cursor, when the text is not first responder:
/// the selected editor's.
- (IBAction)runToCursor:(nullable id)sender  { [[self _selectedEditor] runToCursor:sender]; }
- (IBAction)jumpToCursor:(nullable id)sender { [[self _selectedEditor] jumpToCursor:sender]; }

/// Toggle Breakpoint (⌘\): the selected editor's, at its caret.
- (IBAction)toggleBreakpoint:(nullable id)sender {
    [[self _selectedEditor] toggleBreakpoint:sender];
}

/// The selected frame's file: its tab, opened when it has none, at the line.
- (void)debugSession:(UDDebugSession *)session showFile:(NSString *)path line:(NSInteger)line {
    [self _showFile:path];
    [[self _selectedEditor] revealLine:line];
}

/// A breakpoint chosen in the breakpoint navigator: its line, selected.
- (void)breakpointNavigator:(UDBreakpointNavigatorViewController *)navigator showBreakpoint:(UDBreakpoint *)breakpoint {
    [self _showFile:breakpoint.path];
    [[self _selectedEditor] selectLine:breakpoint.line];
    [self.window makeFirstResponder:[self _selectedEditor].textView];
}

/// Its editor's breakpoint box.
- (void)breakpointNavigator:(UDBreakpointNavigatorViewController *)navigator editBreakpoint:(UDBreakpoint *)breakpoint {
    [self _showFile:breakpoint.path];
    [[self _selectedEditor] editBreakpointAtLine:breakpoint.line];
}

/// @a path's tab selected, opened when it has none.
- (void)_showFile:(NSString *)path {
    NSString *wanted = [path stringByStandardizingPath];
    UDTabBarItem *item = nil;
    for (UDCodeDocument *document in _workspaceModel.documents) {
        if (![[document.fileURL.path stringByStandardizingPath] isEqualToString:wanted]) continue;
        item = [self _itemsForDocument:document].firstObject;
        break;
    }
    if (item) {
        if (item != _editorTabs.selectedItem) [_editorTabs selectItem:item];
    } else {
        [self openURLInNewTab:[NSURL fileURLWithPath:wanted]];
    }
}

- (void)close {
    // the popups, children of the window, go first
    [_signatureHelp close];
    [_hover close];
    [_issuePopup close];
    [_rename cancel];
    [_terminal stop];
    [_debugSession stop];
    [_fileWatcher stop];
    // the project's language servers go with its window
    for (LSPClient *client in _projectServers.allValues) [client terminate];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:nil];
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
