/*---------------------------------------------------------------------------------------------
 *  UDSQLPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLPlugin.h"
#import "UDSQLDatabases.h"
#import "UDSQLNavigatorViewController.h"
#import "UDSQLExampleViewController.h"

@implementation UDSQLPlugin {
    /// Each window's databases.
    NSMapTable<id, UDSQLDatabases *> *_windows;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
    _windows = [NSMapTable weakToStrongObjectsMapTable];
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    _windows = nil;
}

- (const void *)languageFuncForIdentifier:(NSString *)identifier {
    return NULL;
}

- (UDSQLDatabases *)_databasesOf:(id<UDWorkbench>)workbench {
    if (!_windows) _windows = [NSMapTable weakToStrongObjectsMapTable];
    UDSQLDatabases *databases = [_windows objectForKey:workbench];
    if (!databases) {
        databases = [[UDSQLDatabases alloc] initWithWorkbench:workbench];
        databases.extension = self;
        [_windows setObject:databases forKey:workbench];
    }
    return databases;
}

- (NSViewController *)navigatorViewControllerForWorkbench:(id<UDWorkbench>)workbench {
    return [self _databasesOf:workbench].navigator;
}

/// A database's cylinder, as the navigator's segment shows it.
/// The bottom area's Results: a grid.
- (NSImage *)bottomAreaImage {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
    [image lockFocus];
    [[NSColor colorWithCalibratedWhite:0.3 alpha:1] setStroke];
    NSBezierPath *grid = [NSBezierPath bezierPathWithRect:NSMakeRect(2.5, 3.5, 11, 9)];
    for (CGFloat y = 6.5; y < 12; y += 3) {
        [grid moveToPoint:NSMakePoint(2.5, y)];
        [grid lineToPoint:NSMakePoint(13.5, y)];
    }
    [grid moveToPoint:NSMakePoint(6.5, 3.5)];
    [grid lineToPoint:NSMakePoint(6.5, 12.5)];
    grid.lineWidth = 1;
    [grid stroke];
    [image unlockFocus];
    image.template = YES;
    return image;
}

- (NSImage *)navigatorImage {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
    [image lockFocus];
    [[NSColor colorWithCalibratedWhite:0.3 alpha:1] setStroke];
    NSBezierPath *body = [NSBezierPath bezierPath];
    body.lineWidth = 1.2;
    [body moveToPoint:NSMakePoint(3, 12)];
    [body lineToPoint:NSMakePoint(3, 4)];
    [body appendBezierPathWithArcFromPoint:NSMakePoint(3, 1.5) toPoint:NSMakePoint(8, 1.5) radius:3];
    [body lineToPoint:NSMakePoint(8, 1.5)];
    [body appendBezierPathWithArcFromPoint:NSMakePoint(13, 1.5) toPoint:NSMakePoint(13, 4) radius:3];
    [body lineToPoint:NSMakePoint(13, 12)];
    [body stroke];
    NSBezierPath *top = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(3, 10, 10, 4)];
    top.lineWidth = 1.2;
    [top stroke];
    NSBezierPath *middle = [NSBezierPath bezierPath];
    middle.lineWidth = 1.0;
    [middle appendBezierPathWithArcWithCenter:NSMakePoint(8, 9) radius:5 startAngle:200 endAngle:340];
    [middle stroke];
    [image unlockFocus];
    [image setTemplate:YES];
    return image;
}

- (NSArray<NSMenuItem *> *)editorMenuItemsForWorkbench:(id<UDWorkbench>)workbench {
    return [[self _databasesOf:workbench].navigator editorMenuItems];
}

/// A SQLite file (a Core Data store's): its database opened, not its bytes.
- (BOOL)workbench:(id<UDWorkbench>)workbench openURL:(NSURL *)url {
    if (!url.isFileURL) return NO;
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:url.path];
    NSData *head = [file readDataOfLength:16];
    [file closeFile];
    if (head.length < 16 || memcmp(head.bytes, "SQLite format 3\0", 16) != 0) return NO;
    [[self _databasesOf:workbench] openDatabaseFile:url];
    return YES;
}

/// A query by example's document (its mode's): edited in the QbE editor, as
/// VS Code's custom text editors are; its text still shown as text.
- (NSViewController *)workbench:(id<UDWorkbench>)workbench editorForDocument:(UDCodeDocument *)document {
    if (![document.languageMode.identifier isEqualToString:@"qbe"]) return nil;
    return [[UDSQLExampleViewController alloc] initWithDatabases:[self _databasesOf:workbench] document:document];
}

@end
