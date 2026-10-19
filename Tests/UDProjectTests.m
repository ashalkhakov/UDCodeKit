//
//  UDProjectTests.m
//  UDCodeTests
//
//  A folder as a project: what its settings say (and what is guessed when
//  they say nothing, for this system), one folder for both systems; the tools
//  found; and File > Open Folder…, its files in the navigator, a file chosen
//  there opened in a tab.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "AppDelegate.h"
#import "UDDocument.h"
#import "UDDocumentWindowController.h"

@interface UDDocumentWindowController (ProjectTesting)
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
@property (nonatomic, weak) NSTableView *filesTable;
@property (nonatomic, weak) NSView *projectHost;
- (void)searchResults:(UDSearchResultsViewController *)controller showResult:(UDSearchResult *)result;
- (void)textViewDidChangeSelection:(NSNotification *)note;
@property (nonatomic, weak) NSPopUpButton *schemePopUp;
@end

@interface UDProjectTests : UDCodeTestCase
@property (nonatomic, copy) NSString *folder;
/// The window whose settings sheet -answerSettingsSheet answers, and what it saw.
@property (nonatomic, weak) UDDocumentWindowController *sheetController;
@property (nonatomic, copy) NSString *sheetPlaceholder;
@property (nonatomic, copy) NSString *sheetBuild;
@end

@implementation UDProjectTests

- (void)setUp {
    [super setUp];
    _folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:[_folder stringByAppendingPathComponent:@"Sources/Model"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    // as the project names it: its real path (macOS's /var is /private/var)
    _folder = [[UDProject alloc] initWithFolderURL:[NSURL fileURLWithPath:_folder]].folderURL.path;
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:_folder error:NULL];
    [super tearDown];
}

- (void)write:(NSString *)text to:(NSString *)name {
    NSString *path = [_folder stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (UDProject *)project {
    return [[UDProject alloc] initWithFolderURL:[NSURL fileURLWithPath:_folder]];
}

// ---------------------------------------------------------------------------

- (void)testAFolderSaysNothingAndItsBuildSystemIsGuessed {
    XCTAssertNil(self.project.buildCommand, @"an empty folder builds nothing");
    [self write:@"all:\n\tcc -o hello hello.c\n" to:@"Makefile"];
    XCTAssertEqualObjects(self.project.buildCommand, @"make");
    XCTAssertEqualObjects(self.project.cleanCommand, @"make clean");
    XCTAssertNil(self.project.runProgram, @"a Makefile doesn't say what it makes");

    // a GNUstep project: on GNUstep, make, and its application is run
    [self write:@"include $(GNUSTEP_MAKEFILES)/common.make\nAPP_NAME_SUFFIX = x\nAPP_NAME = Hello\n" to:@"GNUmakefile"];
#ifdef GNUSTEP
    XCTAssertEqual(self.project.buildSystem, UDProjectBuildSystemGNUstepMake);
    XCTAssertEqualObjects(self.project.runProgram, [_folder stringByAppendingPathComponent:@"Hello.app/Hello"],
                          @"the application's executable");
    XCTAssertNotNil(self.project.buildEnvironment[@"GNUSTEP_MAKEFILES"], @"GNUstep's environment, as GNUstep.sh has it");
#else
    XCTAssertEqual(self.project.buildSystem, UDProjectBuildSystemMake, @"a GNUmakefile is GNUstep's: not on macOS");
    [self write:@"all:\n" to:@"Makefile.apple"];
    XCTAssertEqualObjects(self.project.buildCommand, @"make -f Makefile.apple", @"on macOS, Makefile.apple");
#endif
}

- (void)testOneFolderForBothSystems {
    [self write:@"all:\n" to:@"Makefile"];
    [self write:@"{ \"build\": \"make all\", \"run\": { \"program\": \"bin/hello\", \"arguments\": \"-v \\\"two words\\\"\" },"
                @"  \"macos\":   { \"build\": \"make -f Makefile.apple\", \"run\": { \"program\": \"build/hello\" } },"
                @"  \"gnustep\": { \"build\": \"make messages=yes\", \"debugger\": \"gdb\" } }"
             to:@".udcode/settings.json"];
    UDProject *project = self.project;
#ifdef GNUSTEP
    XCTAssertEqualObjects(project.buildCommand, @"make messages=yes", @"GNUstep's section");
    XCTAssertEqualObjects(project.runProgram, [_folder stringByAppendingPathComponent:@"bin/hello"]);
    XCTAssertEqualObjects(project.debugger, @"gdb");
#else
    XCTAssertEqualObjects(project.buildCommand, @"make -f Makefile.apple", @"macOS's section");
    XCTAssertEqualObjects(project.runProgram, [_folder stringByAppendingPathComponent:@"build/hello"], @"run, key by key");
    XCTAssertNil(project.debugger);
#endif
    XCTAssertEqualObjects(project.runArguments, (@[ @"-v", @"two words" ]), @"run's other keys kept");
    XCTAssertEqualObjects(project.cleanCommand, @"make clean", @"what the folder doesn't say, guessed");
    XCTAssertEqualObjects(project.runDirectory, _folder);

    // written back as set
    NSMutableDictionary *settings = [project.settings mutableCopy];
    settings[@"languageServers"] = @{ @"c": @"clangd --background-index" };
    XCTAssertTrue([project setSettings:settings error:NULL]);
    XCTAssertEqualObjects([self.project languageServerCommandForIdentifier:@"c"], (@[ @"clangd", @"--background-index" ]));
}

- (void)testTheDebuggersAreAskedAsEachTakesIt {
    NSDictionary *lldb = [UDToolLocator launchArgumentsForDebugger:UDDebuggerLLDB program:@"/p" arguments:@[ @"a" ]
                                                         directory:@"/d" environment:@{ @"K": @"v" }];
    XCTAssertEqualObjects(lldb[@"env"], @[ @"K=v" ], @"lldb-dap: NAME=value");
    NSDictionary *gdb = [UDToolLocator launchArgumentsForDebugger:UDDebuggerGDB program:@"/p" arguments:@[ @"a" ]
                                                        directory:@"/d" environment:@{ @"K": @"v" }];
    XCTAssertEqualObjects(gdb[@"env"], @{ @"K": @"v" });
    XCTAssertEqualObjects(gdb[@"program"], @"/p");
    XCTAssertEqualObjects(gdb[@"args"], @[ @"a" ]);
    XCTAssertEqualObjects(gdb[@"cwd"], @"/d");
    XCTAssertEqualObjects([UDToolLocator kindOfDebugAdapterCommand:@[ @"/usr/bin/lldb-dap-18" ]], UDDebuggerLLDB);
    XCTAssertEqualObjects([UDToolLocator kindOfDebugAdapterCommand:(@[ @"/usr/bin/gdb", @"-i", @"dap" ])], UDDebuggerGDB);
    XCTAssertEqualObjects([UDToolLocator debugAdapterCommandForDebugger:@[ @"my-adapter" ]], @[ @"my-adapter" ],
                          @"an adapter the project names, as it is");
    XCTAssertNotNil([UDToolLocator pathOfTool:@"sh"], @"found on PATH");
}

- (void)testOpenFolderShowsItsFilesAndOpensOneInATab {
    [self write:@"int main(void) { return 0; }\n" to:@"main.c"];
    [self write:@"{}\n" to:@"Sources/Model/model.json"];
    [self write:@"x" to:@".hidden"];
    [[NSFileManager defaultManager] createDirectoryAtPath:[_folder stringByAppendingPathComponent:@".git"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];

    AppDelegate *delegate = [[AppDelegate alloc] init];
    UDWorkspace *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    XCTAssertNotNil(workspace.project);
    UDDocumentWindowController *controller = workspace.windowControllers.firstObject;
    XCTAssertNotNil(controller.fileNavigator, @"the project's files in the navigator");
    XCTAssertFalse([controller.projectHost isHidden]);
    XCTAssertTrue([controller.filesTable.enclosingScrollView isHidden], @"instead of the open files");
    XCTAssertEqualObjects(controller.window.title, _folder.lastPathComponent);
    XCTAssertEqual(controller.editorTabs.items.count, 0u, @"no untitled tab in a project");

    NSOutlineView *outline = controller.fileNavigator.outlineView;
    NSMutableArray *names = [NSMutableArray array];
    for (NSInteger row = 0; row < outline.numberOfRows; row++) {
        [names addObject:[controller.fileNavigator URLOfRow:row].lastPathComponent];
    }
    XCTAssertEqualObjects(names, (@[ @"Sources", @"main.c" ]), @"folders first; hidden files and .git left out");

    // a file deep in it, revealed, and chosen: its tab
    NSURL *model = [NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"Sources/Model/model.json"]];
    [controller.fileNavigator revealURL:model];
    XCTAssertEqualObjects([controller.fileNavigator URLOfRow:outline.selectedRow].path, model.path);
    XCTAssertEqual(controller.editorTabs.items.count, 1u, @"a file selected is opened, as VS Code's Explorer does");
    UDCodeDocument *opened = controller.editorTabs.selectedItem.representedObject;
    XCTAssertEqualObjects(opened.fileURL.lastPathComponent, @"model.json");

    // a new file, listed after a reload, what was expanded kept so
    [self write:@"[]\n" to:@"Sources/Model/more.json"];
    [controller.fileNavigator reload];
    BOOL listed = NO;
    for (NSInteger row = 0; row < outline.numberOfRows; row++) {
        listed = listed || [[controller.fileNavigator URLOfRow:row].lastPathComponent isEqualToString:@"more.json"];
    }
    XCTAssertTrue(listed, @"Sources/Model still expanded, with the new file in it");

    // the same folder again: the window it has
    XCTAssertEqual([delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]], workspace);
    [controller close];
    [workspace close];
}

/// The diagnostics' messages of @a document.
- (NSString *)messagesOf:(UDCodeDocument *)document {
    return [[document.diagnosticStore.allDiagnostics valueForKey:@"message"] componentsJoinedByString:@" | "];
}

/// clangd, the existing language server, for the project's C and
/// Objective-C: one process for the project, its errors in the editor, a
/// GNUstep or Cocoa header found without compile commands (its fallback flags).
- (void)testClangdIsTheProjectsLanguageServer {
    if (![UDToolLocator clangdPath]) {
        NSLog(@"UDProjectTests: no clangd here; its case checks nothing");
        return;
    }
    [self write:@"int main(void) {\n    return undefined_name;\n}\n" to:@"main.c"];
    [self write:@"#import <Foundation/Foundation.h>\n\nint twice(int n) {\n    NSString *s = @\"x\";\n    return n * 2 + (int)s.length + undefined_in_m;\n}\n"
             to:@"Sources/twice.m"];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    UDWorkspace *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    UDDocumentWindowController *controller = workspace.windowControllers.firstObject;

    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"main.c"]]];
    UDCodeDocument *c = controller.editorTabs.selectedItem.representedObject;
    UDRunUntil([[self messagesOf:c] containsString:@"undefined_name"], 30);
    XCTAssertTrue([[self messagesOf:c] containsString:@"undefined_name"], @"clangd's error: %@", [self messagesOf:c]);

    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"Sources/twice.m"]]];
    UDCodeDocument *m = controller.editorTabs.selectedItem.representedObject;
    // its own error said: clangd has parsed it, with Foundation found
    UDRunUntil([[self messagesOf:m] containsString:@"undefined_in_m"], 30);
    XCTAssertTrue([[self messagesOf:m] containsString:@"undefined_in_m"], @"clangd's error: %@", [self messagesOf:m]);
    XCTAssertFalse([[self messagesOf:m] containsString:@"not found"], @"Foundation found: %@", [self messagesOf:m]);
    XCTAssertEqual([[controller valueForKey:@"projectServers"] count], 1u, @"one clangd for the project");

    [controller close];
    [workspace close];
}

// ---------------------------------------------------------------------------
// MARK: - Building, running, debugging
// ---------------------------------------------------------------------------

/// A C project make builds: hello.c, its program "hello".
- (void)writeCProjectWith:(NSString *)source {
    [self write:@"hello: hello.c\n\tcc -g -O0 -o hello hello.c\n\nclean:\n\trm -f hello\n" to:@"Makefile"];
    [self write:source to:@"hello.c"];
    NSString *debugger = NSProcessInfo.processInfo.environment[@"UD_TEST_DEBUGGER"];
    // a debugger by name ("gdb", "lldb"), or an adapter's path
    NSString *named = !debugger.length ? @""
                    : [@[ @"gdb", @"lldb" ] containsObject:debugger] ? [NSString stringWithFormat:@", \"debugger\": \"%@\"", debugger]
                    : [NSString stringWithFormat:@", \"debugger\": [\"%@\"]", debugger];
    [self write:[NSString stringWithFormat:@"{ \"run\": { \"program\": \"hello\", \"arguments\": \"one \\\"two words\\\"\" }%@ }", named]
             to:@".udcode/settings.json"];
}

- (UDDocumentWindowController *)openProject:(UDWorkspace * __strong *)workspace {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    UDDocumentWindowController *controller = (*workspace).windowControllers.firstObject;
    [controller.breakpoints removeAllBreakpoints];
    return controller;
}

- (void)testABuildsErrorsAreIssuesOfTheirFiles {
    NSString *path = nil;
    UDDiagnosticItem *item = [UDBuildRunner diagnosticOfLine:@"src/a.c:12:5: error: use of undeclared identifier 'x'"
                                                    inFolder:@"/p" path:&path];
    XCTAssertEqualObjects(path, @"/p/src/a.c");
    XCTAssertEqual(item.line, 12);
    XCTAssertEqual(item.column, 4);
    XCTAssertEqual(item.severity, UDDiagnosticSeverityError);
    XCTAssertEqualObjects(item.message, @"use of undeclared identifier 'x'");
    XCTAssertEqual([UDBuildRunner diagnosticOfLine:@"b.m:3: warning: unused" inFolder:@"/p" path:&path].severity,
                   UDDiagnosticSeverityWarning);
    XCTAssertNil([UDBuildRunner diagnosticOfLine:@"make: *** [all] Error 1" inFolder:@"/p" path:&path]);

    [self writeCProjectWith:@"int main(void) {\n    return undefined_here;\n}\n"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [controller build:nil];
    XCTAssertTrue(controller.buildRunner.running || controller.buildRunner.command != nil);
    UDRunUntil(!controller.buildRunner.running, 60);
    XCTAssertFalse(controller.buildRunner.succeeded, @"%@", controller.buildRunner.output);
    XCTAssertEqual(controller.buildRunner.errorCount, 1u, @"%@", controller.buildRunner.output);
    UDDiagnosticStore *store = controller.buildRunner.diagnostics[[_folder stringByAppendingPathComponent:@"hello.c"].stringByStandardizingPath];
    XCTAssertEqual(store.allDiagnostics.firstObject.line, 2, @"the error, in hello.c's store: %@", controller.buildRunner.diagnostics);

    // opened, the file has it as its own
    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"hello.c"]]];
    [controller build:nil];
    UDRunUntil(!controller.buildRunner.running, 60);
    UDCodeDocument *hello = controller.editorTabs.selectedItem.representedObject;
    BOOL built = NO;
    for (UDDiagnosticItem *issue in hello.diagnosticStore.allDiagnostics) built = built || [issue.source isEqual:UDDiagnosticSourceBuild];
    XCTAssertTrue(built, @"the build's error in the editor's store: %@", hello.diagnosticStore.allDiagnostics);
    [controller close];
    [workspace close];
}

- (void)testRunBuildsThenDebugsTheProgramStoppingAtABreakpoint {
    if (![UDToolLocator debugAdapterCommandForDebugger:nil]) {
        NSLog(@"UDProjectTests: neither lldb-dap nor gdb here; the debugging case checks nothing");
        return;
    }
    [self writeCProjectWith:@"#include <stdio.h>\n"
                            @"int main(int argc, char **argv) {\n"
                            @"    int count = argc;\n"
                            @"    printf(\"hello %d\\n\", count);\n"
                            @"    return 0;\n"
                            @"}\n"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    NSString *hello = [_folder stringByAppendingPathComponent:@"hello.c"];
    [controller.breakpoints addBreakpointAtLine:4 inFile:hello];

    [controller startDebugging:nil];
    UDRunUntil(controller.debugSession.state == UDDebugSessionStateStopped && controller.debugSession.scopes.count > 0, 90);
    XCTAssertTrue(controller.buildRunner.succeeded, @"built first: %@", controller.buildRunner.output);
    UDDebugSession *session = controller.debugSession;
    UDBreakpoint *set = [controller.breakpoints breakpointAtLine:4 inFile:hello];
    XCTAssertEqual(session.state, UDDebugSessionStateStopped, @"stopped at the breakpoint (%@, verified %d: %@): %@",
                   set.path, set.verified, set.message, session.consoleText);
    XCTAssertEqual(session.selectedFrame.line, 4);
    // in whichever scope the debugger has it (lldb: Locals first; gdb: Arguments, then Locals)
    UDDebugVariable *count = nil;
    for (UDDebugVariable *scope in session.scopes) {
        if (scope.expensive) continue;
        [session loadChildrenOfVariable:scope];
        UDRunUntil(scope.children != nil, 20);
        for (UDDebugVariable *variable in scope.children) if ([variable.name isEqualToString:@"count"]) count = variable;
    }
    XCTAssertEqualObjects(count.value, @"3", @"the program and its two arguments: %@", [session.scopes valueForKey:@"children"]);

    [session continueExecution];
    UDRunUntil(session.state == UDDebugSessionStateEnded, 30);
    XCTAssertEqual(session.state, UDDebugSessionStateEnded);
    XCTAssertTrue([session.consoleText containsString:@"hello 3"], @"its output in the console: %@", session.consoleText);
    [controller.breakpoints removeAllBreakpoints];
    [controller close];
    [workspace close];
}

- (void)testRunWithoutDebuggingRunsItItsOutputInTheConsole {
    if (![UDToolLocator debugAdapterCommandForDebugger:nil]) return;
    [self writeCProjectWith:@"#include <stdio.h>\nint main(int argc, char **argv) {\n    printf(\"plain %d\\n\", argc);\n    return 0;\n}\n"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [controller.breakpoints addBreakpointAtLine:3 inFile:[_folder stringByAppendingPathComponent:@"hello.c"]];
    [controller runWithoutDebugging:nil];
    UDRunUntil(controller.debugSession.state == UDDebugSessionStateEnded, 90);
    XCTAssertEqual(controller.debugSession.state, UDDebugSessionStateEnded, @"ran to its end, its breakpoint not stopping it");
    XCTAssertTrue([controller.debugSession.consoleText containsString:@"plain 3"], @"%@", controller.debugSession.consoleText);
    [controller.breakpoints removeAllBreakpoints];
    [controller close];
    [workspace close];
}

/// The settings sheet, once it shows: what it shows noted, the program
/// named, OK. Until then, asked again.
- (void)answerSettingsSheet {
    UDProjectSettingsController *sheet = _sheetController.projectSettings;
    if (!sheet) {
        [self performSelector:@selector(answerSettingsSheet) withObject:nil afterDelay:0.2
                      inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode ]];
        return;
    }
    _sheetBuild = sheet.buildField.stringValue;
    _sheetPlaceholder = [sheet.buildField.cell placeholderString] ?: @"";
    sheet.programField.stringValue = @"hello";
    [sheet.debuggerPopUp selectItemWithTag:0];
    [sheet ok:nil];
}

/// Project Settings: what is guessed shown, this system's section written
/// (the other's kept); a Run with nothing to run asks there, then runs.
- (void)testProjectSettingsAskWhatToRunForThisSystem {
    [self writeCProjectWith:@"#include <stdio.h>\nint main(void) {\n    printf(\"settled\\n\");\n    return 0;\n}\n"];
    // no program said, and the other system's section to keep
    NSString *other = [UDProjectPlatformKey isEqualToString:@"macos"] ? @"gnustep" : @"macos";
    [self write:[NSString stringWithFormat:@"{ \"%@\": { \"build\": \"make other\" } }", other] to:@".udcode/settings.json"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];

    // the sheet answered when it shows (on GNUstep it runs a modal loop of its own)
    _sheetController = controller;
    [self performSelector:@selector(answerSettingsSheet) withObject:nil afterDelay:0.2
                  inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode ]];
    [controller runWithoutDebugging:nil];
    UDRunUntil(_sheetPlaceholder != nil && controller.projectSettings == nil, 60);
    XCTAssertEqualObjects(_sheetBuild, @"", @"nothing set here");
    XCTAssertEqualObjects(_sheetPlaceholder, @"make", @"what is guessed, shown");

    NSDictionary *saved = controller.project.settings;
    XCTAssertEqualObjects(saved[UDProjectPlatformKey][@"run"][@"program"], @"hello", @"this system's section");
    XCTAssertEqualObjects(saved[other][@"build"], @"make other", @"the other's kept");
    XCTAssertEqualObjects(controller.project.runProgram, [_folder stringByAppendingPathComponent:@"hello"].stringByStandardizingPath);

    // and the Run that asked goes on
    if ([UDToolLocator debugAdapterCommandForDebugger:nil]) {
        UDRunUntil(controller.debugSession.state == UDDebugSessionStateEnded, 60);
        XCTAssertTrue([controller.debugSession.consoleText containsString:@"settled"], @"%@", controller.debugSession.consoleText);
    }
    [controller close];
    [workspace close];
}

/// Files changed by another program: an open file with no edits of its own
/// takes the new text (only what differs replaced); one with edits keeps them;
/// a new file is listed.
- (void)testChangesMadeElsewhereShow {
    [self write:@"first line\nsecond line\n" to:@"notes.txt"];
    [self write:@"mine\n" to:@"edited.txt"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    XCTAssertTrue([[controller valueForKey:@"fileWatcher"] isWatching], @"the system's watching started");

    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"notes.txt"]]];
    UDCodeDocument *notes = controller.editorTabs.selectedItem.representedObject;
    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"edited.txt"]]];
    UDCodeDocument *edited = controller.editorTabs.selectedItem.representedObject;
    UDPosition end = [edited.textModel getPositionAt:[edited.textModel getLength]];
    [edited.textModel applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:PTRangeMake(end.line, end.column, end.line, end.column)
                                                                      text:@"typed\n"] ]];
    XCTAssertTrue(edited.isModified);

    // another program writes
    [self write:@"first line\nchanged line\n" to:@"notes.txt"];
    [self write:@"theirs\n" to:@"edited.txt"];
    [self write:@"new\n" to:@"Sources/added.txt"];
    UDRunUntil([[notes.textModel getValue] isEqualToString:@"first line\nchanged line\n"], 10);
    XCTAssertEqualObjects([notes.textModel getValue], @"first line\nchanged line\n", @"read again");
    XCTAssertFalse(notes.isModified, @"as on disk");
    XCTAssertEqualObjects([edited.textModel getValue], @"mine\ntyped\n", @"its own edits kept");

    NSOutlineView *outline = controller.fileNavigator.outlineView;
    [controller.fileNavigator revealURL:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"Sources/added.txt"]]];
    XCTAssertEqualObjects([controller.fileNavigator URLOfRow:outline.selectedRow].lastPathComponent, @"added.txt", @"listed");
    [controller close];
    [workspace close];
}

// ---------------------------------------------------------------------------
// MARK: - VS Code's tasks.json and launch.json
// ---------------------------------------------------------------------------

- (void)testTasksAndLaunchJSONAreReadAsVSCodeReadsThem {
    [self write:@"// VS Code's own comments\n"
                @"{ \"version\": \"2.0.0\",\n"
                @"  \"tasks\": [\n"
                @"    { \"label\": \"prepare\", \"type\": \"shell\", \"command\": \"echo prep\", },  /* a trailing comma */\n"
                @"    { \"label\": \"build\", \"type\": \"shell\", \"command\": \"make\", \"args\": [\"-j4\", \"two words\"],\n"
                @"      \"group\": { \"kind\": \"build\", \"isDefault\": true }, \"dependsOn\": \"prepare\",\n"
                @"      \"options\": { \"cwd\": \"${workspaceFolder}/sub\", \"env\": { \"FLAVOR\": \"${env:HOME}\" } },\n"
                @"      \"osx\": { \"args\": [\"-j8\"] }, \"linux\": { \"args\": [\"-j2\"] } },\n"
                @"    { \"label\": \"test\", \"type\": \"process\", \"command\": \"./run tests\", \"group\": \"test\" }\n"
                @"  ]\n"
                @"}\n" to:@".vscode/tasks.json"];
    [self write:@"{ \"configurations\": [\n"
                @"  { \"name\": \"Hello (lldb)\", \"type\": \"lldb\", \"request\": \"launch\", \"program\": \"${workspaceFolder}/hello\",\n"
                @"    \"args\": [\"${fileBasenameNoExtension}\"], \"cwd\": \"${workspaceFolder}\", \"env\": { \"A\": \"1\" }, \"preLaunchTask\": \"build\" },\n"
                @"  { \"name\": \"Hello (gdb)\", \"type\": \"cppdbg\", \"request\": \"launch\", \"MIMode\": \"gdb\", \"program\": \"hello\",\n"
                @"    \"environment\": [ { \"name\": \"B\", \"value\": \"2\" } ] },\n"
                @"  { \"name\": \"Attach\", \"type\": \"lldb-dap\", \"request\": \"attach\", \"pid\": 42 },\n"
                @"]}\n" to:@".vscode/launch.json"];
    UDTasks *tasks = [[UDTasks alloc] initWithFolderURL:[NSURL fileURLWithPath:_folder]
                                         currentFileURL:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"main.c"]]];
    XCTAssertEqualObjects([tasks.tasks valueForKey:@"label"], (@[ @"prepare", @"build", @"test" ]), @"comments, trailing commas");
    UDTask *build = tasks.buildTask;
    XCTAssertEqualObjects(build.label, @"build", @"the default build task");
#ifdef __APPLE__
    XCTAssertEqualObjects(build.commandLine, @"make -j8", @"osx's args over the rest");
#else
    XCTAssertEqualObjects(build.commandLine, @"make -j2", @"linux's args over the rest");
#endif
    XCTAssertEqualObjects(build.directory, [_folder stringByAppendingPathComponent:@"sub"], @"${workspaceFolder}");
    XCTAssertEqualObjects(build.environment[@"FLAVOR"], NSHomeDirectory(), @"${env:HOME}");
    NSString *line = [tasks commandLineRunning:build];
    XCTAssertTrue([line rangeOfString:@"echo prep"].location < [line rangeOfString:@"make -j"].location, @"dependsOn first: %@", line);
    XCTAssertEqualObjects([tasks taskLabelled:@"test"].commandLine, @"'./run tests'", @"a process's program, quoted");

    NSArray<UDLaunchConfiguration *> *configurations = tasks.configurations;
    XCTAssertEqual(configurations.count, 3u);
    XCTAssertEqualObjects(configurations[0].debugger, @"lldb");
    XCTAssertEqualObjects(configurations[0].program, [_folder stringByAppendingPathComponent:@"hello"]);
    XCTAssertEqualObjects(configurations[0].arguments, @[ @"main" ], @"${fileBasenameNoExtension}");
    XCTAssertEqualObjects(configurations[0].preLaunchTask, @"build");
    XCTAssertEqualObjects(configurations[1].debugger, @"gdb", @"cppdbg with gdb");
    XCTAssertEqualObjects(configurations[1].program, [_folder stringByAppendingPathComponent:@"hello"], @"relative: in the folder");
    XCTAssertEqualObjects(configurations[1].environment, @{ @"B": @"2" }, @"the C/C++ extension's environment");
    XCTAssertEqualObjects(configurations[2].request, @"attach");
    XCTAssertEqual(configurations[2].processID, 42);
}

/// A project set up for VS Code alone: its launch configuration chosen, its
/// preLaunchTask builds, it runs; the Debug menu lists both files' entries.
- (void)testAProjectSetUpForVSCodeRunsAsItIs {
    if (![UDToolLocator debugAdapterCommandForDebugger:nil]) return;
    [self write:@"#include <stdio.h>\nint main(int argc, char **argv) {\n    printf(\"vscode %s\\n\", argv[1]);\n    return 0;\n}\n" to:@"hello.c"];
    [self write:@"{ \"version\": \"2.0.0\", \"tasks\": [\n"
                @"  { \"label\": \"compile\", \"type\": \"shell\", \"command\": \"cc\", \"args\": [\"-g\", \"-o\", \"hello\", \"hello.c\"],\n"
                @"    \"group\": { \"kind\": \"build\", \"isDefault\": true } } ] }\n" to:@".vscode/tasks.json"];
    NSString *type = [UDToolLocator debugAdapterCommandForDebugger:nil] == [UDToolLocator debugAdapterCommandForDebugger:@"gdb"]
        ? @"\"type\": \"cppdbg\", \"MIMode\": \"gdb\"" : @"\"type\": \"lldb\"";
#ifdef __APPLE__
    type = @"\"type\": \"lldb\"";
#else
    type = @"\"type\": \"cppdbg\", \"MIMode\": \"gdb\"";
#endif
    [self write:[NSString stringWithFormat:@"{ \"configurations\": [\n"
                 @"  { \"name\": \"First\", %@, \"request\": \"launch\", \"program\": \"${workspaceFolder}/hello\", \"args\": [\"first\"] },\n"
                 @"  { \"name\": \"Second\", %@, \"request\": \"launch\", \"program\": \"${workspaceFolder}/hello\", \"args\": [\"second\"],\n"
                 @"    \"preLaunchTask\": \"compile\" } ] }\n", type, type] to:@".vscode/launch.json"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];

    // the Debug menu's entries
    AppDelegate *delegate = [[AppDelegate alloc] init];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Launch Configuration"];
    [controller.window makeKeyAndOrderFront:nil];
    [delegate menuNeedsUpdate:menu];
    XCTAssertEqualObjects([menu.itemArray valueForKey:@"title"], (@[ @"First", @"Second" ]));
    XCTAssertEqualObjects(controller.selectedLaunchConfiguration, @"First", @"launch.json's first, until one is chosen");
    [controller selectLaunchConfiguration:menu.itemArray[1]];
    XCTAssertEqualObjects(controller.selectedLaunchConfiguration, @"Second");

    [controller runWithoutDebugging:nil];
    UDRunUntil(controller.debugSession.state == UDDebugSessionStateEnded, 90);
    XCTAssertTrue(controller.buildRunner.succeeded, @"its preLaunchTask built it: %@", controller.buildRunner.output);
    XCTAssertTrue([controller.debugSession.consoleText containsString:@"vscode second"], @"the configuration's args: %@",
                  controller.debugSession.consoleText);
    controller.selectedLaunchConfiguration = nil;
    [controller close];
    [workspace close];
}


// ---------------------------------------------------------------------------
// MARK: - The language's: search, Open Quickly, and clangd's navigation and edits
// ---------------------------------------------------------------------------

/// A WorkspaceEdit's two shapes: an open file's model edited, a closed one's
/// file rewritten, the edits of one file applied together.
- (void)testAWorkspaceEditChangesOpenAndClosedFiles {
    [self write:@"alpha beta\ngamma alpha\n" to:@"closed.txt"];
    NSString *closed = [NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"closed.txt"]].absoluteString;
    NSDictionary *range00 = @{ @"start": @{ @"line": @0, @"character": @0 }, @"end": @{ @"line": @0, @"character": @5 } };
    NSDictionary *range16 = @{ @"start": @{ @"line": @1, @"character": @6 }, @"end": @{ @"line": @1, @"character": @11 } };
    NSDictionary *edit = @{ @"changes": @{ closed: @[ @{ @"range": range00, @"newText": @"omega" },
                                                      @{ @"range": range16, @"newText": @"omega" } ] } };
    NSArray *changed = [UDWorkspaceEdit applyEdit:edit documents:nil error:NULL];
    XCTAssertEqual(changed.count, 1u);
    NSString *text = [NSString stringWithContentsOfFile:[_folder stringByAppendingPathComponent:@"closed.txt"]
                                               encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertEqualObjects(text, @"omega beta\ngamma omega\n");

    // a rename's edit to a stand-in name, given the real one, the file being typed in left out
    NSString *other = [NSURL fileURLWithPath:@"/tmp/elsewhere.c"].absoluteString;
    NSDictionary *standIn = @{ @"changes": @{ closed: @[ @{ @"range": range00, @"newText": @"x_udcode_rename" } ],
                                              other: @[ @{ @"range": range16, @"newText": @"x_udcode_rename" } ] } };
    NSDictionary *renamed = [UDWorkspaceEdit edit:standIn withNewText:@"better"
                                 excludingFileURL:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"closed.txt"]]];
    XCTAssertEqualObjects([renamed[@"changes"] allKeys], @[ other ]);
    XCTAssertEqualObjects(renamed[@"changes"][other][0][@"newText"], @"better");
    XCTAssertEqualObjects(renamed[@"changes"][other][0][@"range"], range16);
    XCTAssertEqual([UDWorkspaceEdit textEditsOfFileURL:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"closed.txt"]]
                                                inEdit:standIn].count, 1u);

    UDTextModel *model = [[UDTextModel alloc] initWithText:@"one two\nthree\n"];
    [UDWorkspaceEdit applyTextEdits:@[ @{ @"range": @{ @"start": @{ @"line": @1, @"character": @0 }, @"end": @{ @"line": @1, @"character": @5 } },
                                          @"newText": @"3" },
                                       @{ @"range": @{ @"start": @{ @"line": @0, @"character": @4 }, @"end": @{ @"line": @0, @"character": @7 } },
                                          @"newText": @"2" } ]
                        toTextModel:model];
    XCTAssertEqualObjects([model getValue], @"one 2\n3\n");
}

/// Edit > Find > Find in Workspace: the folder's files searched, the
/// matches by file in the Find navigator; one chosen, its place shown.
- (void)testFindInWorkspaceShowsWhereTheTextIs {
    [self write:@"nothing here\nthe Needle is here\n" to:@"Sources/one.txt"];
    [self write:@"needle first\nand a needle again\n" to:@"Sources/Model/two.txt"];
    [self write:@"no match\n" to:@"three.txt"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [controller.searchResults searchFor:@"needle"];
    UDRunUntil(!controller.searchResults.searching, 20);
    NSArray<UDSearchResult *> *results = controller.searchResults.results;
    XCTAssertEqual(results.count, 3u, @"%@", [results valueForKey:@"lineText"]);
    NSArray *files = [[results valueForKeyPath:@"url.lastPathComponent"] valueForKeyPath:@"@distinctUnionOfObjects.self"];
    XCTAssertEqualObjects([files sortedArrayUsingSelector:@selector(compare:)], (@[ @"one.txt", @"two.txt" ]));

    UDSearchResult *needle = nil;
    for (UDSearchResult *result in results) {
        if ([result.url.lastPathComponent isEqual:@"one.txt"]) needle = result;
    }
    XCTAssertEqual(needle.line, 2);
    XCTAssertEqual(needle.column, 4);
    [controller searchResults:controller.searchResults showResult:needle];
    UDCodeDocument *shown = controller.editorTabs.selectedItem.representedObject;
    XCTAssertEqualObjects(shown.fileURL.lastPathComponent, @"one.txt");
    NSTextView *textView = [(UDCodeEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem] textView];
    XCTAssertEqualObjects([textView.string substringWithRange:textView.selectedRange], @"Needle");
    [controller close];
    [workspace close];
}

/// Open Quickly: the files whose names have the letters typed, in order,
/// best first.
- (void)testOpenQuicklyFindsFilesByTheirLetters {
    [self write:@"" to:@"Sources/Model/UDThing.m"];
    [self write:@"" to:@"Sources/Model/UDThing.h"];
    [self write:@"" to:@"Sources/OtherThing.m"];
    [self write:@"" to:@".hidden/UDThing.m"];
    UDOpenQuicklyController *open = [[UDOpenQuicklyController alloc] init];
    open.folderURL = [NSURL fileURLWithPath:_folder];
    XCTAssertEqual(open.files.count, 3u, @"%@", open.files);
    XCTAssertFalse([open.files containsObject:@".hidden/UDThing.m"], @"%@", open.files);
    open.query = @"udthing.m";
    XCTAssertEqualObjects([open.results.firstObject.url.path substringFromIndex:_folder.length + 1], @"Sources/Model/UDThing.m");
    open.query = @"othm";
    XCTAssertEqualObjects([open.results valueForKeyPath:@"url.lastPathComponent"], (@[ @"OtherThing.m" ]), @"letters apart");
    open.query = @"zzz";
    XCTAssertEqual(open.results.count, 0u);
}

- (NSTextView *)textViewOf:(UDDocumentWindowController *)controller {
    return [(UDCodeEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem] textView];
}

/// The caret in @a textView, @a offset characters into the @a nth (0-based) @a text.
- (void)put:(NSTextView *)textView at:(NSString *)text nth:(NSUInteger)nth offset:(NSUInteger)offset {
    NSRange found = NSMakeRange(0, 0);
    NSUInteger from = 0;
    for (NSUInteger i = 0; i <= nth; i++) {
        found = [textView.string rangeOfString:text options:0 range:NSMakeRange(from, textView.string.length - from)];
        from = NSMaxRange(found);
    }
    textView.selectedRange = NSMakeRange(found.location + offset, 0);
}

/// clangd, through the Navigate and Editor menus: the caret's symbol
/// highlighted where it occurs; Fix Issue's fix; Jump to Definition; Find
/// References; Rename Symbol; Format Document; a call's signature as it is typed.
- (void)testClangdNavigatesAndEditsTheCode {
    if (![UDToolLocator clangdPath]) {
        NSLog(@"UDProjectTests: no clangd here; its case checks nothing");
        return;
    }
    [self write:@"static int counter;\n"
                @"static int bump(int by) {\n"
                @"    counter = counter + by;\n"
                @"    return counter;\n"
                @"}\n"
                @"int main(void) {\n"
                @"    int   x=bump(1);\n"
                @"    return x + bump(2)\n"
                @"}\n" to:@"main.c"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [controller.window makeKeyAndOrderFront:nil];
    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"main.c"]]];
    UDCodeDocument *document = controller.editorTabs.selectedItem.representedObject;
    NSTextView *textView = [self textViewOf:controller];
    UDLSPCoordinator *lsp = ((UDEditorSession *)[[controller valueForKey:@"sessions"] objectForKey:document]).lspCoordinator;
    UDRunUntil([[self messagesOf:document] containsString:@"after return statement"], 30);
    XCTAssertTrue([[self messagesOf:document] containsString:@"after return statement"], @"%@", [self messagesOf:document]);

    // the occurrences of counter: its declaration, two writes' and reads'
    [self put:textView at:@"counter" nth:1 offset:2];
    [controller textViewDidChangeSelection:[NSNotification notificationWithName:NSTextViewDidChangeSelectionNotification object:textView]];
    UDRunUntil(lsp.occurrenceRanges.count == 4, 10);
    XCTAssertEqual(lsp.occurrenceRanges.count, 4u);

    // Fix Issue: clangd's fix, the missing semicolon, in a Fix-its panel; Return applies it
    [self put:textView at:@"bump(2)" nth:0 offset:7];
    [controller fixIssue:nil];
    UDRunUntil(controller.issuePopup != nil, 10);
    XCTAssertNotNil(controller.issuePopup, @"the Fix-its are up");
    XCTAssertTrue([controller.issuePopup.messageLabel.stringValue containsString:@"after return statement"],
                  @"the issue's message: %@", controller.issuePopup.messageLabel.stringValue);
    XCTAssertTrue(controller.issuePopup.fixes.count > 0);
    [textView doCommandBySelector:@selector(insertNewline:)];
    XCTAssertNil(controller.issuePopup, @"away once applied");
    XCTAssertTrue([[document.textModel getValue] containsString:@"bump(2);"], @"%@", [document.textModel getValue]);
    XCTAssertFalse([[document.textModel getValue] containsString:@"bump(2)\n\n"], @"Return went to the panel, not the text");

    // Jump to Definition, from a call
    [self put:textView at:@"bump" nth:1 offset:1];
    [controller jumpToDefinition:nil];
    UDRunUntil(textView.selectedRange.location < 40, 10);
    XCTAssertEqualObjects([textView.string substringWithRange:textView.selectedRange], @"bump", @"its declaration");
    XCTAssertEqual(textView.selectedRange.location, [textView.string rangeOfString:@"bump"].location);

    // Find References: the declaration and both calls
    [controller findReferences:nil];
    UDRunUntil(controller.searchResults.results.count == 3, 10);
    XCTAssertEqualObjects([controller.searchResults.results valueForKey:@"line"], (@[ @2, @7, @8 ]));

    // Rename Symbol, as Xcode's: typed where it stands, the file's other places following
    [self put:textView at:@"bump" nth:2 offset:2];
    [controller renameSymbol:nil];
    UDRunUntil(controller.renaming != nil, 10);
    XCTAssertEqual(controller.renaming.ranges.count, 3u, @"its declaration and both calls");
    XCTAssertEqualObjects([textView.string substringWithRange:textView.selectedRange], @"bump", @"the one at the caret selected");
    [textView insertText:@"incr"];
    UDRunUntil([[document.textModel getValue] componentsSeparatedByString:@"incr("].count == 4, 5);
    XCTAssertEqual([[document.textModel getValue] componentsSeparatedByString:@"incr("].count, 4u, @"%@", [document.textModel getValue]);
    [textView insertText:@"ease"];
    [textView doCommandBySelector:@selector(insertNewline:)];
    XCTAssertNil(controller.renaming, @"Return ends it");
    XCTAssertFalse([[document.textModel getValue] containsString:@"bump"], @"%@", [document.textModel getValue]);
    XCTAssertEqual([[document.textModel getValue] componentsSeparatedByString:@"increase("].count, 4u, @"%@", [document.textModel getValue]);
    XCTAssertFalse([[document.textModel getValue] containsString:@"\n\n"], @"Return made no line: %@", [document.textModel getValue]);

    // Escape puts it back
    [self put:textView at:@"increase" nth:1 offset:0];
    [controller renameSymbol:nil];
    UDRunUntil(controller.renaming != nil, 10);
    [textView insertText:@"oops"];
    UDRunUntil([[document.textModel getValue] componentsSeparatedByString:@"oops"].count == 4, 5);
    [textView doCommandBySelector:@selector(cancelOperation:)];
    XCTAssertFalse([[document.textModel getValue] containsString:@"oops"], @"%@", [document.textModel getValue]);
    XCTAssertEqual([[document.textModel getValue] componentsSeparatedByString:@"increase("].count, 4u);

    // Format Document: clangd's style
    [controller formatDocument:nil];
    UDRunUntil([[document.textModel getValue] containsString:@"int x = increase(1);"], 10);
    XCTAssertTrue([[document.textModel getValue] containsString:@"int x = increase(1);"], @"%@", [document.textModel getValue]);

    // a call typed: its signature, the parameter
    [self put:textView at:@"return x" nth:0 offset:0];
    [textView insertText:@"increase("];
    UDRunUntil([controller.signatureHelpText containsString:@"int by"], 10);
    XCTAssertTrue([controller.signatureHelpText containsString:@"increase(int by)"], @"%@", controller.signatureHelpText);

    [controller close];
    [workspace close];
}


// ---------------------------------------------------------------------------
// MARK: - Xcode's window: its toolbar
// ---------------------------------------------------------------------------

/// The toolbar, as Xcode's: the navigator's button, Run and Stop, the scheme
/// (launch.json's configurations), the activity view saying what goes on,
/// the inspector's button; Run and Stop enabled as their menu items are.
- (void)testTheToolbarIsXcodes {
    [self writeCProjectWith:@"#include <stdio.h>\nint main(void) {\n    return 0;\n}\n"];
    [self write:@"{ \"configurations\": [\n"
                @"  { \"name\": \"First\", \"type\": \"lldb\", \"request\": \"launch\", \"program\": \"${workspaceFolder}/hello\" },\n"
                @"  { \"name\": \"Second\", \"type\": \"lldb\", \"request\": \"launch\", \"program\": \"${workspaceFolder}/hello\" } ] }\n"
             to:@".vscode/launch.json"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    controller.selectedLaunchConfiguration = nil;
    NSToolbar *toolbar = controller.window.toolbar;
    XCTAssertNotNil(toolbar);
    NSArray *labels = [[toolbar.items valueForKey:@"label"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    XCTAssertEqualObjects(labels, (@[ @"Navigator", @"Run", @"Stop", @"Scheme", @"Activity", @"Inspector" ]));

    NSPopUpButton *scheme = controller.schemePopUp;
    XCTAssertEqualObjects(scheme.itemTitles, (@[ @"First", @"Second" ]));
    XCTAssertEqualObjects(scheme.titleOfSelectedItem, @"First");
    [scheme selectItemAtIndex:1];
    [controller selectLaunchConfiguration:scheme];
    XCTAssertEqualObjects(controller.selectedLaunchConfiguration, @"Second", @"chosen in the toolbar");
    XCTAssertEqualObjects(scheme.titleOfSelectedItem, @"Second");

    NSString *name = controller.project.name;
    XCTAssertEqualObjects(controller.activityText, ([NSString stringWithFormat:@"%@ | Ready", name]));
    NSToolbarItem *stop = nil, *run = nil;
    for (NSToolbarItem *item in toolbar.items) {
        if ([item.label isEqual:@"Stop"]) stop = item;
        if ([item.label isEqual:@"Run"]) run = item;
    }
    XCTAssertTrue([controller validateToolbarItem:run]);
    XCTAssertFalse([controller validateToolbarItem:stop], @"nothing to stop");

    [controller build:nil];
    XCTAssertEqualObjects(controller.activityText, ([NSString stringWithFormat:@"%@ | Building %@…", name, name]));
    XCTAssertTrue([controller validateToolbarItem:stop], @"the build can be stopped");
    UDRunUntil(!controller.buildRunner.running, 60);
    UDRunUntil(NO, 0.1);
    XCTAssertEqualObjects(controller.activityText, ([NSString stringWithFormat:@"%@ | Build Succeeded", name]));
    controller.selectedLaunchConfiguration = nil;
    [controller close];
    [workspace close];
}


/// View > Terminal: a shell in the bottom area, in the project's folder.
- (void)testTheTerminalOpensInTheProjectsFolder {
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [controller showTerminal:nil];
    UDTerminalViewController *terminal = controller.terminal;
    XCTAssertTrue(terminal.running);
    XCTAssertFalse(terminal.view.superview.isHidden, @"the terminal shown");
    XCTAssertEqual(controller.window.firstResponder, terminal.terminalView);
    [terminal.pseudoTerminal writeData:[@"echo \"at:$(pwd -P)\"\r" dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *expected = [@"at:" stringByAppendingString:_folder];
    UDRunUntil([terminal.terminalView.screenText containsString:expected], 30);
    XCTAssertTrue([terminal.terminalView.screenText containsString:expected], @"%@", terminal.terminalView.screenText);

    // the switch back to the debugger's area, and the terminal's again
    [controller.window makeFirstResponder:nil];
    [controller showTerminal:nil];
    XCTAssertTrue(terminal.running, @"the same shell");
    [controller close];
    UDRunUntil(!terminal.running, 10);
    XCTAssertFalse(terminal.running, @"hung up on with its window");
    [workspace close];
}


/// clangd's semantic tokens, coloured over tree-sitter's: a macro, a
/// parameter, a field, a typedef's name, code an #if leaves out.
- (void)testClangdColoursWhatOnlyTheCompilerKnows {
    if (![UDToolLocator clangdPath]) {
        NSLog(@"UDProjectTests: no clangd here; its case checks nothing");
        return;
    }
    [self write:@"#define SQUARE(x) ((x) * (x))\n"
                @"struct point { int x; int y; };\n"
                @"typedef struct point point_t;\n"
                @"static int area(point_t p, int scale) {\n"
                @"    return SQUARE(p.x) * scale;\n"
                @"}\n"
                @"#if 0\n"
                @"int left_out;\n"
                @"#endif\n"
                @"int main(void) { point_t q = { 1, 2 }; return area(q, 3); }\n" to:@"shapes.c"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"shapes.c"]]];
    UDCodeDocument *document = controller.editorTabs.selectedItem.representedObject;
    UDEditorSession *session = [[controller valueForKey:@"sessions"] objectForKey:document];
    UDLSPCoordinator *lsp = session.lspCoordinator;
    UDRunUntil(lsp.semanticTokenCount > 0, 30);
    XCTAssertGreaterThan(lsp.semanticTokenCount, 0u, @"clangd's tokens");

    NSString *text = [document.textModel getValue];
    NSUInteger (^at)(NSString *, NSUInteger) = ^NSUInteger(NSString *word, NSUInteger nth) {
        NSRange found = NSMakeRange(0, 0);
        NSUInteger from = 0;
        for (NSUInteger i = 0; i <= nth; i++) {
            found = [text rangeOfString:word options:0 range:NSMakeRange(from, text.length - from)];
            from = NSMaxRange(found);
        }
        return found.location;
    };
    XCTAssertEqualObjects([lsp semanticTokenAtIndex:at(@"SQUARE", 1)], @"constant.macro", @"the macro, where it is used");
    XCTAssertEqualObjects([lsp semanticTokenAtIndex:at(@"scale", 1)], @"variable.parameter");
    XCTAssertEqualObjects([lsp semanticTokenAtIndex:at(@"p.x", 0) + 2], @"property", @"the field");
    XCTAssertEqualObjects([lsp semanticTokenAtIndex:at(@"point_t", 2)], @"type", @"the typedef's name");
    XCTAssertEqualObjects([lsp semanticTokenAtIndex:at(@"left_out", 0)], @"comment", @"what #if 0 leaves out");

    // drawn in the theme's colour for it
    TreeSitterTheme *theme = [controller valueForKey:@"currentTheme"];
    NSColor *parameter = [theme styleAttributesForName:@"variable.parameter"][NSForegroundColorAttributeName];
    NSColor *drawn = [session.textStorage attribute:NSForegroundColorAttributeName atIndex:at(@"scale", 1) effectiveRange:NULL];
    XCTAssertEqualObjects(drawn, parameter);
    [controller close];
    [workspace close];
}

@end
