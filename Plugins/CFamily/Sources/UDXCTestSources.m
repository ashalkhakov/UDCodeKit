/*---------------------------------------------------------------------------------------------
 *  UDXCTestSources.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXCTestSources.h"
#import "UDCFamilyTestOutput.h"
#import <objc/runtime.h>

static char UDSourcesReadKey;

@implementation UDXCTestSources

+ (NSArray<NSString *> *)sourceFilesOfProject:(UDProject *)project {
    NSString *folder = project.folderURL.path;
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:folder];
    NSSet *skipped = [NSSet setWithObjects:@"build", @"obj", @"DerivedData", @"node_modules", nil];
    for (NSString *path in enumerator) {
        if (files.count >= 20000) break;
        BOOL hidden = NO;
        for (NSString *component in path.pathComponents) hidden = hidden || [component hasPrefix:@"."] || [skipped containsObject:component];
        if (hidden) continue;
        if ([@[ @"m", @"mm", @"h" ] containsObject:path.pathExtension]) [files addObject:[folder stringByAppendingPathComponent:path]];
    }
    return files;
}

+ (void)addTestsOfProject:(UDProject *)project toCatalog:(UDTestCatalog *)catalog {
    if (objc_getAssociatedObject(catalog, &UDSourcesReadKey)) return;
    objc_setAssociatedObject(catalog, &UDSourcesReadKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self addTestsInFiles:[self sourceFilesOfProject:project] toCatalog:catalog];
}

+ (void)addTestsInFiles:(NSArray<NSString *> *)paths toCatalog:(UDTestCatalog *)catalog {
    NSMutableDictionary *sources = [NSMutableDictionary dictionary];
    for (NSString *path in paths) {
        if (![@[ @"m", @"mm" ] containsObject:path.pathExtension]) continue;
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        if (text && [text rangeOfString:@"@implementation"].location != NSNotFound) sources[path] = text;
    }
    [self addTestsOfSources:sources toCatalog:catalog];
}

/// The identifier at the start of @a text (letters, digits, underscores).
static NSString *UDIdentifierAt(NSString *text) {
    NSMutableCharacterSet *identifier = [NSMutableCharacterSet alphanumericCharacterSet];
    [identifier addCharactersInString:@"_"];
    NSUInteger end = 0;
    while (end < text.length && [identifier characterIsMember:[text characterAtIndex:end]]) end++;
    return [text substringToIndex:end];
}

+ (void)addTestsOfSources:(NSDictionary<NSString *, NSString *> *)sources toCatalog:(UDTestCatalog *)catalog {
    NSArray<NSString *> *paths = [sources.allKeys sortedArrayUsingSelector:@selector(compare:)];
    [catalog addSourcePaths:paths];
    // what each class inherits, and where each is implemented with its test methods
    NSMutableDictionary<NSString *, NSString *> *superclasses = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSArray *> *implementations = [NSMutableDictionary dictionary];   // class → [path, line, [[name, line]]]
    NSCharacterSet *spaces = [NSCharacterSet whitespaceCharacterSet];
    for (NSString *path in paths) {
        NSArray<NSString *> *lines = [sources[path] componentsSeparatedByString:@"\n"];
        NSString *implementing = nil;
        NSInteger implementingLine = 0;
        NSMutableArray *tests = nil;
        for (NSUInteger i = 0; i < lines.count; i++) {
            NSString *line = [lines[i] stringByTrimmingCharactersInSet:spaces];
            if ([line hasPrefix:@"@interface "]) {
                NSString *rest = [line substringFromIndex:11];
                NSString *name = UDIdentifierAt(rest);
                NSRange colon = [rest rangeOfString:@":"];
                if (name.length && colon.location != NSNotFound && colon.location < [rest rangeOfString:@"("].location) {
                    NSString *superclass = UDIdentifierAt([[rest substringFromIndex:NSMaxRange(colon)] stringByTrimmingCharactersInSet:spaces]);
                    if (superclass.length) superclasses[name] = superclass;
                }
            } else if ([line hasPrefix:@"@implementation "]) {
                implementing = UDIdentifierAt([line substringFromIndex:16]);
                implementingLine = (NSInteger)i + 1;
                tests = [NSMutableArray array];
            } else if ([line hasPrefix:@"@end"] && implementing) {
                if (tests.count) implementations[implementing] = @[ path, @(implementingLine), tests ];
                implementing = nil;
            } else if (implementing && [line hasPrefix:@"-"]) {
                // - (void)testSomething {   (no arguments)
                NSString *method = [[line substringFromIndex:1] stringByTrimmingCharactersInSet:spaces];
                if (![method hasPrefix:@"(void)"]) continue;
                method = [[method substringFromIndex:6] stringByTrimmingCharactersInSet:spaces];
                NSString *name = UDIdentifierAt(method);
                NSString *after = [[method substringFromIndex:name.length] stringByTrimmingCharactersInSet:spaces];
                if ([name hasPrefix:@"test"] && ![after hasPrefix:@":"]) [tests addObject:@[ name, @((NSInteger)i + 1) ]];
            }
        }
    }
    // a test case class: XCTestCase's, directly or through classes between
    for (NSString *name in [implementations.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *ancestor = superclasses[name];
        NSUInteger depth = 0;
        while (ancestor && ![ancestor isEqualToString:@"XCTestCase"] && depth++ < 16) ancestor = superclasses[ancestor];
        if (![ancestor isEqualToString:@"XCTestCase"]) continue;
        NSArray *implementation = implementations[name];
        UDTestSuite *suite = [catalog addSuiteNamed:name];
        suite.kind = UDTestKindXCTest;
        suite.path = implementation[0];
        suite.line = [implementation[1] integerValue];
        for (NSArray *test in implementation[2]) {
            UDTest *made = [catalog addTest:test[0] toSuite:suite];
            made.path = implementation[0];
            made.line = [test[1] integerValue];
        }
    }
}

@end
