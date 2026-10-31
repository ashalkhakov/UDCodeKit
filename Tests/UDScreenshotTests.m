//
//  UDScreenshotTests.m
//
//  The README's screenshots, made again: run with UD_SCREENSHOTS_DIR naming
//  a folder (skipped else). A small project — an Objective-C class, a Core
//  Data store and a query — opened in a window: the class with its jump
//  bar, then the query run against the store. Each window's content drawn
//  into a PNG, light (macOS's appearance set; GNUstep's is), as
//  <name>-macos.png or <name>-gnustep.png.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "AppDelegate.h"
#import "UDDocument.h"
#import "UDDocumentWindowController.h"
#import "UDSQLConnection.h"
#import "UDSQLDatabases.h"
#import "UDSQLNavigatorViewController.h"

static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}

@interface UDDocumentWindowController (ScreenshotTaking)
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
@end

@interface UDScreenshotTests : UDCodeTestCase
@end

@implementation UDScreenshotTests

/// @a window's content as a PNG in @a folder.
static void UDShoot(NSWindow *window, NSString *folder, NSString *name) {
    NSView *view = window.contentView;
    [view display];
#if defined(__APPLE__)
    NSBitmapImageRep *image = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
    NSString *platform = @"macos";
#else
    // gnustep-gui's cache of a view draws nothing: the view's own drawing, read back
    [view lockFocus];
    NSBitmapImageRep *image = [[NSBitmapImageRep alloc] initWithFocusedViewRect:view.bounds];
    [view unlockFocus];
    NSString *platform = @"gnustep";
#endif
#if defined(__APPLE__)
    NSData *png = [image representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
#else
    NSData *png = [image representationUsingType:NSPNGFileType properties:@{}];
#endif
    [png writeToFile:[folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.png", name, platform]] atomically:YES];
}

static void UDWrite(NSString *text, NSString *path) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)testTheREADMEsScreenshots {
    NSString *output = [[NSProcessInfo processInfo] environment][@"UD_SCREENSHOTS_DIR"];
    if (!output.length) return;     // made only when asked for
#if defined(__APPLE__)
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
#endif
    NSString *folder = UDRealPath([NSTemporaryDirectory() stringByAppendingPathComponent:@"Contacts"]);
    [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];
    UDWrite(@"#import <Foundation/Foundation.h>\n\n@interface Person : NSObject\n@property (nonatomic, copy) NSString *name;\n"
             "@property (nonatomic, strong) NSDate *born;\n- (instancetype)initWithName:(NSString *)name born:(NSDate *)born;\n"
             "- (NSInteger)ageOn:(NSDate *)date;\n@end\n",
            [folder stringByAppendingPathComponent:@"Sources/Model/Person.h"]);
    UDWrite(@"#import \"Person.h\"\n\n@implementation Person\n\n- (instancetype)initWithName:(NSString *)name born:(NSDate *)born {\n"
             "    self = [super init];\n    if (self) {\n        _name = [name copy];\n        _born = born;\n    }\n    return self;\n}\n\n"
             "/// Whole years from the day born to @a date.\n- (NSInteger)ageOn:(NSDate *)date {\n"
             "    NSCalendar *calendar = [NSCalendar currentCalendar];\n"
             "    return [calendar components:NSCalendarUnitYear fromDate:_born toDate:date options:0].year;\n}\n\n@end\n",
            [folder stringByAppendingPathComponent:@"Sources/Model/Person.m"]);
    UDWrite(@"# Contacts\n\nPeople, and when they were born.\n", [folder stringByAppendingPathComponent:@"README.md"]);
    UDWrite(@"-- the people born before a date\nSELECT ZNAME, ZBORN, Z_ENT\nFROM ZPERSON\n"
             "WHERE ZBORN < :before\nORDER BY ZBORN;\n\nSELECT count(*) FROM ZPERSON;\n",
            [folder stringByAppendingPathComponent:@"Queries/born.sql"]);
    // a Core Data store's tables: Person and Employee
    NSString *store = [folder stringByAppendingPathComponent:@"Contacts.sqlite"];
    [[NSData data] writeToFile:store atomically:YES];
    UDSQLConnection *connection = [UDPluginClass(@"UDSQLConnection") connectionToURL:[NSURL fileURLWithPath:store] password:nil error:NULL];
    for (NSString *sql in @[ @"CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER)",
                             @"INSERT INTO Z_PRIMARYKEY VALUES (1, 'Person', 0, 4), (2, 'Employee', 1, 0)",
                             @"CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID VARCHAR(255), Z_PLIST BLOB)",
                             @"CREATE TABLE ZPERSON (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZNAME VARCHAR, ZBORN TIMESTAMP)",
                             @"INSERT INTO ZPERSON VALUES (1, 1, 1, 'Ada Lovelace', -5900000000), (2, 2, 1, 'Grace Hopper', -2900000000), "
                              "(3, 1, 1, 'Alan Turing', -2800000000), (4, 2, 1, 'Edsger Dijkstra', -2200000000)" ]) {
        [connection execute:sql parameters:@[] maxRows:1 error:NULL];
    }
    [connection close];

#if !defined(__APPLE__)
    // the app's images (its toolbar's, its navigators'), found by name as in UDCode.app: xctest is no app
    NSString *resources = [[[[NSProcessInfo processInfo] environment][@"UD_PLUGINS_PATH"] stringByDeletingLastPathComponent]
                           stringByAppendingPathComponent:@"Resources"];
    for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:resources error:NULL]) {
        if (![file.pathExtension isEqualToString:@"png"]) continue;
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:[resources stringByAppendingPathComponent:file]];
        [image setName:file.stringByDeletingPathExtension];
    }
#endif
    // the window as it first opens: its debug area hidden
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UDPaneSplit UDCode Debug Area"];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    UDWorkspace *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:folder]];
    UDDocumentWindowController *controller = workspace.windowControllers.firstObject;
    [controller.window setFrame:NSMakeRect(80, 80, 1180, 720) display:YES];
    [controller showWindow:nil];
    [NSApp sendAction:NSSelectorFromString(@"showFilesNavigator:") to:controller from:nil];
    [controller.fileNavigator revealURL:[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"Sources/Model/Person.m"]]];
    [(id<UDWorkbench>)controller showURL:[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"Sources/Model/Person.m"]]];
    UDCodeEditorViewController *editor = (UDCodeEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    [editor.textView setSelectedRange:NSMakeRange([editor.textView.string rangeOfString:@"NSCalendar *"].location, 0)];
    UDRunUntil(NO, 2.0);
    UDShoot(controller.window, output, @"objc");

    // the query, against the store
    [controller openURLInNewTab:[NSURL fileURLWithPath:store]];
    [controller openURLInNewTab:[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"Queries/born.sql"]]];
    editor = (UDCodeEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    UDRunUntil(NO, 1.0);
    [controller.window makeFirstResponder:editor.textView];
    [editor.textView setSelectedRange:NSMakeRange([editor.textView.string rangeOfString:@"SELECT count"].location, 0)];
    id plugin = nil;
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if ([extension isKindOfClass:UDPluginClass(@"UDSQLPlugin")]) plugin = extension;
    }
    UDSQLDatabases *databases = [plugin performSelector:@selector(_databasesOf:) withObject:controller];
    [databases runStatement:nil];
    UDRunUntil(NO, 1.0);
    [editor.textView setSelectedRange:NSMakeRange([editor.textView.string rangeOfString:@"FROM ZPERSON\n"].location, 0)];
    // its parameter given as the sheet would
    [databases performSelector:@selector(_run:values:) withObject:@{
        @"statements": @[ [editor.textView.string componentsSeparatedByString:@";"].firstObject ],
        @"database": databases.databases.firstObject, @"document": controller.editorTabs.selectedItem.representedObject,
        @"results": editor.accessoryViewController } withObject:@{ @":before": @(-2500000000) }];
    UDRunUntil(NO, 2.0);
    UDShoot(controller.window, output, @"sql");
    [controller close];
    [workspace close];
}

@end
