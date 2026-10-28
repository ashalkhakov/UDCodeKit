//
//  UDShellTests.m
//  UDCodeTests
//
//  The shell on Windows: MSYS2's, and what a user may choose for it
//  (windows/, which no other system builds).
//

#import <XCTest/XCTest.h>
#import <UDCodeKit/UDCodeKit.h>
#import <UDCodeKit/UDShell.h>

@interface UDShellTests : XCTestCase
@end

@implementation UDShellTests

/// MSYS2's launchers (msys2.exe, clang64.exe), chosen as the shell in
/// Preferences: its bash, as a launcher opens a window and runs nothing.
- (void)testAnMSYS2LauncherIsItsBash {
    NSString *bash = UDLoginShellArguments(nil).firstObject;
    NSString *root = [[[bash stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
                      stringByDeletingLastPathComponent];
    XCTAssertEqualObjects(bash.lastPathComponent, @"bash.exe", @"MSYS2's bash, where the tests run");
    for (NSString *name in @[ @"msys2.exe", @"clang64.exe" ]) {
        NSString *launcher = [root stringByAppendingPathComponent:name];
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:launcher]) continue;
        XCTAssertEqualObjects(UDLoginShellArguments(launcher), (@[ bash, @"-l" ]), @"%@", name);
        XCTAssertEqualObjects(UDShellCommandArguments(launcher, @"make"), (@[ bash, @"-c", @"make" ]), @"%@", name);
        XCTAssertEqualObjects(UDShellToolFolders(launcher), UDShellToolFolders(nil), @"%@", name);
    }
}

@end
