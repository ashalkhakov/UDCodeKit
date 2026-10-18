#import "UDDocumentWindowController.h"
#import "UDDocument.h"
#import <UDCodeKit/UDErrorsViewController.h>
#import "UDWorkspaceModel.h"
#import "UDDemoDebugAdapter.h"
#import <objc/runtime.h>
#import <UDCodeKit/UDCodeKit.h>
#ifdef __APPLE__
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

// The panes of the window's split view (UDDocumentWindowController.xib).
static const NSInteger UDNavigatorPane = 0;
static const NSInteger UDInspectorPane = 2;
// The editors' split: the debug area below them.
static const NSInteger UDDebugAreaPane = 1;
// The navigator's segments.
static const NSInteger UDFindNavigatorSegment = 1;
static const NSInteger UDIssuesNavigatorSegment = 2;
static const NSInteger UDDebugNavigatorSegment = 3;
static const NSInteger UDBreakpointNavigatorSegment = 4;
static const NSInteger UDBuildNavigatorSegment = 5;
// What follows a build.
static const NSInteger UDAfterBuildNothing = 0;
static const NSInteger UDAfterBuildRun = 1;
static const NSInteger UDAfterBuildDebug = 2;

// ---------------------------------------------------------------------------
// MARK: - UDDocumentWindowController  (private extension)
// ---------------------------------------------------------------------------

@interface UDDocumentWindowController () <UDDiagnosticTextViewDelegate, UDErrorsViewControllerDelegate,
                                          UDEditorTabsControllerDelegate, UDDebugSessionDelegate,
                                          UDBreakpointNavigatorDelegate, UDFileNavigatorDelegate, UDBuildRunnerDelegate,
                                          UDFileWatcherDelegate, UDSearchResultsDelegate, UDWorkspaceEditDocuments, UDOpenQuicklyDelegate,
                                          NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>

// The window's layout, all in the XIB.
@property (nonatomic, strong) IBOutlet UDPaneSplitController  *paneSplit;
@property (nonatomic, strong) IBOutlet UDEditorTabsController *editorTabs;
@property (nonatomic, weak) IBOutlet NSSegmentedControl *navigatorControl;
@property (nonatomic, weak) IBOutlet NSTabView          *navigatorTabView;
@property (nonatomic, weak) IBOutlet NSTableView        *filesTable;
@property (nonatomic, weak) IBOutlet NSView             *projectHost;
@property (nonatomic, weak) IBOutlet NSView             *buildLogHost;
@property (nonatomic, weak) IBOutlet NSView             *findHost;
@property (nonatomic, weak) IBOutlet NSPopUpButton      *schemePopUp;
@property (nonatomic, weak) IBOutlet NSTextField        *activityLabel;
@property (nonatomic, strong, readwrite) UDSearchResultsViewController *searchResults;
@property (nonatomic, strong, readwrite, nullable) UDOpenQuicklyController *openQuickly;
@property (nonatomic, strong, readwrite, nullable) UDTextPromptController *renamePrompt;
@property (nonatomic, weak, nullable) UDTextModel *formattingModel;
@property (nonatomic, readwrite, copy, nullable) NSArray<NSDictionary *> *codeActions;
@property (nonatomic, weak, nullable) UDLSPCoordinator *codeActionCoordinator;
@property (nonatomic, strong, readwrite, nullable) NSMenu *codeActionsMenu;
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
@property (nonatomic, strong, readwrite, nullable) UDFileNavigatorViewController *fileNavigator;
/// The project's language servers, one per command, which its documents share
/// (one clangd for the project, as VS Code has it).
@property (nonatomic, strong) NSMutableDictionary<NSArray<NSString *> *, LSPClient *> *projectServers;
@property (nonatomic, weak) IBOutlet NSView             *issuesHost;
@property (nonatomic, weak) IBOutlet NSView             *debugNavigatorHost;
@property (nonatomic, weak) IBOutlet NSView             *breakpointNavigatorHost;
@property (nonatomic, strong) IBOutlet UDPaneSplitController *debugSplit;
@property (nonatomic, weak) IBOutlet NSView             *debugBarHost;
@property (nonatomic, weak) IBOutlet NSView             *debugAreaHost;
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
        _buildRunner = [[UDBuildRunner alloc] initWithProject:_project];
        _fileWatcher = [[UDFileWatcher alloc] initWithFolderURL:_project.folderURL ignoredNames:nil];
        _fileWatcher.delegate = self;
    }
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
        if ([path.lastPathComponent hasPrefix:@"clangd"]) {
            client.initializationOptions = @{ @"fallbackFlags": _project.fallbackCompileFlags };
        }
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
    } else {
        [_schemePopUp addItemWithTitle:_project ? _project.name : self.window.title];
    }
    _schemePopUp.enabled = configurations.count > 1;
    _schemePopUp.target = self;
    _schemePopUp.action = @selector(selectLaunchConfiguration:);
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
    if (_buildRunner.running) {
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
    if (_buildRunner.command && !_buildRunner.running) {
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
    _buildLog.runner = _buildRunner;
    [self showBuildNavigator:nil];
    [self _showBuildIssues];
    [self _updateActivity];
}

- (void)buildRunner:(UDBuildRunner *)runner didOutput:(NSString *)text {
    [self _showBuildIssues];
}

- (void)buildRunnerDidFinish:(UDBuildRunner *)runner {
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
    [self _updateSchemePopUp];      // launch.json may have changed
    NSMutableSet<NSString *> *changed = [NSMutableSet set];
    for (NSString *path in paths) [changed addObject:path.stringByStandardizingPath];
    for (UDCodeDocument *document in _workspaceModel.documents) {
        if (document.fileURL && [changed containsObject:document.fileURL.path.stringByStandardizingPath]) {
            [document reloadFromFileIfUnmodified];
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

/// The word at the caret: what a search is for.
- (NSString *)_wordAtCaret {
    NSTextView *textView = [self _selectedEditor].textView;
    if (!textView) return @"";
    NSRange selected = textView.selectedRange;
    if (selected.length) return [textView.string substringWithRange:selected];
    NSRange word = [textView selectionRangeForProposedRange:NSMakeRange(selected.location, 0) granularity:NSSelectByWord];
    return word.length && NSMaxRange(word) <= textView.string.length ? [textView.string substringWithRange:word] : @"";
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

/// Editor > Rename Symbol (⌃⌘E): its new name asked for, then each place it is.
- (IBAction)renameSymbol:(nullable id)sender {
    UDCodeEditorViewController *editor = [self _selectedEditor];
    UDLSPCoordinator *lsp = [self _activeSession].lspCoordinator;
    if (!editor || !lsp.ready) {
        NSBeep();
        return;
    }
    NSRange selected = editor.textView.selectedRange;
    NSString *word = [self _wordAtCaret];
    if (!word.length) {
        NSBeep();
        return;
    }
    if (!_renamePrompt) _renamePrompt = [[UDTextPromptController alloc] init];
    _renamePrompt.context = @{ @"coordinator": lsp, @"index": @(selected.location) };
    [_renamePrompt beginSheetForWindow:self.window message:[NSString stringWithFormat:@"Rename “%@” to:", word]
                                  text:word target:self action:@selector(_renamePromptDidEnd:)];
}

- (void)_renamePromptDidEnd:(UDTextPromptController *)prompt {
    UDLSPCoordinator *lsp = prompt.context[@"coordinator"];
    NSUInteger index = [prompt.context[@"index"] unsignedIntegerValue];
    prompt.context = nil;
    NSString *name = [prompt.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (prompt.returnCode != NSModalResponseOK || !name.length) return;
    if (![lsp request:@"textDocument/rename" atIndex:index extra:@{ @"newName": name }
               target:self action:@selector(_didRename:)]) {
        NSBeep();
    }
}

- (void)_didRename:(LSPResponse *)response {
    if (response.error) {
        [self _tell:@"The symbol could not be renamed." detail:response.error.localizedDescription];
        return;
    }
    if (![response.result isKindOfClass:[NSDictionary class]] || ![self _applyWorkspaceEdit:response.result]) NSBeep();
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

/// Editor > Fix Issue at Cursor (⌃⌥⌘F): the server's code actions for the
/// caret's diagnostics (its fixes first), in a menu at the caret.
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
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Fixes"];
    [actions enumerateObjectsUsingBlock:^(NSDictionary *action, NSUInteger i, BOOL *stop) {
        NSMenuItem *item = [menu addItemWithTitle:action[@"title"] action:@selector(performCodeAction:) keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)i;
    }];
    // below the caret's line, at the caret
    NSLayoutManager *layout = textView.layoutManager;
    NSUInteger caret = MIN(textView.selectedRange.location, textView.string.length);
    NSRange glyphs = [layout glyphRangeForCharacterRange:NSMakeRange(caret, 0) actualCharacterRange:NULL];
    NSRect line = [layout lineFragmentRectForGlyphAtIndex:MIN(glyphs.location, MAX(layout.numberOfGlyphs, 1) - 1) effectiveRange:NULL];
    NSPoint x = [layout locationForGlyphAtIndex:MIN(glyphs.location, MAX(layout.numberOfGlyphs, 1) - 1)];
    NSPoint origin = textView.textContainerOrigin;
    NSPoint at = NSMakePoint(origin.x + line.origin.x + x.x, origin.y + NSMaxY(line));
    _codeActionsMenu = menu;
    [menu popUpMenuPositioningItem:nil atLocation:at inView:textView];
}

/// One of the code actions chosen: its edit, then its command (which may
/// send its own edit back, workspace/applyEdit).
- (IBAction)performCodeAction:(nullable id)sender {
    NSInteger index = [sender respondsToSelector:@selector(tag)] ? [sender tag] : 0;
    if (index < 0 || (NSUInteger)index >= _codeActions.count) return;
    [self _performCodeAction:_codeActions[(NSUInteger)index]];
}

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
    _debugBarHost.frame = NSMakeRect(0, NSMaxY(bounds) - bar, NSWidth(bounds), bar);
    _debugAreaHost.frame = NSMakeRect(0, 0, NSWidth(bounds), NSHeight(bounds) - bar);
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

- (IBAction)showFindNavigator:(nullable id)sender {
    [_paneSplit setPane:UDNavigatorPane visible:YES];
    _navigatorControl.selectedSegment = UDFindNavigatorSegment;
    [self navigatorChanged:nil];
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
    if (document.fileURL) [editor showBreakpointsOfStore:_breakpoints forFile:document.fileURL.path];

    if (first) {
        [session activateWithTheme:_currentTheme];
        if (![self _startProjectLanguageServerOf:session document:document]) [session startLanguageServer];
        session.lspCoordinator.editDocuments = self;
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
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:program]) {
        [self _tell:@"The program isn't there" detail:[NSString stringWithFormat:@"%@ wasn't made by the build.", program]];
        return;
    }
    NSArray<NSString *> *command = [UDToolLocator debugAdapterCommandForDebugger:_project.debugger];
    if (!command) {
        [self _tell:@"No debugger" detail:@"Neither lldb-dap nor gdb (14 or later) was found. Install LLVM's lldb, or gdb, "
                                          @"or name a debug adapter in the project's settings (\"debugger\")."];
        return;
    }
    NSString *kind = [UDToolLocator kindOfDebugAdapterCommand:command];
    NSMutableDictionary *arguments = [[UDToolLocator launchArgumentsForDebugger:kind program:program
                                                                      arguments:_project.runArguments
                                                                      directory:_project.runDirectory
                                                                    environment:_project.buildEnvironment] mutableCopy];
    if (!debugging) arguments[@"noDebug"] = @YES;
    // run alone: no breakpoints for it to stop at (not every adapter honours noDebug)
    UDDebugSession *session = [[UDDebugSession alloc] initWithAdapterCommand:command
                                                        currentDirectoryPath:_project.folderURL.path
                                                                 breakpoints:debugging ? _breakpoints : [[UDBreakpointStore alloc] init]];
    session.adapterID = kind ?: @"udcode";
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
    NSArray<NSString *> *command = nil;
    if (configuration.debuggerPath && [configuration.debugger isEqualToString:UDDebuggerGDB]) {
        command = @[ configuration.debuggerPath, @"-i", @"dap" ];
    } else {
        command = [UDToolLocator debugAdapterCommandForDebugger:configuration.debugger ?: _project.debugger];
    }
    if (!command) {
        [self _tell:@"No debugger" detail:[NSString stringWithFormat:@"“%@” wants %@, which wasn't found.", configuration.name,
                                           configuration.debugger ?: @"lldb-dap or gdb"]];
        return;
    }
    NSString *kind = [UDToolLocator kindOfDebugAdapterCommand:command];
    NSMutableDictionary *environment = [_project.buildEnvironment mutableCopy];
    [environment addEntriesFromDictionary:configuration.environment];
    NSMutableDictionary *arguments = nil;
    if (attach) {
        arguments = [@{ @"pid": @(configuration.processID) } mutableCopy];
        if (configuration.program) arguments[@"program"] = configuration.program;
    } else {
        arguments = [[UDToolLocator launchArgumentsForDebugger:kind program:configuration.program
                                                     arguments:configuration.arguments
                                                     directory:configuration.directory ?: _project.folderURL.path
                                                   environment:environment] mutableCopy];
    }
    if (!debugging) arguments[@"noDebug"] = @YES;
    UDDebugSession *session = [[UDDebugSession alloc] initWithAdapterCommand:command
                                                        currentDirectoryPath:_project.folderURL.path
                                                                 breakpoints:debugging ? _breakpoints : [[UDBreakpointStore alloc] init]];
    session.adapterID = kind ?: configuration.type;
    self.debugSession = session;
    [_debugSplit setPane:UDDebugAreaPane visible:YES];
    if (debugging) [self showDebugNavigator:nil];
    if (attach) [session attachWithArguments:arguments];
    else [session launchWithArguments:arguments];
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
