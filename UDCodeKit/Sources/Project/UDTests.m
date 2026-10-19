/*---------------------------------------------------------------------------------------------
 *  UDTests.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTests.h"

@interface UDTest ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, weak) UDTestSuite *suite;
@end

@interface UDTestSuite ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<UDTest *> *mutableTests;
@end

@interface UDTestFailure ()
@property (nonatomic, readwrite, nullable) UDTest *test;
@property (nonatomic, readwrite, copy, nullable) NSString *file;
@property (nonatomic, readwrite) NSInteger line;
@property (nonatomic, readwrite, copy) NSString *message;
@property (nonatomic, readwrite) BOOL compilerStyle;
@end

@implementation UDTest

- (instancetype)init {
    if ((self = [super init])) _failures = [NSMutableArray array];
    return self;
}

- (NSString *)identifier {
    return [NSString stringWithFormat:@"%@.%@", _suite.name, _name];
}

@end

@implementation UDTestSuite

- (instancetype)init {
    if ((self = [super init])) {
        _mutableTests = [NSMutableArray array];
        _failures = [NSMutableArray array];
    }
    return self;
}

- (NSArray<UDTest *> *)tests {
    return [_mutableTests copy];
}

- (UDTestStatus)status {
    BOOL running = NO, allPassed = _mutableTests.count > 0;
    for (UDTest *test in _mutableTests) {
        if (test.status == UDTestStatusFailed) return UDTestStatusFailed;
        running = running || test.status == UDTestStatusRunning;
        allPassed = allPassed && test.status == UDTestStatusPassed;
    }
    if (_failures.count) return UDTestStatusFailed;
    return running ? UDTestStatusRunning : allPassed ? UDTestStatusPassed : UDTestStatusNotRun;
}

@end

@implementation UDTestFailure
@end

@implementation UDTestCatalog {
    NSMutableArray<UDTestSuite *> *_suites;
    NSMutableDictionary<NSString *, UDTestSuite *> *_suitesByName;
    NSArray<NSString *> *_paths;
}

// ---------------------------------------------------------------------------
// MARK: - The sources: test case classes and their tests
// ---------------------------------------------------------------------------

+ (instancetype)catalogOfFiles:(NSArray<NSString *> *)paths {
    NSMutableDictionary *sources = [NSMutableDictionary dictionary];
    for (NSString *path in paths) {
        if (![@[ @"m", @"mm" ] containsObject:path.pathExtension]) continue;
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        if (text && [text rangeOfString:@"@implementation"].location != NSNotFound) sources[path] = text;
    }
    return [self catalogOfSources:sources];
}

/// The identifier at the start of @a text (letters, digits, underscores).
static NSString *UDIdentifierAt(NSString *text) {
    NSMutableCharacterSet *identifier = [NSMutableCharacterSet alphanumericCharacterSet];
    [identifier addCharactersInString:@"_"];
    NSUInteger end = 0;
    while (end < text.length && [identifier characterIsMember:[text characterAtIndex:end]]) end++;
    return [text substringToIndex:end];
}

+ (instancetype)catalogOfSources:(NSDictionary<NSString *, NSString *> *)sources {
    UDTestCatalog *catalog = [[self alloc] init];
    catalog->_paths = [sources.allKeys sortedArrayUsingSelector:@selector(compare:)];
    // what each class inherits, and where each is implemented with its test methods
    NSMutableDictionary<NSString *, NSString *> *superclasses = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSArray *> *implementations = [NSMutableDictionary dictionary];   // class → [path, line, [[name, line]]]
    NSCharacterSet *spaces = [NSCharacterSet whitespaceCharacterSet];
    for (NSString *path in catalog->_paths) {
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
        UDTestSuite *suite = [catalog _suiteNamed:name create:YES];
        suite.path = implementation[0];
        suite.line = [implementation[1] integerValue];
        for (NSArray *test in implementation[2]) {
            UDTest *made = [catalog _test:test[0] inSuite:suite create:YES];
            made.path = implementation[0];
            made.line = [test[1] integerValue];
        }
    }
    return catalog;
}

- (instancetype)init {
    if ((self = [super init])) {
        _suites = [NSMutableArray array];
        _suitesByName = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSArray<UDTestSuite *> *)suites {
    return [_suites copy];
}

- (NSArray<UDTest *> *)allTests {
    NSMutableArray *tests = [NSMutableArray array];
    for (UDTestSuite *suite in _suites) [tests addObjectsFromArray:suite.mutableTests];
    return tests;
}

- (UDTestSuite *)_suiteNamed:(NSString *)name create:(BOOL)create {
    UDTestSuite *suite = _suitesByName[name];
    if (!suite && create) {
        suite = [[UDTestSuite alloc] init];
        suite.name = name;
        _suitesByName[name] = suite;
        [_suites addObject:suite];
    }
    return suite;
}

- (UDTest *)_test:(NSString *)name inSuite:(UDTestSuite *)suite create:(BOOL)create {
    for (UDTest *test in suite.mutableTests) {
        if ([test.name isEqualToString:name]) return test;
    }
    if (!create) return nil;
    UDTest *test = [[UDTest alloc] init];
    test.name = name;
    test.suite = suite;
    [suite.mutableTests addObject:test];
    return test;
}

- (UDTestSuite *)suiteNamed:(NSString *)name {
    return _suitesByName[name];
}

- (UDTest *)testNamed:(NSString *)name inSuite:(NSString *)suite {
    UDTestSuite *found = _suitesByName[suite];
    return found ? [self _test:name inSuite:found create:NO] : nil;
}

- (void)resetTests:(NSArray<UDTest *> *)tests {
    for (UDTest *test in tests ?: self.allTests) {
        test.status = UDTestStatusNotRun;
        [test.failures removeAllObjects];
    }
    if (!tests) {
        for (UDTestSuite *suite in _suites) [suite.failures removeAllObjects];
    }
}

- (NSUInteger)passedCount {
    NSUInteger count = 0;
    for (UDTest *test in self.allTests) count += test.status == UDTestStatusPassed;
    return count;
}

- (NSUInteger)failedCount {
    NSUInteger count = 0;
    for (UDTest *test in self.allTests) count += test.status == UDTestStatusFailed;
    return count;
}

- (NSString *)pathOfFile:(NSString *)file {
    if (!file.length) return nil;
    if (file.isAbsolutePath) return file;
    NSString *tail = [@"/" stringByAppendingString:file];
    for (NSString *path in _paths) {
        if ([path hasSuffix:tail] || [path isEqualToString:file]) return path;
    }
    return nil;
}

// ---------------------------------------------------------------------------
// MARK: - A run's output
// ---------------------------------------------------------------------------

/// "-[Suite test]" (Swift's "-[Module.Suite test]"): its test, made when the
/// sources didn't have it.
- (nullable UDTest *)_testOfMethodName:(NSString *)method {
    if (![method hasPrefix:@"-["] || ![method hasSuffix:@"]"]) return nil;
    NSArray<NSString *> *parts = [[method substringWithRange:NSMakeRange(2, method.length - 3)] componentsSeparatedByString:@" "];
    if (parts.count != 2) return nil;
    NSString *suite = [parts[0] componentsSeparatedByString:@"."].lastObject;
    return [self _test:parts[1] inSuite:[self _suiteNamed:suite create:YES] create:YES];
}

/// The "-[Suite test]" in @a text, from its start.
static NSString *UDMethodNameIn(NSString *text) {
    NSRange start = [text rangeOfString:@"-["];
    if (start.location == NSNotFound) return nil;
    NSRange end = [text rangeOfString:@"]" options:0 range:NSMakeRange(start.location, text.length - start.location)];
    return end.location == NSNotFound ? nil : [text substringWithRange:NSMakeRange(start.location, NSMaxRange(end) - start.location)];
}

- (UDTestFailure *)readLine:(NSString *)line {
    line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // GNUstep's xctest: NSLog's "date xctest[pid:tid] XCTest: ..."
    NSRange marker = [line rangeOfString:@"XCTest: "];
    if (marker.location != NSNotFound) {
        NSString *said = [[line substringFromIndex:NSMaxRange(marker)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([said hasPrefix:@"-["] && ([said hasSuffix:@" PASSED"] || [said hasSuffix:@" FAILED"])) {
            UDTest *test = [self _testOfMethodName:[said substringToIndex:said.length - 7]];
            test.status = [said hasSuffix:@" PASSED"] ? UDTestStatusPassed : UDTestStatusFailed;
            return nil;
        }
        if ([said hasPrefix:@"Running "]) {
            UDTestSuite *suite = [self _suiteNamed:[said substringFromIndex:8] create:NO];
            for (UDTest *test in suite.mutableTests) {
                if (test.status == UDTestStatusNotRun) test.status = UDTestStatusRunning;
            }
            return nil;
        }
        // "File.m:12: -[Suite test]: message"
        NSString *method = UDMethodNameIn(said);
        NSArray<NSString *> *place = [said componentsSeparatedByString:@":"];
        if (method && place.count >= 3 && [place[1] integerValue] > 0) {
            NSRange after = [said rangeOfString:[method stringByAppendingString:@": "]];
            UDTestFailure *failure = [[UDTestFailure alloc] init];
            failure.test = [self _testOfMethodName:method];
            failure.file = place[0];
            failure.line = [place[1] integerValue];
            failure.message = after.location == NSNotFound ? said : [said substringFromIndex:NSMaxRange(after)];
            [failure.test.failures addObject:failure.message];
            failure.test.status = UDTestStatusFailed;
            return failure;
        }
        // "Suite FAILED, threw ...": its setUp or tearDown
        NSRange threw = [said rangeOfString:@" FAILED, threw "];
        if (threw.location != NSNotFound) {
            UDTestSuite *suite = [self _suiteNamed:[said substringToIndex:threw.location] create:YES];
            [suite.failures addObject:[said substringFromIndex:threw.location + 9]];
            for (UDTest *test in suite.mutableTests) {
                if (test.status == UDTestStatusRunning) test.status = UDTestStatusFailed;
            }
        }
        return nil;
    }
    // Apple's: "Test Case '-[Suite test]' started." / "passed (0.001 seconds)." / "failed (...)."
    if ([line hasPrefix:@"Test Case '"]) {
        NSRange quote = [line rangeOfString:@"'" options:0 range:NSMakeRange(11, line.length - 11)];
        if (quote.location == NSNotFound) return nil;
        UDTest *test = [self _testOfMethodName:[line substringWithRange:NSMakeRange(11, quote.location - 11)]];
        NSString *rest = [line substringFromIndex:NSMaxRange(quote)];
        if ([rest hasPrefix:@" started"]) test.status = UDTestStatusRunning;
        else if ([rest hasPrefix:@" passed"]) test.status = UDTestStatusPassed;
        else if ([rest hasPrefix:@" failed"]) test.status = UDTestStatusFailed;
        return nil;
    }
    // "/path/File.m:12: error: -[Suite test] : message"
    NSRange error = [line rangeOfString:@": error: -["];
    if (error.location != NSNotFound) {
        NSString *place = [line substringToIndex:error.location];
        NSRange colon = [place rangeOfString:@":" options:NSBackwardsSearch];
        NSString *said = [line substringFromIndex:error.location + 9];
        NSString *method = UDMethodNameIn(said);
        if (colon.location == NSNotFound || !method) return nil;
        UDTestFailure *failure = [[UDTestFailure alloc] init];
        failure.test = [self _testOfMethodName:method];
        failure.file = [place substringToIndex:colon.location];
        failure.line = [[place substringFromIndex:NSMaxRange(colon)] integerValue];
        NSString *message = [said substringFromIndex:method.length];
        failure.message = [message hasPrefix:@" : "] ? [message substringFromIndex:3] : message;
        failure.compilerStyle = YES;
        [failure.test.failures addObject:failure.message];
        failure.test.status = UDTestStatusFailed;
        return failure;
    }
    return nil;
}

@end
