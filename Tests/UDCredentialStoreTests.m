//
//  UDCredentialStoreTests.m
//
//  Passwords kept where the system keeps them (UDCredentialStore): the
//  system's store keeps one, gives it back, replaces it, forgets it (the
//  Keychain on macOS; on Linux the Secret Service where one runs, memory
//  where none does; UD_TEST_SECRET_SERVICE: one must). A connection's password (the SQL extension's
//  UDSQLPasswords): by its URL without a password, for the session, kept
//  only when asked, forgotten with its connection.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDSQLConnection.h"
#import "UDSQLDatabases.h"
#import "UDSQLSheets.h"

static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}

/// A store as the system's would be (persistent), in memory: the tests'.
@interface UDTestCredentialStore : UDCredentialStore
@end

@implementation UDTestCredentialStore
- (BOOL)isPersistent {
    return YES;
}
- (NSString *)name {
    return @"the tests' store";
}
@end

@interface UDCredentialStoreTests : UDCodeTestCase
@end

@implementation UDCredentialStoreTests

- (void)tearDown {
    [UDCredentialStore setSharedStore:nil];
    [super tearDown];
}

- (void)testTheSystemsStoreKeepsAndForgets {
    UDCredentialStore *store = [UDCredentialStore sharedStore];
    XCTAssertNotNil(store.name);
#ifdef __APPLE__
    XCTAssertTrue(store.persistent, @"the Keychain");
    XCTAssertEqualObjects(store.name, @"the Keychain");
#else
    // UD_TEST_SECRET_SERVICE: one runs (a D-Bus session, its keyring unlocked)
    if (getenv("UD_TEST_SECRET_SERVICE")) {
        XCTAssertNotNil([store passwordForService:@"UDCode tests" account:@"probe"] ?: @"", @"asked");
        XCTAssertTrue(store.persistent, @"%@", store.name);
        XCTAssertEqualObjects(store.name, @"the Secret Service");
    }
#endif
    NSString *service = [@"UDCode tests " stringByAppendingString:[[NSUUID UUID] UUIDString]];
    NSString *account = @"postgresql://ann@localhost:5432/app";
    NSError *error = nil;
    XCTAssertNil([store passwordForService:service account:account], @"none kept yet");
    XCTAssertTrue([store setPassword:@"s3cret ü" forService:service account:account error:&error], @"%@", error);
    XCTAssertEqualObjects([store passwordForService:service account:account], @"s3cret ü");
    XCTAssertTrue([store setPassword:@"another" forService:service account:account error:&error], @"%@", error);
    XCTAssertEqualObjects([store passwordForService:service account:account], @"another", @"replaced, not a second");
    XCTAssertNil([store passwordForService:service account:@"postgresql://bob@localhost:5432/app"], @"by its account");
    XCTAssertTrue([store removePasswordForService:service account:account error:&error], @"%@", error);
    XCTAssertNil([store passwordForService:service account:account]);
    XCTAssertTrue([store removePasswordForService:service account:account error:&error], @"none kept: still YES");
}

- (void)testTheMemoryStore {
    UDCredentialStore *store = [UDCredentialStore memoryStore];
    XCTAssertFalse(store.persistent);
    XCTAssertEqualObjects(store.name, @"memory, until UDCode quits");
    [store setPassword:@"x" forService:@"s" account:@"a" error:NULL];
    XCTAssertEqualObjects([store passwordForService:@"s" account:@"a"], @"x");
    XCTAssertNil([[UDCredentialStore memoryStore] passwordForService:@"s" account:@"a"], @"each its own");
}

- (void)testAConnectionsPassword {
    UDTestCredentialStore *store = [[UDTestCredentialStore alloc] init];
    [UDCredentialStore setSharedStore:store];
    Class passwords = UDPluginClass(@"UDSQLPasswords");
    NSURL *url = [NSURL URLWithString:@"postgresql://ann:inline@db.example:5432/app?sslmode=require"];
    XCTAssertEqualObjects([passwords accountOfURL:url], @"postgresql://ann@db.example:5432/app?sslmode=require", @"its URL, no password");
    NSString *account = [passwords accountOfURL:url];

    // for the session only
    XCTAssertNil([passwords rememberPassword:@"one" ofURL:url keep:NO]);
    XCTAssertEqualObjects([passwords passwordOfURL:url], @"one");
    XCTAssertFalse([passwords isKeptForURL:url]);
    XCTAssertNil([store passwordForService:@"UDCode database" account:account], @"not kept");
    // kept
    XCTAssertNil([passwords rememberPassword:@"two" ofURL:url keep:YES]);
    XCTAssertTrue([passwords isKeptForURL:url]);
    XCTAssertEqualObjects([store passwordForService:@"UDCode database" account:account], @"two");
    // kept no more: forgotten by the store, still this session's
    [passwords rememberPassword:@"two" ofURL:url keep:NO];
    XCTAssertFalse([passwords isKeptForURL:url]);
    XCTAssertEqualObjects([passwords passwordOfURL:url], @"two");
    // a later session: the store's
    [passwords rememberPassword:@"three" ofURL:url keep:YES];
    [passwords forgetPasswordOfURL:url];
    XCTAssertNil([passwords passwordOfURL:url]);
    [store setPassword:@"kept" forService:@"UDCode database" account:account error:NULL];
    XCTAssertEqualObjects([passwords passwordOfURL:url], @"kept", @"the store's, when this session has none");
    [passwords forgetPasswordOfURL:url];
    XCTAssertNil([store passwordForService:@"UDCode database" account:account]);
}

- (void)testAConnectionRemovedForgetsItsPassword {
    UDTestCredentialStore *store = [[UDTestCredentialStore alloc] init];
    [UDCredentialStore setSharedStore:store];
    Class passwords = UDPluginClass(@"UDSQLPasswords");
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UDSQLDatabases"];
    UDSQLDatabases *databases = [[UDPluginClass(@"UDSQLDatabases") alloc] initWithWorkbench:nil];
    NSURL *url = [NSURL URLWithString:@"postgresql://ann@db.example/app"];
    UDSQLDatabase *one = [[UDPluginClass(@"UDSQLDatabase") alloc] init];
    one.name = @"one";
    one.URL = url;
    UDSQLDatabase *two = [[UDPluginClass(@"UDSQLDatabase") alloc] init];
    two.name = @"two";
    two.URL = url;
    [databases addDatabase:one];
    [databases addDatabase:two];
    [passwords rememberPassword:@"pw" ofURL:url keep:YES];
    [databases removeDatabase:one];
    XCTAssertTrue([passwords isKeptForURL:url], @"another connection is to it");
    [databases removeDatabase:two];
    XCTAssertFalse([passwords isKeptForURL:url], @"forgotten with its last connection");
    XCTAssertNil([passwords passwordOfURL:url]);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UDSQLDatabases"];
}

@end
