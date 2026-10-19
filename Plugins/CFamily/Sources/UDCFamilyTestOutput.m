/*---------------------------------------------------------------------------------------------
 *  UDCFamilyTestOutput.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCFamilyTestOutput.h"
#import <objc/runtime.h>

NSString * const UDTestKindXCTest = @"xctest";
NSString * const UDTestKindCTest = @"ctest";
NSString * const UDTestKindGoogleTest = @"gtest";

@implementation UDTest (CFamily)

- (NSString *)identifier {
    if ([self.suite.kind isEqualToString:UDTestKindCTest]) return self.name;
    return [NSString stringWithFormat:@"%@.%@", self.suite.name, self.name];
}

@end

@implementation UDCFamilyTestRunner

- (BOOL)readLine:(NSString *)line inCatalog:(UDTestCatalog *)catalog failure:(UDTestFailure **)failure {
    return [[UDCFamilyTestOutput readerOfCatalog:catalog] readLine:line failure:failure];
}

@end

static char UDReaderKey;

@implementation UDCFamilyTestOutput {
    __weak UDTestCatalog *_catalog;
    UDTestFailure *_pendingFailure;     // GoogleTest's, its message's lines still coming
}

+ (instancetype)readerOfCatalog:(UDTestCatalog *)catalog {
    UDCFamilyTestOutput *reader = objc_getAssociatedObject(catalog, &UDReaderKey);
    if (!reader) {
        reader = [[UDCFamilyTestOutput alloc] init];
        reader->_catalog = catalog;
        objc_setAssociatedObject(catalog, &UDReaderKey, reader, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return reader;
}

/// @a suite's test @a name, the suite (made of kind @a kind when new) made when it isn't there.
- (UDTest *)_test:(NSString *)name inSuite:(NSString *)suiteName kind:(NSString *)kind {
    UDTestSuite *suite = [_catalog addSuiteNamed:suiteName];
    if (!suite.kind) suite.kind = kind;
    return [_catalog addTest:name toSuite:suite];
}

/// "-[Suite test]" (Swift's "-[Module.Suite test]"): its test, made when the
/// sources didn't have it.
- (nullable UDTest *)_testOfMethodName:(NSString *)method {
    if (![method hasPrefix:@"-["] || ![method hasSuffix:@"]"]) return nil;
    NSArray<NSString *> *parts = [[method substringWithRange:NSMakeRange(2, method.length - 3)] componentsSeparatedByString:@" "];
    if (parts.count != 2) return nil;
    return [self _test:parts[1] inSuite:[parts[0] componentsSeparatedByString:@"."].lastObject kind:UDTestKindXCTest];
}

/// The "-[Suite test]" in @a text, from its start.
static NSString *UDMethodNameIn(NSString *text) {
    NSRange start = [text rangeOfString:@"-["];
    if (start.location == NSNotFound) return nil;
    NSRange end = [text rangeOfString:@"]" options:0 range:NSMakeRange(start.location, text.length - start.location)];
    return end.location == NSNotFound ? nil : [text substringWithRange:NSMakeRange(start.location, NSMaxRange(end) - start.location)];
}

/// GoogleTest's "[  FAILED  ] Suite.Test (3 ms)" and the like: the test named.
- (nullable UDTest *)_googleTestNamed:(NSString *)said {
    NSString *name = [said componentsSeparatedByString:@" "].firstObject;
    NSRange dot = [name rangeOfString:@"."];
    if (dot.location == NSNotFound) return nil;
    return [self _test:[name substringFromIndex:NSMaxRange(dot)] inSuite:[name substringToIndex:dot.location] kind:UDTestKindGoogleTest];
}

/// A GoogleTest failure whose message has ended: its test's.
- (nullable UDTestFailure *)_endPendingFailure {
    UDTestFailure *ended = _pendingFailure;
    _pendingFailure = nil;
    if (ended.test) [ended.test.failures addObject:ended.message];
    return ended;
}

/// A failure of @a test, its test marked failed.
static UDTestFailure *UDFailed(UDTest *test, NSString *file, NSInteger line, NSString *message) {
    UDTestFailure *failure = [UDTestFailure failureOfTest:test file:file line:line message:message];
    [test.failures addObject:message];
    test.status = UDTestStatusFailed;
    return failure;
}

- (BOOL)readLine:(NSString *)line failure:(UDTestFailure **)failure {
    *failure = nil;
    // GoogleTest's: "[ RUN      ] Suite.Test", "[       OK ] ...", "[  FAILED  ] ...";
    // a failure, "file:line: Failure" and its message's lines
    if ([line hasPrefix:@"["] && line.length > 12 && [line characterAtIndex:11] == ']') {
        *failure = [self _endPendingFailure];
        NSString *tag = [[line substringWithRange:NSMakeRange(1, 10)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *said = [[line substringFromIndex:12] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        UDTest *test = [tag isEqualToString:@"RUN"] || [tag isEqualToString:@"OK"] || [tag isEqualToString:@"FAILED"]
                     ? [self _googleTestNamed:said] : nil;
        if ([tag isEqualToString:@"RUN"]) test.status = UDTestStatusRunning;
        else if ([tag isEqualToString:@"OK"]) test.status = UDTestStatusPassed;
        else if ([tag isEqualToString:@"FAILED"] && test.status != UDTestStatusPassed) test.status = UDTestStatusFailed;
        return YES;
    }
    NSRange gtestFailure = [line rangeOfString:@": Failure" options:NSBackwardsSearch];
    if (gtestFailure.location != NSNotFound && NSMaxRange(gtestFailure) == line.length) {
        NSString *place = [line substringToIndex:gtestFailure.location];
        NSRange colon = [place rangeOfString:@":" options:NSBackwardsSearch];
        if (colon.location != NSNotFound) {
            *failure = [self _endPendingFailure];
            // the test running: the last marked so
            UDTest *running = nil;
            for (UDTest *test in _catalog.allTests) {
                if (test.status == UDTestStatusRunning) running = test;
            }
            _pendingFailure = [UDTestFailure failureOfTest:running file:[place substringToIndex:colon.location]
                                                      line:[[place substringFromIndex:NSMaxRange(colon)] integerValue] message:@""];
            running.status = UDTestStatusFailed;
            return YES;
        }
    }
    if (_pendingFailure) {
        _pendingFailure.message = _pendingFailure.message.length ? [_pendingFailure.message stringByAppendingFormat:@" %@", line] : line;
        return YES;
    }
    // CTest's: "1/2 Test #1: adds ......   Passed    0.00 sec", "...***Failed"
    UDTestSuite *ctest = [_catalog suiteNamed:@"CTest"];
    NSRange number = [line rangeOfString:@" Test #"];
    if (number.location != NSNotFound && ctest) {
        NSString *rest = [line substringFromIndex:NSMaxRange(number)];
        NSRange colon = [rest rangeOfString:@": "];
        if (colon.location != NSNotFound) {
            NSString *after = [rest substringFromIndex:NSMaxRange(colon)];
            UDTest *test = [_catalog testNamed:[after componentsSeparatedByString:@" "].firstObject inSuite:@"CTest"];
            if ([after rangeOfString:@"Passed"].location != NSNotFound) test.status = UDTestStatusPassed;
            else if ([after rangeOfString:@"***"].location != NSNotFound || [after rangeOfString:@"Failed"].location != NSNotFound) {
                test.status = UDTestStatusFailed;
            }
            return YES;
        }
    }
    if ([line hasPrefix:@"Start "] && ctest) {
        NSRange colon = [line rangeOfString:@": "];
        if (colon.location != NSNotFound) {
            [_catalog testNamed:[line substringFromIndex:NSMaxRange(colon)] inSuite:@"CTest"].status = UDTestStatusRunning;
        }
        return YES;
    }
    // GNUstep's xctest: NSLog's "date xctest[pid:tid] XCTest: ..."
    NSRange marker = [line rangeOfString:@"XCTest: "];
    if (marker.location != NSNotFound) {
        NSString *said = [[line substringFromIndex:NSMaxRange(marker)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([said hasPrefix:@"-["] && ([said hasSuffix:@" PASSED"] || [said hasSuffix:@" FAILED"])) {
            UDTest *test = [self _testOfMethodName:[said substringToIndex:said.length - 7]];
            test.status = [said hasSuffix:@" PASSED"] ? UDTestStatusPassed : UDTestStatusFailed;
            return YES;
        }
        if ([said hasPrefix:@"Running "]) {
            for (UDTest *test in [_catalog suiteNamed:[said substringFromIndex:8]].tests) {
                if (test.status == UDTestStatusNotRun) test.status = UDTestStatusRunning;
            }
            return YES;
        }
        // "File.m:12: -[Suite test]: message"
        NSString *method = UDMethodNameIn(said);
        NSArray<NSString *> *place = [said componentsSeparatedByString:@":"];
        if (method && place.count >= 3 && [place[1] integerValue] > 0) {
            NSRange after = [said rangeOfString:[method stringByAppendingString:@": "]];
            *failure = UDFailed([self _testOfMethodName:method], place[0], [place[1] integerValue],
                                after.location == NSNotFound ? said : [said substringFromIndex:NSMaxRange(after)]);
            return YES;
        }
        // "Suite FAILED, threw ...": its setUp or tearDown
        NSRange threw = [said rangeOfString:@" FAILED, threw "];
        if (threw.location != NSNotFound) {
            UDTestSuite *suite = [_catalog addSuiteNamed:[said substringToIndex:threw.location]];
            [suite.failures addObject:[said substringFromIndex:threw.location + 9]];
            for (UDTest *test in suite.tests) {
                if (test.status == UDTestStatusRunning) test.status = UDTestStatusFailed;
            }
        }
        return YES;
    }
    // Apple's: "Test Case '-[Suite test]' started." / "passed (0.001 seconds)." / "failed (...).";
    // xcodebuild's since Xcode 16, "Test case '-[Suite test]' passed on 'My Mac - App (pid)' (0.001 seconds)"
    if ([line rangeOfString:@"Test Case '" options:NSAnchoredSearch | NSCaseInsensitiveSearch].location == 0) {
        NSRange quote = [line rangeOfString:@"'" options:0 range:NSMakeRange(11, line.length - 11)];
        if (quote.location == NSNotFound) return YES;
        UDTest *test = [self _testOfMethodName:[line substringWithRange:NSMakeRange(11, quote.location - 11)]];
        NSString *rest = [line substringFromIndex:NSMaxRange(quote)];
        if ([rest hasPrefix:@" started"]) test.status = UDTestStatusRunning;
        else if ([rest hasPrefix:@" passed"]) test.status = UDTestStatusPassed;
        else if ([rest hasPrefix:@" failed"]) test.status = UDTestStatusFailed;
        return YES;
    }
    // "/path/File.m:12: error: -[Suite test] : message"
    NSRange error = [line rangeOfString:@": error: -["];
    if (error.location != NSNotFound) {
        NSString *place = [line substringToIndex:error.location];
        NSRange colon = [place rangeOfString:@":" options:NSBackwardsSearch];
        NSString *said = [line substringFromIndex:error.location + 9];
        NSString *method = UDMethodNameIn(said);
        if (colon.location == NSNotFound || !method) return NO;
        NSString *message = [said substringFromIndex:method.length];
        *failure = UDFailed([self _testOfMethodName:method], [place substringToIndex:colon.location],
                            [[place substringFromIndex:NSMaxRange(colon)] integerValue],
                            [message hasPrefix:@" : "] ? [message substringFromIndex:3] : message);
        (*failure).compilerStyle = YES;
        return YES;
    }
    return NO;
}

@end
