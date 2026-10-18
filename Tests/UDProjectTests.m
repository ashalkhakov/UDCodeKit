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

@end
