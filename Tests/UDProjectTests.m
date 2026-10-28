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
#import "UDProjectTests.h"
#import <UDCodeKit/UDCodeKit.h>
#import "AppDelegate.h"
#import "UDDocument.h"
#import "UDDocumentWindowController.h"
// CFamily's, UDCode's plugin: its classes reached by name once the plugins
// are loaded (the tests link UDCodeKit, not the bundle); its headers for
// what they answer to
#import "UDCFamilyPlugin.h"
#import "UDCFamilyDebuggers.h"
#import "UDCFamilyTestOutput.h"
#import "UDXCTestSources.h"
#import "UDGNUstepMakeBuildSystem.h"
#import "UDXcodeBuildSystem.h"
#import "UDCMakeBuildSystem.h"
#import "UDGoogleTestRunner.h"
#import "UDCTestRunner.h"
#import "UDXCTestBundleRunner.h"

static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}
#define UDPlugin(name) ((id)UDPluginClass(@#name))

@interface UDDocumentWindowController (ProjectTesting)
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
@property (nonatomic, weak) NSTableView *filesTable;
@property (nonatomic, weak) NSView *projectHost;
- (void)searchResults:(UDSearchResultsViewController *)controller showResult:(UDSearchResult *)result;
- (void)textViewDidChangeSelection:(NSNotification *)note;
@property (nonatomic, weak) NSPopUpButton *schemePopUp;
@end

/// A machine with only the tools named (a Steam Deck: CMake, Ninja, no make).
@interface UDProjectWithTools : UDProject
@property (nonatomic, copy) NSSet<NSString *> *tools;
@end

@implementation UDProjectWithTools
- (BOOL)hasTool:(NSString *)name {
    return [_tools containsObject:name];
}
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
    XCTAssertEqualObjects(self.project.buildSystem.name, @"GNUstep make");
    XCTAssertEqualObjects(self.project.runProgram, [_folder stringByAppendingPathComponent:@"Hello.app/Hello"],
                          @"the application's executable");
    XCTAssertEqualObjects(self.project.buildCommand, @"make debug=yes", @"unoptimized, for the debugger");
    XCTAssertEqualObjects(self.project.cleanCommand, @"make debug=yes clean");
    XCTAssertNotNil(self.project.buildEnvironment[@"GNUSTEP_MAKEFILES"], @"GNUstep's environment, as GNUstep.sh has it");
    XCTAssertNotNil([self.project pathOfToolOnBuildPath:@"make"], @"its PATH the system's (on Windows, MSYS2's make on it)");
#else
    XCTAssertEqualObjects(self.project.buildSystem.name, @"make", @"a GNUmakefile is GNUstep's: not on macOS");
    [self write:@"all:\n" to:@"Makefile.apple"];
    XCTAssertEqualObjects(self.project.buildCommand, @"make -f Makefile.apple", @"on macOS, Makefile.apple");
#endif
}

/// The shell its commands and terminal run in: its settings' when this
/// machine has it, else the user's (Preferences), else the system's (nil).
- (void)testItsShellIsItsOwnThenTheUsers {
    NSString *program = [NSBundle mainBundle].executablePath;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:UDShellDefaultsKey];
    XCTAssertNil(self.project.shell, @"none chosen: the system's");
    [defaults setObject:program forKey:UDShellDefaultsKey];
    XCTAssertEqualObjects(self.project.shell, program, @"the user's");
    [self write:@"{ \"shell\": \"/no/such/shell\" }" to:@".udcode/settings.json"];
    XCTAssertEqualObjects(self.project.shell, program, @"one this machine hasn't is passed over");
    [defaults removeObjectForKey:UDShellDefaultsKey];
    NSData *own = [NSJSONSerialization dataWithJSONObject:@{ @"shell": program } options:0 error:NULL];
    [self write:[[NSString alloc] initWithData:own encoding:NSUTF8StringEncoding] to:@".udcode/settings.json"];
    XCTAssertEqualObjects(self.project.shell, program, @"its own");
}

/// An Xcode project: its Debug build (as Xcode's Run), and what that makes
/// run, as xcodebuild -showBuildSettings says: the first application or tool.
- (void)testAnXcodeProjectRunsWhatItsDebugBuildMakes {
    NSString *settings = @"Command line invocation:\n    xcodebuild -showBuildSettings\n\n"
                         @"Build settings for action build and target Kit:\n"
                         @"    FULL_PRODUCT_NAME = Kit.framework\n"
                         @"    PRODUCT_TYPE = com.apple.product-type.framework\n"
                         @"    TARGET_BUILD_DIR = /tmp/p/build/Debug\n\n"
                         @"Build settings for action build and target Calculator:\n"
                         @"    ACTION = build\n"
                         @"    FULL_PRODUCT_NAME = Calculator.app\n"
                         @"    PRODUCT_TYPE = com.apple.product-type.application\n"
                         @"    TARGET_BUILD_DIR = /tmp/p/build/Debug\n\n"
                         @"Build settings for action build and target CalculatorTests:\n"
                         @"    FULL_PRODUCT_NAME = CalculatorTests.xctest\n"
                         @"    PRODUCT_TYPE = com.apple.product-type.bundle.unit-test\n";
    XCTAssertEqualObjects([UDPlugin(UDXcodeBuildSystem) productOfBuildSettings:settings], @"/tmp/p/build/Debug/Calculator.app");
    XCTAssertNil([UDPlugin(UDXcodeBuildSystem) productOfBuildSettings:@"Build settings for action build and target Kit:\n"
                                                            @"    FULL_PRODUCT_NAME = Kit.framework\n"
                                                   @"    PRODUCT_TYPE = com.apple.product-type.framework\n"
                                                   @"    TARGET_BUILD_DIR = /tmp\n"], @"nothing to run");
    XCTAssertEqualObjects([UDProject quotedArgument:@"My App.xcodeproj"], @"'My App.xcodeproj'");
#ifndef GNUSTEP
    [[NSFileManager defaultManager] createDirectoryAtPath:[_folder stringByAppendingPathComponent:@"Calculator.xcodeproj"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    XCTAssertEqualObjects(self.project.buildSystem.name, @"Xcode");
    XCTAssertEqualObjects(self.project.buildCommand, @"xcodebuild -configuration Debug build", @"Debug, as Xcode's Run");
    XCTAssertEqualObjects(self.project.cleanCommand, @"xcodebuild -configuration Debug clean");
    [[NSFileManager defaultManager] createDirectoryAtPath:[_folder stringByAppendingPathComponent:@"Other Thing.xcodeproj"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    XCTAssertEqualObjects(self.project.buildCommand, @"xcodebuild -configuration Debug -project Calculator.xcodeproj build",
                          @"which, when there are two");
#endif
}

/// A Makefile and a CMakeLists.txt: the build this machine has the tool
/// for; CMake with Ninja where there is no make, unless already configured.
- (void)testMakeOrCMakeAsTheMachineHasThem {
    [self write:@"all:\n" to:@"Makefile"];
    [self write:@"project(x)\n" to:@"CMakeLists.txt"];
    UDProjectWithTools *project = [[UDProjectWithTools alloc] initWithFolderURL:[NSURL fileURLWithPath:_folder]];
    project.tools = [NSSet setWithObjects:@"make", @"cmake", nil];
    XCTAssertEqualObjects(project.buildCommand, @"make", @"make, when there is one");
    project.tools = [NSSet setWithObjects:@"cmake", @"ninja", nil];
    XCTAssertEqualObjects(project.buildSystem.name, @"CMake");
    XCTAssertEqualObjects(project.buildCommand, @"cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -G Ninja && cmake --build build");
    XCTAssertEqualObjects(project.cleanCommand, @"cmake --build build --target clean");
    [self write:@"CMAKE_GENERATOR:INTERNAL=Unix Makefiles\n" to:@"build/CMakeCache.txt"];
    XCTAssertEqualObjects(project.buildCommand, @"cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && cmake --build build", @"configured: its own generator");
    project.tools = [NSSet set];
    XCTAssertEqualObjects(project.buildSystem.name, @"make", @"neither: the Makefile, as before");
}

/// Run from an AppImage, what UDCode starts (a build, a shell, a debugger, a
/// language server) gets the machine's environment back, not the image's.
- (void)testWhatItStartsGetsTheMachinesEnvironment {
    NSDictionary *image = @{ @"PATH": @"/tmp/.mount_UDCode/usr/bin:/usr/bin:/bin",
                             @"LD_LIBRARY_PATH": @"/tmp/.mount_UDCode/usr/lib",
                             @"APPIMAGE_HOST_PATH": @"/usr/bin:/bin:/opt/gnustep/System/Tools",
                             @"APPIMAGE_HOST_LD_LIBRARY_PATH": @"",
                             @"GNUSTEP_CONFIG_FILE": @"/tmp/GNUstep-UDCode-1.conf",
                             @"GNUSTEP_SYSTEM_ROOT": @"/tmp/.mount_UDCode/usr/System",
                             @"FONTCONFIG_FILE": @"/tmp/fonts-udcode-1.conf",
                             @"APPDIR": @"/tmp/.mount_UDCode", @"APPIMAGE": @"/home/me/UDCode.AppImage",
                             @"HOME": @"/home/me", @"LANG": @"en_US.UTF-8" };
    NSDictionary *host = [LSPTransport hostEnvironmentOf:image];
    XCTAssertEqualObjects(host, (@{ @"PATH": @"/usr/bin:/bin:/opt/gnustep/System/Tools", @"HOME": @"/home/me",
                                    @"LANG": @"en_US.UTF-8" }));
    NSMutableDictionary *withLibraries = [image mutableCopy];
    withLibraries[@"APPIMAGE_HOST_LD_LIBRARY_PATH"] = @"/opt/gnustep/Local/Library/Libraries";
    XCTAssertEqualObjects([LSPTransport hostEnvironmentOf:withLibraries][@"LD_LIBRARY_PATH"], @"/opt/gnustep/Local/Library/Libraries");
    // not from an AppImage: as it is
    NSDictionary *plain = @{ @"PATH": @"/usr/bin", @"GNUSTEP_MAKEFILES": @"/opt/gnustep/System/Library/Makefiles" };
    XCTAssertEqualObjects([LSPTransport hostEnvironmentOf:plain], plain);
    // started from Windows' Start menu: its "Path" is PATH
    NSDictionary *windows = @{ @"Path": @"C:\\Windows\\system32;C:\\Windows", @"COMSPEC": @"C:\\Windows\\system32\\cmd.exe" };
    XCTAssertEqualObjects([LSPTransport hostEnvironmentOf:windows],
                          (@{ @"PATH": @"C:\\Windows\\system32;C:\\Windows", @"COMSPEC": @"C:\\Windows\\system32\\cmd.exe" }));
}

/// A GNUstep project whose GNUmakefile is in a folder of its own, beside an
/// Xcode project (ProjectCenter's, as UDCalc's): its application's folder.
- (void)testAGNUmakefileInAFolderOfItsOwn {
    [self write:@"include $(GNUSTEP_MAKEFILES)/common.make\nTOOL_NAME = CalculatorTests\n" to:@"CalculatorTests/GNUmakefile"];
    [self write:@"include $(GNUSTEP_MAKEFILES)/common.make\nAPP_NAME = Calculator\n" to:@"Calculator/GNUmakefile"];
#ifdef GNUSTEP
    XCTAssertEqualObjects(self.project.buildSystem.name, @"GNUstep make");
    XCTAssertEqualObjects(self.project.buildCommand, @"make -C Calculator debug=yes", @"the application's, not the tests'");
    XCTAssertEqualObjects(self.project.runProgram, [_folder stringByAppendingPathComponent:@"Calculator/Calculator.app/Calculator"]);
    XCTAssertEqualObjects(self.project.inferredProgram, @"Calculator/Calculator.app");
#else
    XCTAssertNil(self.project.buildSystem, @"GNUstep's, not macOS's");
#endif
}

/// A GNUstep project of several (UDQuakeTools'): what its SUBPROJECTS build
/// that runs, applications first, each a scheme in the toolbar; the one
/// chosen is run, and kept.
- (void)testAProjectOfSeveralProgramsHasASchemeForEach {
    [self write:@"include $(GNUSTEP_MAKEFILES)/common.make\nSUBPROJECTS = Sources/Libraries Tools/paktool Sources/Launcher \\\n"
                @"              Sources/Quarry\ninclude $(GNUSTEP_MAKEFILES)/aggregate.make\n" to:@"GNUmakefile"];
    [self write:@"LIBRARY_NAME = libquake\n" to:@"Sources/Libraries/GNUmakefile"];
    [self write:@"TOOL_NAME = paktool\n" to:@"Tools/paktool/GNUmakefile"];
    [self write:@"APP_NAME = Launcher\n" to:@"Sources/Launcher/GNUmakefile"];
    [self write:@"APP_NAME = Quarry # the editor\n" to:@"Sources/Quarry/GNUmakefile"];
#ifdef GNUSTEP
    XCTAssertEqualObjects(self.project.programs, (@[ @"Sources/Launcher/Launcher.app", @"Sources/Quarry/Quarry.app",
                                                     @"Tools/paktool/obj/paktool" ]));
    XCTAssertEqualObjects(self.project.inferredProgram, @"Sources/Launcher/Launcher.app", @"the first application");
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    controller.selectedProgram = nil;
    NSPopUpButton *scheme = controller.schemePopUp;
    XCTAssertEqualObjects(scheme.itemTitles, (@[ @"Launcher", @"Quarry", @"paktool" ]));
    [scheme selectItemAtIndex:1];
    [controller selectProgram:scheme];
    XCTAssertEqualObjects(controller.project.runProgram,
                          [_folder stringByAppendingPathComponent:@"Sources/Quarry/Quarry.app/Quarry"], @"the scheme chosen");
    XCTAssertEqualObjects(scheme.titleOfSelectedItem, @"Quarry");
    [controller close];
    [workspace close];
    // kept with the project
    controller = [self openProject:&workspace];
    XCTAssertEqualObjects(controller.project.inferredProgram, @"Sources/Quarry/Quarry.app");
    controller.selectedProgram = nil;
    [controller close];
    [workspace close];
#else
    XCTAssertEqualObjects(self.project.programs, @[], @"GNUstep's, not macOS's");
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
    // CFamily's, the extensions': lldb's first on macOS, gdb's elsewhere
    NSArray *names = [[UDDebugger classes] valueForKey:@"name"];
#ifdef __APPLE__
    XCTAssertEqualObjects(names, (@[ @"lldb", @"gdb" ]));
#else
    XCTAssertEqualObjects(names, (@[ @"gdb", @"lldb" ]));
#endif
    NSDictionary *lldb = [[UDDebugger classNamed:@"lldb"] launchArgumentsForProgram:@"/p" arguments:@[ @"a" ]
                                                                         directory:@"/d" environment:@{ @"K": @"v" }];
    XCTAssertEqualObjects(lldb[@"env"], @[ @"K=v" ], @"lldb-dap: NAME=value");
    NSDictionary *gdb = [[UDDebugger classNamed:@"gdb"] launchArgumentsForProgram:@"/p" arguments:@[ @"a" ]
                                                                       directory:@"/d" environment:@{ @"K": @"v" }];
    XCTAssertEqualObjects(gdb[@"env"], @{ @"K": @"v" });
    XCTAssertEqualObjects(gdb[@"program"], @"/p");
    XCTAssertEqualObjects(gdb[@"args"], @[ @"a" ]);
    XCTAssertEqualObjects(gdb[@"cwd"], @"/d");
    XCTAssertEqualObjects([[UDDebugger classOfAdapterCommand:@[ @"/usr/bin/lldb-dap-18" ]] name], @"lldb");
    XCTAssertEqualObjects([[UDDebugger classOfAdapterCommand:(@[ @"/usr/bin/gdb", @"-i", @"dap" ])] name], @"gdb");
    XCTAssertEqualObjects([[UDDebugger classNamed:@"gdb"] adapterCommandWithExecutable:@"/opt/gdb"], (@[ @"/opt/gdb", @"-i", @"dap" ]),
                          @"launch.json's miDebuggerPath");
    XCTAssertEqualObjects([UDDebugger adapterCommandForDebugger:@[ @"my-adapter" ]], @[ @"my-adapter" ],
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
    if (![UDToolLocator pathOfLLVMTool:@"clangd"]) {
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

/// A file reached by another path to it (a link to the project's folder;
/// on Windows a short name, C:/Users/ARTYOM~1) is opened by its real path:
/// the project's, as its folder is known, and its language server's.
- (void)testAFileReachedByAnotherPathIsTheProjects {
    [self write:@"notes\n" to:@"notes.txt"];
    NSString *link = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    if (![[NSFileManager defaultManager] createSymbolicLinkAtPath:link withDestinationPath:_folder error:NULL]) {
        NSLog(@"UDProjectTests: no symbolic link here; its case checks nothing");
        return;
    }
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [controller openURLInNewTab:[NSURL fileURLWithPath:[link stringByAppendingPathComponent:@"notes.txt"]]];
    UDCodeDocument *document = controller.editorTabs.selectedItem.representedObject;
    XCTAssertEqualObjects(document.fileURL.path, [controller.project.folderURL.path stringByAppendingPathComponent:@"notes.txt"]);
    [controller close];
    [workspace close];
    [[NSFileManager defaultManager] removeItemAtPath:link error:NULL];
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

/// The Issues navigator, as Xcode's: an error's red mark, a warning's
/// yellow one, a file's issues counted by kind; not edited by a double-click.
- (void)testIssuesAreErrorsOrWarningsAsTheyAre {
    UDDiagnosticStore *store = [[UDDiagnosticStore alloc] init];
    [store setDiagnostics:@[ [[UDDiagnosticItem alloc] initWithLine:3 column:1 message:@"unused variable 'x'"
                                                          severity:UDDiagnosticSeverityWarning source:UDDiagnosticSourceBuild],
                             [[UDDiagnosticItem alloc] initWithLine:7 column:1 message:@"undeclared identifier"
                                                          severity:UDDiagnosticSeverityError source:UDDiagnosticSourceBuild],
                             [[UDDiagnosticItem alloc] initWithLine:9 column:1 message:@"unused function"
                                                          severity:UDDiagnosticSeverityWarning source:UDDiagnosticSourceBuild] ]
                forSource:UDDiagnosticSourceBuild];
    UDErrorsViewController *issues = [[UDErrorsViewController alloc] init];
    (void)issues.view;
    [issues setStores:@[ store ] displayNames:@[ @"UDVM.m" ]];
    NSOutlineView *outline = [issues valueForKey:@"outlineView"];
    NSTableColumn *column = outline.tableColumns.firstObject;
    id file = [outline itemAtRow:0];
    XCTAssertEqualObjects([issues outlineView:outline objectValueForTableColumn:column byItem:file], @"UDVM.m (1 error, 2 warnings)");
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    for (NSInteger row = 1; row < outline.numberOfRows; row++) {
        id value = [issues outlineView:outline objectValueForTableColumn:column byItem:[outline itemAtRow:row]];
        [rows addObject:[value isKindOfClass:[NSAttributedString class]] ? [value string] : value];
    }
    XCTAssertEqual(rows.count, 3u);
    for (NSString *row in rows) {
        BOOL warning = [row containsString:@"unused"];
        XCTAssertTrue([row hasPrefix:warning ? @"\u25B2 Line" : @"\u25CF Line"], @"%@", row);
    }
    XCTAssertFalse([issues outlineView:outline shouldEditTableColumn:column item:[outline itemAtRow:1]], @"a double-click goes to it");
    XCTAssertFalse(column.isEditable);
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
    if (![UDDebugger adapterCommandForDebugger:nil]) {
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
    if (![UDDebugger adapterCommandForDebugger:nil]) return;
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
    if ([UDDebugger adapterCommandForDebugger:nil]) {
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
    // unset (Windows' Start menu sets no HOME), "" as VS Code has it
    XCTAssertEqualObjects(build.environment[@"FLAVOR"], NSProcessInfo.processInfo.environment[@"HOME"] ?: @"", @"${env:HOME}");
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
    // the debugger its launch.json names: lldb on macOS, gdb (14 or later, for its DAP) on Linux
#ifdef __APPLE__
    NSString *debugger = @"lldb";
#else
    NSString *debugger = @"gdb";
#endif
    if (![UDDebugger adapterCommandForDebugger:debugger]) {
        NSLog(@"UDProjectTests: no %@ that speaks DAP here; its case checks nothing", debugger);
        return;
    }
    [self write:@"#include <stdio.h>\nint main(int argc, char **argv) {\n    printf(\"vscode %s\\n\", argv[1]);\n    return 0;\n}\n" to:@"hello.c"];
    [self write:@"{ \"version\": \"2.0.0\", \"tasks\": [\n"
                @"  { \"label\": \"compile\", \"type\": \"shell\", \"command\": \"cc\", \"args\": [\"-g\", \"-o\", \"hello\", \"hello.c\"],\n"
                @"    \"group\": { \"kind\": \"build\", \"isDefault\": true } } ] }\n" to:@".vscode/tasks.json"];
#ifdef __APPLE__
    NSString *type = @"\"type\": \"lldb\"";
#else
    NSString *type = @"\"type\": \"cppdbg\", \"MIMode\": \"gdb\"";
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
    if (![UDToolLocator pathOfLLVMTool:@"clangd"]) {
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
    // MSYS2's bash says its folder as Windows has it with pwd -W (/tmp/x is
    // C:/msys64/tmp/x); other shells have no -W
    [terminal.pseudoTerminal writeData:[@"echo \"at:$( (pwd -W || pwd -P) 2>/dev/null)\"\r" dataUsingEncoding:NSUTF8StringEncoding]];
    // its rows joined: a folder longer than the terminal is wide (macOS's
    // /private/var/folders/...) goes on to the next row
    NSString *expected = [@"at:" stringByAppendingString:_folder];
    UDRunUntil([[terminal.terminalView.screenText stringByReplacingOccurrencesOfString:@"\n" withString:@""] containsString:expected], 30);
    XCTAssertTrue([[terminal.terminalView.screenText stringByReplacingOccurrencesOfString:@"\n" withString:@""] containsString:expected],
                  @"%@", terminal.terminalView.screenText);

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
    if (![UDToolLocator pathOfLLVMTool:@"clangd"]) {
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


// ---------------------------------------------------------------------------
// MARK: - Tests: found, run, marked, debugged
// ---------------------------------------------------------------------------

/// A catalog of the tests in these sources (path → text), as CFamily
/// finds them, a run's output read as its runners read it.
- (UDTestCatalog *)catalogOfSources:(NSDictionary<NSString *, NSString *> *)sources {
    UDTestCatalog *catalog = [[UDTestCatalog alloc] init];
    [UDPlugin(UDXCTestSources) addTestsOfSources:sources toCatalog:catalog];
    catalog.runners = @[ [[UDPlugin(UDCFamilyTestRunner) alloc] initWithProject:self.project] ];
    return catalog;
}

/// The tests in a project's sources: XCTestCase's subclasses (a class of the
/// project's between, too), their test methods with where each is; not a
/// test's helper, nor a class that isn't one.
- (void)testTheTestsAreFoundInTheSources {
    NSDictionary *sources = @{
        @"/p/Tests/Base.h": @"@interface BaseCase : XCTestCase\n@end\n",
        @"/p/Tests/Base.m": @"@implementation BaseCase\n- (void)setUp {}\n- (void)helper {}\n@end\n",
        @"/p/Tests/CalcTests.m": @"#import \"Base.h\"\n@interface CalcTests : BaseCase\n@end\n\n@implementation CalcTests\n\n"
                               @"- (void)testAdds {\n}\n\n- (void) testDivides\n{\n}\n- (void)testWith:(int)x {}\n- (int)testValue { return 0; }\n@end\n",
        @"/p/Tests/Other.m": @"@interface Other : NSObject\n@end\n@implementation Other\n- (void)testNothing {}\n@end\n" };
    UDTestCatalog *catalog = [self catalogOfSources:sources];
    XCTAssertEqualObjects([catalog.suites valueForKey:@"name"], @[ @"CalcTests" ], @"BaseCase has no tests; Other is no test case");
    UDTestSuite *calc = [catalog suiteNamed:@"CalcTests"];
    XCTAssertEqualObjects([calc.tests valueForKey:@"name"], (@[ @"testAdds", @"testDivides" ]));
    XCTAssertEqualObjects(calc.path, @"/p/Tests/CalcTests.m");
    XCTAssertEqual(calc.line, 5);
    XCTAssertEqual([catalog testNamed:@"testDivides" inSuite:@"CalcTests"].line, 10);
    XCTAssertEqualObjects([catalog testNamed:@"testAdds" inSuite:@"CalcTests"].identifier, @"CalcTests.testAdds", @"xctest's filter");
    XCTAssertEqualObjects([catalog pathOfFile:@"CalcTests.m"], @"/p/Tests/CalcTests.m");
    XCTAssertEqualObjects([catalog pathOfFile:@"Tests/CalcTests.m"], @"/p/Tests/CalcTests.m");
    XCTAssertNil([catalog pathOfFile:@"Missing.m"]);
}

/// A run's output, GNUstep's xctest's and Apple's: each test marked as it
/// went, a failure where it was said.
- (void)testARunsOutputMarksTheTests {
    UDTestCatalog *catalog = [self catalogOfSources:@{
        @"/p/T.m": @"@interface CalcTests : XCTestCase\n@end\n@implementation CalcTests\n- (void)testAdds {}\n- (void)testDivides {}\n@end\n" }];
    UDTest *adds = [catalog testNamed:@"testAdds" inSuite:@"CalcTests"];
    UDTest *divides = [catalog testNamed:@"testDivides" inSuite:@"CalcTests"];
    XCTAssertNil([catalog readLine:@"2026-10-19 12:00:00.000 xctest[1:1] XCTest:   Running CalcTests"]);
    XCTAssertEqual(adds.status, UDTestStatusRunning);
    [catalog readLine:@"2026-10-19 12:00:00.001 xctest[1:1] XCTest:     -[CalcTests testAdds] PASSED"];
    UDTestFailure *failure = [catalog readLine:@"2026-10-19 12:00:00.002 xctest[1:1] XCTest: T.m:5: -[CalcTests testDivides]: "
                                               @"((1/2) equal to (0.5)) failed: (\"0\") is not equal to (\"0.5\")"];
    [catalog readLine:@"2026-10-19 12:00:00.003 xctest[1:1] XCTest:     -[CalcTests testDivides] FAILED"];
    XCTAssertEqual(adds.status, UDTestStatusPassed);
    XCTAssertEqual(divides.status, UDTestStatusFailed);
    XCTAssertEqual(failure.test, divides);
    XCTAssertEqualObjects(failure.file, @"T.m");
    XCTAssertEqual(failure.line, 5);
    XCTAssertTrue([failure.message hasPrefix:@"((1/2) equal to (0.5)) failed"], @"%@", failure.message);
    XCTAssertFalse(failure.compilerStyle);
    XCTAssertEqual(catalog.passedCount, 1u);
    XCTAssertEqual(catalog.failedCount, 1u);
    XCTAssertEqual([catalog suiteNamed:@"CalcTests"].status, UDTestStatusFailed);

    // Apple's (xcodebuild test, Xcode's xctest); a test the sources didn't have, added
    [catalog resetTests:nil];
    XCTAssertEqual(adds.status, UDTestStatusNotRun);
    [catalog readLine:@"Test Case '-[CalcTests testAdds]' started."];
    XCTAssertEqual(adds.status, UDTestStatusRunning);
    [catalog readLine:@"Test Case '-[CalcTests testAdds]' passed (0.001 seconds)."];
    failure = [catalog readLine:@"/p/T.m:5: error: -[CalcTests testDivides] : XCTAssertEqual failed: (\"0\") is not equal to (\"1\")"];
    [catalog readLine:@"Test Case '-[CalcTests testDivides]' failed (0.002 seconds)."];
    [catalog readLine:@"Test Case '-[Calc.MoreTests testNew]' passed (0.001 seconds)."];
    XCTAssertEqual(adds.status, UDTestStatusPassed);
    XCTAssertEqual(divides.status, UDTestStatusFailed);
    XCTAssertTrue(failure.compilerStyle, @"the build's issues have it already");
    XCTAssertEqualObjects(failure.file, @"/p/T.m");
    XCTAssertEqualObjects(failure.message, @"XCTAssertEqual failed: (\"0\") is not equal to (\"1\")");
    XCTAssertEqual([catalog testNamed:@"testNew" inSuite:@"MoreTests"].status, UDTestStatusPassed, @"Swift's Module.Suite");

    // xcodebuild's since Xcode 16: "Test case", and where it ran
    [catalog resetTests:nil];
    [catalog readLine:@"Test case '-[CalcTests testAdds]' passed on 'My Mac - Calculator (88892)' (0.001 seconds)"];
    [catalog readLine:@"Test case '-[CalcTests testDivides]' failed on 'My Mac - Calculator (88892)' (0.002 seconds)"];
    XCTAssertEqual(adds.status, UDTestStatusPassed);
    XCTAssertEqual(divides.status, UDTestStatusFailed);
}

/// A run of tests of several kinds: each runner runs its own, filtered to
/// those asked for; a suite no runner listed, the first that runs its kind;
/// the project's command only when no runner runs anything.
- (void)testEachRunnerRunsItsOwnTests {
    [self write:@"all:\n\ncheck:\n\t./run-tests\n" to:@"Makefile"];
    UDTestCatalog *catalog = self.project.testCatalog;
    XCTAssertEqualObjects([catalog commandRunningTests:nil], @"make check", @"nothing else runs them");
    XCTAssertNil([catalog commandRunningTests:@[]], @"none asked for");

    // a CTest runner's and a GoogleTest runner's, made by hand
    UDCTestRunner *ctest = [[UDPlugin(UDCTestRunner) alloc] initWithProject:self.project directory:[_folder stringByAppendingPathComponent:@"build"]];
    UDGoogleTestRunner *google = [[UDPlugin(UDGoogleTestRunner) alloc] initWithProject:self.project];
    UDTestSuite *calc = [catalog addSuiteNamed:@"Calc"];
    calc.kind = @"gtest";
    calc.executable = [_folder stringByAppendingPathComponent:@"build/calc_test"];
    UDTest *adds = [catalog addTest:@"Adds" toSuite:calc];
    UDTest *divides = [catalog addTest:@"Divides" toSuite:calc];
    catalog.runners = [@[ ctest, google ] arrayByAddingObjectsFromArray:catalog.runners];
    XCTAssertEqual([catalog runnerOfSuite:calc], google, @"its kind's runner");
    NSString *command = [catalog commandRunningTests:@[ divides ]];
    XCTAssertTrue([command hasSuffix:@"calc_test --gtest_filter=Calc.Divides )"], @"%@", command);
    XCTAssertFalse([command containsString:@"make check"], @"%@", command);
    UDTestDebugPlan *plan = [catalog debugPlanForTests:@[ adds, divides ] reason:NULL];
    XCTAssertEqualObjects(plan.configuration.arguments, @[ @"--gtest_filter=Calc.Adds:Calc.Divides" ]);
    XCTAssertEqualObjects(plan.buildCommand, @"make");
    NSString *reason = nil;
    XCTAssertNil([[catalog runners].lastObject debugPlanForTests:nil reason:&reason], @"the command's: not one by one");
    XCTAssertNotNil(reason);
    XCTAssertEqualObjects([UDTestRunner commandOfSteps:(@[ @"a", @"b" ])], @"( failed=0; a || failed=1; b || failed=1; exit $failed )");
}

/// How a project's tests run, as it says: a GNUstep XCTest bundle (by
/// xctest), a Makefile's check target, CMake's ctest, the settings' own.
- (void)testTheProjectSaysHowItsTestsRun {
    XCTAssertNil(self.project.testCommand, @"nothing says");
    [self write:@"all:\n\tcc -o hello hello.c\n\ncheck: all\n\t./hello --test\n" to:@"Makefile"];
    XCTAssertEqualObjects(self.project.testCommand, @"make check");
    [self write:@"{ \"test\": \"./run-tests.sh\" }" to:@".udcode/settings.json"];
    XCTAssertEqualObjects(self.project.testCommand, @"./run-tests.sh", @"the settings' own");
    [[NSFileManager defaultManager] removeItemAtPath:[_folder stringByAppendingPathComponent:@".udcode"] error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[_folder stringByAppendingPathComponent:@"Makefile"] error:NULL];
    [self write:@"project(x)\n" to:@"CMakeLists.txt"];
    XCTAssertEqualObjects(self.project.testCommand, @"ctest --test-dir build --output-on-failure");
    [self write:@"include $(GNUSTEP_MAKEFILES)/common.make\nAPP_NAME = Calc\n" to:@"Calc/GNUmakefile"];
    [self write:@"include $(GNUSTEP_MAKEFILES)/common.make\nBUNDLE_NAME = CalcTests\nADDITIONAL_LDFLAGS += -lXCTest\n"
             to:@"CalcTests/GNUmakefile"];
    [self write:@"include $(GNUSTEP_MAKEFILES)/common.make\nBUNDLE_NAME = Plugin\n" to:@"Plugin/GNUmakefile"];
#ifdef GNUSTEP
    UDProject *project = self.project;      // its build system's, kept
    UDGNUstepMakeBuildSystem *gnustep = (UDGNUstepMakeBuildSystem *)project.buildSystem;
    XCTAssertEqualObjects(gnustep.name, @"GNUstep make");
    XCTAssertEqualObjects(gnustep.testBundles, @[ @"CalcTests/CalcTests.bundle" ], @"an XCTest bundle; not another bundle");
    XCTAssertTrue([[project.testCatalog.runners.firstObject class] isEqual:UDPluginClass(@"UDXCTestBundleRunner")], @"run by xctest");
#else
    XCTAssertEqualObjects(self.project.buildSystem.name, @"CMake", @"a GNUmakefile is GNUstep's");
#endif
}

/// clangd's fallbackFlags, where a project says nothing of its own
/// (compile_commands.json): GNUstep's headers, as the system has their
/// folders (on Windows not MSYS2's /c/GNUstep), so Foundation.h is found.
- (void)testClangdFindsGNUstepsHeaders {
#ifdef GNUSTEP
    NSArray<NSString *> *flags = [UDPluginClass(@"UDCFamilyPlugin") fallbackCompileFlagsForProject:self.project];
    BOOL found = NO;
    for (NSString *flag in flags) {
        if (![flag hasPrefix:@"-I"]) continue;
        NSString *folder = [flag substringFromIndex:2];
        found = found || [[NSFileManager defaultManager] fileExistsAtPath:[folder stringByAppendingPathComponent:@"Foundation/Foundation.h"]];
    }
    XCTAssertTrue(found, @"%@", flags);
    XCTAssertFalse([flags containsObject:@"-MMD"], @"make's, not an index's");
#endif
}

/// A GNUstep project's compile commands, as make's dry run says them: each
/// file's own folder and flags (continued lines joined, the folders make
/// enters followed), a file compiled again for a test bundle the first
/// time's, what makes dependency files left out.
- (void)testMakesDryRunIsEachFilesCompileCommand {
#ifdef GNUSTEP
    // the folders as the system has them, which every shell's are too
    NSString *calc = self.project.folderURL.path;
    NSString *app = [calc stringByAppendingPathComponent:@"App"], *tests = [calc stringByAppendingPathComponent:@"Tests"];
    NSString *output = [NSString stringWithFormat:
                        @"make: Entering directory '%@'\n"
                        @"make[1]: Entering directory '%@'\n"
                        @"clang main.m -c \\\n"
                        @"      -MMD -MP -Iinclude -fobjc-arc -include Compat.h \\\n"
                        @"       -o obj/App.obj/main.m.o\n"
                        @"clang -Wl,--enable-auto-import -o obj/App obj/App.obj/main.m.o\n"
                        @"make[1]: Leaving directory '%@'\n"
                        @"make[1]: Entering directory '%@'\n"
                        @"clang ../App/main.m -c -DTESTING -o obj/Tests.obj/main.m.o\n"
                        @"clang Tests.m -c -fblocks -o obj/Tests.obj/Tests.m.o\n"
                        @"make[1]: Leaving directory '%@'\n", calc, app, app, tests, tests];
    Class gnustep = UDPluginClass(@"UDGNUstepMakeBuildSystem");
    NSDictionary *commands = [gnustep compileCommandsInDryRun:output folder:calc shell:nil];
    NSString *main = [app stringByAppendingPathComponent:@"main.m"], *testsFile = [tests stringByAppendingPathComponent:@"Tests.m"];
    XCTAssertEqualObjects([NSSet setWithArray:commands.allKeys], ([NSSet setWithObjects:main, testsFile, nil]));
    XCTAssertEqualObjects(commands[main][@"workingDirectory"], app);
    NSArray *expected = [@[ @"clang", @"main.m", @"-c", @"-Iinclude", @"-fobjc-arc", @"-include", @"Compat.h", @"-o", @"obj/App.obj/main.m.o" ]
                         arrayByAddingObjectsFromArray:UDShellCompilerFlags(nil)];
    XCTAssertEqualObjects(commands[main][@"compilationCommand"], expected, @"the first, without -MMD -MP");
    XCTAssertEqualObjects(commands[testsFile][@"workingDirectory"], tests);
#endif
}

/// clangd told how make compiles each file of a GNUstep project (its
/// -fobjc-arc, which no fallback flag knows), from make's own dry run.
- (void)testClangdIsToldHowMakeCompilesEachFile {
#ifdef GNUSTEP
    [self write:@"include $(GNUSTEP_MAKEFILES)/common.make\nTOOL_NAME = calc\ncalc_OBJC_FILES = main.m\n"
                @"ADDITIONAL_OBJCFLAGS += -fobjc-arc\ninclude $(GNUSTEP_MAKEFILES)/tool.make\n" to:@"GNUmakefile"];
    [self write:@"int main(void) { return 0; }\n" to:@"main.m"];
    UDProject *project = [[UDProject alloc] initWithFolderURL:[NSURL fileURLWithPath:self.folder]];
    NSDictionary *options = [project initializationOptionsForLanguageServer:@[ @"clangd" ]];
    NSString *main = [project.folderURL.path stringByAppendingPathComponent:@"main.m"].stringByStandardizingPath;
    NSDictionary *command = options[@"compilationDatabaseChanges"][main];
    XCTAssertEqualObjects(command[@"workingDirectory"], project.folderURL.path.stringByStandardizingPath, @"%@", options);
    XCTAssertTrue([command[@"compilationCommand"] containsObject:@"-fobjc-arc"], @"%@", command);
    XCTAssertNotNil(options[@"fallbackFlags"], @"for the files make does not compile (headers)");
#endif
}

/// A GNUstep project's tests, written as UDCalc's are (an XCTest bundle in a
/// folder of its own): Debug › Test builds and runs them, the Test navigator
/// marks each, a failure is an issue at its line; one test runs alone.
- (void)testTestsRunFromTheWindow {
#ifdef GNUSTEP
    [self write:@"include $(GNUSTEP_MAKEFILES)/common.make\nTOOL_NAME = calc\ncalc_OBJC_FILES = main.m\n"
                @"include $(GNUSTEP_MAKEFILES)/tool.make\n" to:@"Calc/GNUmakefile"];
    [self write:@"int main(void) { return 0; }\n" to:@"Calc/main.m"];
    [self write:@"include $(GNUSTEP_MAKEFILES)/common.make\nBUNDLE_NAME = CalcTests\nCalcTests_OBJC_FILES = CalcTests.m\n"
                @"CalcTests_BUNDLE_LIBS += -lXCTest\ninclude $(GNUSTEP_MAKEFILES)/bundle.make\n" to:@"CalcTests/GNUmakefile"];
    [self write:@"#import <XCTest/XCTest.h>\n"
                @"@interface CalcTests : XCTestCase\n@end\n\n"
                @"@implementation CalcTests\n\n"
                @"- (void)testAdds {\n    XCTAssertEqual(1 + 1, 2);\n}\n\n"
                @"- (void)testDivides {\n    XCTAssertEqual(1 / 2, 1, @\"integers\");\n}\n\n"
                @"@end\n" to:@"CalcTests/CalcTests.m"];
#else
    // Apple's XCTest's output, from a Makefile's check target
    [self write:@"all:\n\ncheck:\n"
                @"\t@echo \"Test Case '-[CalcTests testAdds]' started.\"\n"
                @"\t@echo \"Test Case '-[CalcTests testAdds]' passed (0.001 seconds).\"\n"
                @"\t@echo \"$(CURDIR)/CalcTests/CalcTests.m:12: error: -[CalcTests testDivides] : integers\"\n"
                @"\t@echo \"Test Case '-[CalcTests testDivides]' failed (0.001 seconds).\"\n"
                @"\t@false\n" to:@"Makefile"];
    [self write:@"#import <XCTest/XCTest.h>\n@interface CalcTests : XCTestCase\n@end\n\n@implementation CalcTests\n\n"
                @"- (void)testAdds {\n    XCTAssertEqual(1 + 1, 2);\n}\n\n- (void)testDivides {\n    XCTAssertEqual(1 / 2, 1, @\"integers\");\n}\n\n@end\n"
             to:@"CalcTests/CalcTests.m"];
#endif
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [controller showTestNavigator:nil];
    UDTestCatalog *catalog = controller.testCatalog;
    XCTAssertEqualObjects([catalog.allTests valueForKey:@"name"], (@[ @"testAdds", @"testDivides" ]), @"found before any run");
    XCTAssertEqualObjects(controller.testNavigator.summaryLabel.stringValue, @"2 tests");

    [controller test:nil];
    XCTAssertEqualObjects(controller.activityText, ([NSString stringWithFormat:@"%@ | Testing…", controller.project.name]));
    UDRunUntil(!controller.buildRunner.running, 120);
    UDRunUntil(NO, 0.3);
    UDTest *adds = [catalog testNamed:@"testAdds" inSuite:@"CalcTests"];
    UDTest *divides = [catalog testNamed:@"testDivides" inSuite:@"CalcTests"];
    XCTAssertEqual(adds.status, UDTestStatusPassed, @"%@", controller.buildRunner.output);
    XCTAssertEqual(divides.status, UDTestStatusFailed, @"%@", controller.buildRunner.output);
    XCTAssertEqualObjects(controller.activityText, ([NSString stringWithFormat:@"%@ | Tests Failed | 1 failed, 1 passed", controller.project.name]));
    XCTAssertEqualObjects([controller.testNavigator textOfRow:1], @"✓ testAdds");
    XCTAssertEqualObjects([controller.testNavigator textOfRow:2], @"✗ testDivides");
    XCTAssertEqualObjects(controller.testNavigator.summaryLabel.stringValue, @"1 passed, 1 failed, of 2");
    // the failure, an issue of the test's file at its line
    NSString *file = [[_folder stringByAppendingPathComponent:@"CalcTests/CalcTests.m"] stringByStandardizingPath];
    UDDiagnosticItem *issue = controller.buildRunner.diagnostics[file].allDiagnostics.firstObject;
    XCTAssertEqual(issue.line, 12, @"%@", controller.buildRunner.diagnostics);
    XCTAssertEqual(issue.severity, UDDiagnosticSeverityError);
    XCTAssertTrue([issue.message containsString:@"integers"], @"%@", issue.message);

#ifdef GNUSTEP
    // one test, alone
    [controller runTests:@[ adds ] debugging:NO];
    UDRunUntil(!controller.buildRunner.running, 120);
    UDRunUntil(NO, 0.3);
    XCTAssertEqual(adds.status, UDTestStatusPassed);
    XCTAssertEqual(divides.status, UDTestStatusFailed, @"not run again: as the last run left it");
    XCTAssertFalse([controller.buildRunner.output containsString:@"testDivides"], @"%@", controller.buildRunner.output);
    XCTAssertEqualObjects(controller.activityText, ([NSString stringWithFormat:@"%@ | Tests Failed | 1 failed, 1 passed", controller.project.name]));

    // debugged: stopped at a breakpoint in the test
    if ([UDDebugger adapterCommandForDebugger:nil]) {
        [controller.breakpoints addBreakpointAtLine:12 inFile:file];
        [controller runTests:@[ divides ] debugging:YES];
        UDRunUntil(controller.debugSession.state == UDDebugSessionStateStopped && controller.debugSession.selectedFrame, 120);
        XCTAssertEqual(controller.debugSession.state, UDDebugSessionStateStopped, @"%@ %@", controller.buildRunner.output,
                       controller.debugSession.consoleText);
        XCTAssertEqual(controller.debugSession.selectedFrame.line, 12);
        [controller.debugSession continueExecution];
        UDRunUntil(controller.debugSession.state == UDDebugSessionStateEnded, 60);
        [controller.breakpoints removeAllBreakpoints];
    }
#endif
    [controller close];
    [workspace close];
}


/// CTest's and GoogleTest's output, as their runs print it.
- (void)testCTestsAndGoogleTestsOutputMarksTheirTests {
    UDTestCatalog *catalog = [self catalogOfSources:@{}];
    UDTestSuite *ctest = [catalog addSuiteNamed:@"CTest"];
    ctest.kind = @"ctest";
    UDTest *adds = [catalog addTest:@"adds" toSuite:ctest];
    UDTest *divides = [catalog addTest:@"divides" toSuite:ctest];
    XCTAssertEqualObjects(adds.identifier, @"adds", @"CTest's test, by its name");
    [catalog readLine:@"    Start 1: adds"];
    XCTAssertEqual(adds.status, UDTestStatusRunning);
    [catalog readLine:@"1/2 Test #1: adds .............................   Passed    0.00 sec"];
    [catalog readLine:@"2/2 Test #2: divides ..........................***Failed    0.01 sec"];
    XCTAssertEqual(adds.status, UDTestStatusPassed);
    XCTAssertEqual(divides.status, UDTestStatusFailed);

    UDTestSuite *calc = [catalog addSuiteNamed:@"Calc"];
    calc.kind = @"gtest";
    UDTest *gadds = [catalog addTest:@"Adds" toSuite:calc];
    UDTest *gdivides = [catalog addTest:@"Divides" toSuite:calc];
    XCTAssertEqualObjects(gadds.identifier, @"Calc.Adds", @"--gtest_filter's");
    [catalog readLine:@"[ RUN      ] Calc.Adds"];
    XCTAssertEqual(gadds.status, UDTestStatusRunning);
    [catalog readLine:@"[       OK ] Calc.Adds (0 ms)"];
    XCTAssertNil([catalog readLine:@"[ RUN      ] Calc.Divides"]);
    XCTAssertNil([catalog readLine:@"/src/calc_test.cc:12: Failure"]);
    XCTAssertNil([catalog readLine:@"Expected equality of these values:"]);
    XCTAssertNil([catalog readLine:@"  1 / 2"]);
    UDTestFailure *failure = [catalog readLine:@"[  FAILED  ] Calc.Divides (0 ms)"];
    XCTAssertEqual(gadds.status, UDTestStatusPassed);
    XCTAssertEqual(gdivides.status, UDTestStatusFailed);
    XCTAssertEqual(failure.test, gdivides);
    XCTAssertEqualObjects(failure.file, @"/src/calc_test.cc");
    XCTAssertEqual(failure.line, 12);
    XCTAssertEqualObjects(failure.message, @"Expected equality of these values: 1 / 2");
    XCTAssertEqualObjects(gdivides.failures, @[ @"Expected equality of these values: 1 / 2" ]);
    [catalog readLine:@"[  FAILED  ] Calc.Divides"];
    XCTAssertEqual(gdivides.status, UDTestStatusFailed, @"the summary's line, again");
}

/// What the runners and the tools say, as UDCode reads it: TestMate's glob,
/// GoogleTest's listing, CTest's JSON, xcodebuild's build settings, TestMate's
/// debug template.
- (void)testTheRunnersAreReadAsTheySay {
    NSString *glob = @"{build,Build,BUILD,out,Out,OUT}/**/*{test,Test,TEST}*";
    XCTAssertTrue([UDPlugin(UDGoogleTestRunner) path:@"build/calc_test" matchesGlob:glob]);
    XCTAssertTrue([UDPlugin(UDGoogleTestRunner) path:@"out/tests/bin/UnitTests" matchesGlob:glob]);
    XCTAssertFalse([UDPlugin(UDGoogleTestRunner) path:@"src/calc_test.cc" matchesGlob:glob]);
    XCTAssertFalse([UDPlugin(UDGoogleTestRunner) path:@"build/calc" matchesGlob:glob]);
    XCTAssertTrue([UDPlugin(UDGoogleTestRunner) path:@"bin/a.test" matchesGlob:@"bin/*.test"]);

    XCTAssertEqualObjects([UDPlugin(UDGoogleTestRunner) testsOfListing:@"Calc.\n  Adds\n  Divides\nParam/Squares.\n  Of/0  # GetParam() = 1\n"],
                          (@[ @"Calc.Adds", @"Calc.Divides", @"Param/Squares.Of/0" ]));

    NSString *json = @"{ \"kind\": \"ctestInfo\", \"tests\": [ { \"name\": \"adds\", \"command\": [ \"/b/calc_test\", \"adds\" ], "
                     @"\"properties\": [ { \"name\": \"WORKING_DIRECTORY\", \"value\": \"/b\" } ] }, { \"name\": \"divides\" } ] }";
    NSArray *ctests = [UDPlugin(UDCTestRunner) testsOfJSON:json];
    XCTAssertEqual(ctests.count, 2u);
    XCTAssertEqualObjects(ctests[0][@"command"], (@[ @"/b/calc_test", @"adds" ]));
    XCTAssertEqualObjects(ctests[0][@"directory"], @"/b");

    NSArray *targets = [UDPlugin(UDXcodeBuildSystem) targetsOfBuildSettings:@"Build settings for action build and target Calculator:\n"
                                                          @"    PRODUCT_TYPE = com.apple.product-type.application\n\n"
                                                          @"Build settings for action build and target CalculatorTests:\n"
                                                          @"    PRODUCT_TYPE = com.apple.product-type.bundle.unit-test\n"
                                                          @"    TEST_HOST = /b/Calculator.app/Contents/MacOS/Calculator\n"];
    XCTAssertEqualObjects([targets valueForKey:@"TARGET_NAME"], (@[ @"Calculator", @"CalculatorTests" ]));
    XCTAssertEqualObjects(targets[1][@"TEST_HOST"], @"/b/Calculator.app/Contents/MacOS/Calculator");

    // TestMate's debug template, with its placeholders, read as launch.json's are
    [self write:@"{ // TestMate's\n \"testMate.cpp.debug.configTemplate\": { \"type\": \"cppdbg\", \"MIMode\": \"gdb\", "
                @"\"program\": \"${exec}\", \"args\": \"${argsArray}\", \"cwd\": \"${cwd}\" },\n"
                @" \"testMate.cpp.test.executables\": \"bin/*.test\", \"cmake.buildDirectory\": \"${workspaceFolder}/out\" }\n"
             to:@".vscode/settings.json"];
    UDTasks *tasks = [[UDTasks alloc] initWithFolderURL:[NSURL fileURLWithPath:_folder] currentFileURL:nil];
    // an absolute folder as the system writes one (/b is not, on Windows)
    NSString *b = [_folder stringByAppendingPathComponent:@"b"];
    NSString *calcTest = [b stringByAppendingPathComponent:@"calc_test"];
    UDLaunchConfiguration *debug = [tasks testDebugConfigurationForExecutable:calcTest arguments:@[ @"--gtest_filter=Calc.Adds" ]
                                                                    directory:b];
    XCTAssertEqualObjects(debug.program, calcTest);
    XCTAssertEqualObjects(debug.arguments, @[ @"--gtest_filter=Calc.Adds" ]);
    XCTAssertEqualObjects(debug.directory, b);
    XCTAssertEqualObjects(debug.debugger, @"gdb", @"cppdbg with gdb");
    XCTAssertEqualObjects([[[UDPlugin(UDGoogleTestRunner) alloc] initWithProject:self.project] globs], @[ @"bin/*.test" ], @"TestMate's own setting");
    XCTAssertEqualObjects([[[UDPlugin(UDCMakeBuildSystem) alloc] initWithProject:self.project] buildDirectory],
                          [_folder stringByAppendingPathComponent:@"out"], @"CMake Tools' cmake.buildDirectory");
}

/// A CMake project's tests, as CTest has them (add_test): listed, run,
/// one run alone, one debugged to a breakpoint in what it runs.
- (void)testCTestsRunAndDebugFromTheWindow {
    if (![UDToolLocator pathOfTool:@"cmake"] || ![UDToolLocator pathOfTool:@"ctest"]) {
        NSLog(@"UDProjectTests: no cmake here; its case checks nothing");
        return;
    }
    [self write:@"cmake_minimum_required(VERSION 3.14)\nproject(calc C)\nenable_testing()\n"
                @"add_executable(calc_test calc_test.c)\n"
                @"add_test(NAME adds COMMAND calc_test adds)\nadd_test(NAME divides COMMAND calc_test divides)\n" to:@"CMakeLists.txt"];
    [self write:@"#include <stdio.h>\n#include <string.h>\n"
                @"int main(int argc, char **argv) {\n"
                @"    int result = 1 / 2;\n"
                @"    if (argc > 1 && strcmp(argv[1], \"divides\") == 0) {\n"
                @"        printf(\"divides: %d\\n\", result);\n"
                @"        return result == 1 ? 0 : 1;\n"
                @"    }\n"
                @"    return 1 + 1 == 2 ? 0 : 1;\n"
                @"}\n" to:@"calc_test.c"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    [controller build:nil];
    UDRunUntil(!controller.buildRunner.running, 120);
    XCTAssertTrue(controller.buildRunner.succeeded, @"%@", controller.buildRunner.output);
    [controller reloadTests];
    UDTestCatalog *catalog = controller.testCatalog;
    UDTest *adds = [catalog testNamed:@"adds" inSuite:@"CTest"];
    UDTest *divides = [catalog testNamed:@"divides" inSuite:@"CTest"];
    XCTAssertNotNil(adds, @"%@", [catalog.allTests valueForKey:@"identifier"]);
    XCTAssertEqualObjects(divides.command.lastObject, @"divides");

    [controller test:nil];
    UDRunUntil(!controller.buildRunner.running, 120);
    XCTAssertEqual(adds.status, UDTestStatusPassed, @"%@", controller.buildRunner.output);
    XCTAssertEqual(divides.status, UDTestStatusFailed, @"%@", controller.buildRunner.output);

    [controller runTests:@[ adds ] debugging:NO];
    UDRunUntil(!controller.buildRunner.running, 120);
    XCTAssertEqual(adds.status, UDTestStatusPassed);
    XCTAssertFalse([controller.buildRunner.output containsString:@"divides"], @"alone: %@", controller.buildRunner.output);

    if ([UDDebugger adapterCommandForDebugger:nil]) {
        NSString *source = [_folder stringByAppendingPathComponent:@"calc_test.c"];
        [controller.breakpoints addBreakpointAtLine:6 inFile:source];
        [controller runTests:@[ divides ] debugging:YES];
        UDRunUntil(controller.debugSession.state == UDDebugSessionStateStopped && controller.debugSession.selectedFrame, 120);
        XCTAssertEqual(controller.debugSession.selectedFrame.line, 6, @"%@ %@", controller.buildRunner.output,
                       controller.debugSession.consoleText);
        [controller.debugSession continueExecution];
        UDRunUntil(controller.debugSession.state == UDDebugSessionStateEnded, 60);
        [controller.breakpoints removeAllBreakpoints];
    }
    [controller close];
    [workspace close];
}

/// An Xcode project's tests (UD_TEST_XCODE_PROJECT: a copy of one, as
/// UDCalc's): its scheme's test target, xcodebuild test, one test alone.
- (void)testAnXcodeProjectsTestsRun {
    NSString *folder = NSProcessInfo.processInfo.environment[@"UD_TEST_XCODE_PROJECT"];
#ifdef __APPLE__
    if (!folder.length) {
        NSLog(@"UDProjectTests: no UD_TEST_XCODE_PROJECT; its case checks nothing");
        return;
    }
    UDProject *project = [[UDProject alloc] initWithFolderURL:[NSURL fileURLWithPath:folder]];
    UDXcodeBuildSystem *xcode = (UDXcodeBuildSystem *)project.buildSystem;
    XCTAssertEqualObjects(xcode.name, @"Xcode");
    XCTAssertNotNil(xcode.scheme);
    XCTAssertTrue(xcode.testTargets.count > 0, @"%@", xcode.testTargets);
    XCTAssertTrue([project.testCommand containsString:@" -scheme "], @"%@", project.testCommand);

    // from the window: all of them, one alone, one debugged
    AppDelegate *delegate = [[AppDelegate alloc] init];
    UDWorkspace *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:folder]];
    UDDocumentWindowController *controller = workspace.windowControllers.firstObject;
    UDTestCatalog *catalog = controller.testCatalog;
    XCTAssertTrue(catalog.allTests.count > 0);
    [controller test:nil];
    UDRunUntil(!controller.buildRunner.running, 600);
    XCTAssertTrue(catalog.passedCount + catalog.failedCount > 0, @"%@", controller.buildRunner.output);
    XCTAssertEqual(catalog.passedCount + catalog.failedCount, catalog.allTests.count, @"each marked: %@", controller.activityText);
    UDTest *one = catalog.allTests.firstObject;
    UDTest *other = catalog.allTests.lastObject;
    [catalog resetTests:nil];
    [controller runTests:@[ one ] debugging:NO];
    UDRunUntil(!controller.buildRunner.running, 600);
    XCTAssertNotEqual(one.status, UDTestStatusNotRun, @"%@", controller.buildRunner.output);
    XCTAssertEqual(other.status, UDTestStatusNotRun, @"alone");
    if ([UDDebugger adapterCommandForDebugger:@"lldb"] && one.path) {
        [controller.breakpoints addBreakpointAtLine:one.line + 1 inFile:one.path];
        [controller runTests:@[ one ] debugging:YES];
        // the breakpoint's stop (not the attach's, in dyld)
        UDRunUntil(controller.debugSession.state == UDDebugSessionStateStopped && controller.debugSession.selectedFrame.path, 300);
        XCTAssertEqual(controller.debugSession.state, UDDebugSessionStateStopped, @"%@ %@", controller.buildRunner.output,
                       controller.debugSession.consoleText);
        XCTAssertEqualObjects(controller.debugSession.selectedFrame.path.lastPathComponent, one.path.lastPathComponent,
                              @"%@ in %@", controller.debugSession.selectedFrame.name, controller.debugSession.consoleText);
        [controller.debugSession continueExecution];
        UDRunUntil(!controller.buildRunner.running, 300);
        [controller.breakpoints removeAllBreakpoints];
    }
    [controller close];
    [workspace close];
#else
    (void)folder;
#endif
}

@end
