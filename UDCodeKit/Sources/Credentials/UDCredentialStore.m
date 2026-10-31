/*---------------------------------------------------------------------------------------------
 *  UDCredentialStore.m
 *
 *  The store itself keeps them in memory; UDSystemCredentialStore (one in
 *  each system's folder: apple, linux, windows) is the system's.
 *--------------------------------------------------------------------------------------------*/

#import "UDCredentialStore.h"
#import "UDSystemCredentialStore.h"

@implementation UDCredentialStore {
    NSMutableDictionary<NSString *, NSString *> *_passwords;     // in memory: by service and account
}

static UDCredentialStore *UDShared;

+ (UDCredentialStore *)sharedStore {
    @synchronized(self) {
        if (!UDShared) UDShared = [UDSystemCredentialStore systemStore] ?: [self memoryStore];
        return UDShared;
    }
}

+ (void)setSharedStore:(UDCredentialStore *)store {
    @synchronized(self) {
        UDShared = store;
    }
}

+ (UDCredentialStore *)memoryStore {
    return [[UDCredentialStore alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) _passwords = [NSMutableDictionary dictionary];
    return self;
}

- (NSString *)name {
    return @"memory, until UDCode quits";
}

- (BOOL)isPersistent {
    return NO;
}

static NSString *UDKeyOf(NSString *service, NSString *account) {
    return [NSString stringWithFormat:@"%@\n%@", service, account];
}

- (NSString *)passwordForService:(NSString *)service account:(NSString *)account {
    @synchronized(self) {
        return _passwords[UDKeyOf(service, account)];
    }
}

- (BOOL)setPassword:(NSString *)password forService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    @synchronized(self) {
        _passwords[UDKeyOf(service, account)] = [password copy];
    }
    return YES;
}

- (BOOL)removePasswordForService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    @synchronized(self) {
        [_passwords removeObjectForKey:UDKeyOf(service, account)];
    }
    return YES;
}

@end

@implementation UDSystemCredentialStore (Errors)

+ (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:@"UDCredentialErrorDomain" code:code userInfo:@{ NSLocalizedDescriptionKey: message }];
}

@end
