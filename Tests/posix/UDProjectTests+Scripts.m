//
//  UDProjectTests+Scripts.m
//  UDCodeTests
//
//  UDProjectTests that run a shell script as a program (#!/bin/sh): a POSIX
//  system's, which Windows does not build (posix/).
//

#import <XCTest/XCTest.h>
#import <UDCodeKit/UDCodeKit.h>
#import "../UDProjectTests.h"
#import "AppDelegate.h"
#import "UDDocument.h"
#import "UDDocumentWindowController.h"

@implementation UDProjectTests (Scripts)

/// A Makefile project's test executable, found as C++ TestMate finds them (a
/// GoogleTest's, by what it says of itself): its tests listed, run, one alone.
- (void)testATestExecutableIsAskedForItsTests {
    // a GoogleTest executable, as far as UDCode can tell: it answers as one
    [self write:@"all:\n" to:@"Makefile"];
    [self write:@"#!/bin/sh\n"
                @"case \"$1\" in\n"
                @"  --help) echo 'This program contains tests written using Google Test.'; echo '  --gtest_list_tests'; exit 0 ;;\n"
                @"  --gtest_list_tests) printf 'Calc.\\n  Adds\\n  Divides\\n'; exit 0 ;;\n"
                @"esac\n"
                @"filter=${1#--gtest_filter=}\n"
                @"for t in Calc.Adds Calc.Divides; do\n"
                @"  case \"$filter\" in *\"$t\"*|\"\") ;; *) [ -n \"$1\" ] && continue ;; esac\n"
                @"  echo \"[ RUN      ] $t\"\n"
                @"  if [ \"$t\" = Calc.Divides ]; then echo \"$PWD/../calc_test.cc:12: Failure\"; echo 'Expected: 1'; echo \"[  FAILED  ] $t (0 ms)\";\n"
                @"  else echo \"[       OK ] $t (0 ms)\"; fi\n"
                @"done\n" to:@"build/calc_test"];
    [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0755 }
                                     ofItemAtPath:[self.folder stringByAppendingPathComponent:@"build/calc_test"] error:NULL];
    [self write:@"// the tests\n" to:@"calc_test.cc"];
    UDWorkspace *workspace = nil;
    UDDocumentWindowController *controller = [self openProject:&workspace];
    UDTestCatalog *catalog = controller.testCatalog;
    UDTest *adds = [catalog testNamed:@"Adds" inSuite:@"Calc"];
    UDTest *divides = [catalog testNamed:@"Divides" inSuite:@"Calc"];
    XCTAssertNotNil(adds, @"%@", [catalog.allTests valueForKey:@"identifier"]);
    XCTAssertEqualObjects(adds.suite.kind, @"gtest");

    [controller test:nil];
    UDRunUntil(!controller.buildRunner.running, 60);
    XCTAssertEqual(adds.status, UDTestStatusPassed, @"%@", controller.buildRunner.output);
    XCTAssertEqual(divides.status, UDTestStatusFailed, @"%@", controller.buildRunner.output);
    NSString *file = [[self.folder stringByAppendingPathComponent:@"calc_test.cc"] stringByStandardizingPath];
    XCTAssertEqual(controller.buildRunner.diagnostics[file].allDiagnostics.firstObject.line, 12, @"%@", controller.buildRunner.diagnostics);

    [controller runTests:@[ adds ] debugging:NO];
    UDRunUntil(!controller.buildRunner.running, 60);
    XCTAssertTrue([controller.buildRunner.output containsString:@"Calc.Adds"]);
    XCTAssertFalse([controller.buildRunner.output containsString:@"Calc.Divides"], @"alone: %@", controller.buildRunner.output);
    [controller close];
    [workspace close];
}

@end
