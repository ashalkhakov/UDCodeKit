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
@end

@implementation UDProjectTests

- (void)setUp {
    [super setUp];
    _folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:[_folder stringByAppendingPathComponent:@"Sources/Model"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
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
    XCTAssertEqualObjects(project.runDirectory, _folder.stringByStandardizingPath);

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
    XCTAssertFalse(controller.projectHost.hidden);
    XCTAssertTrue(controller.filesTable.enclosingScrollView.hidden, @"instead of the open files");
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
    XCTAssertEqualObjects([controller.fileNavigator URLOfRow:outline.selectedRow].path, model.URLByStandardizingPath.path);
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

@end
