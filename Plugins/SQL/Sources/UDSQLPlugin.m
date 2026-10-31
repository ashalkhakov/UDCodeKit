/*---------------------------------------------------------------------------------------------
 *  UDSQLPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLPlugin.h"
#import "UDSQLDatabases.h"
#import "UDSQLNavigatorViewController.h"

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
        [_windows setObject:databases forKey:workbench];
    }
    return databases;
}

- (NSViewController *)navigatorViewControllerForWorkbench:(id<UDWorkbench>)workbench {
    return [self _databasesOf:workbench].navigator;
}

/// A database's cylinder, as the navigator's segment shows it.
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

@end
