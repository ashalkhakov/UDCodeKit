/*---------------------------------------------------------------------------------------------
 *  UDSystemCredentialStore.m (apple)
 *
 *  The Keychain's generic passwords: a password's service and account
 *  theirs, labeled so Keychain Access shows what each opens.
 *--------------------------------------------------------------------------------------------*/

#import "UDSystemCredentialStore.h"
#import <Security/Security.h>

@implementation UDSystemCredentialStore

+ (instancetype)systemStore {
    return [[self alloc] init];
}

- (NSString *)name {
    return @"the Keychain";
}

- (BOOL)isPersistent {
    return YES;
}

static NSMutableDictionary *UDQueryOf(NSString *service, NSString *account) {
    return [@{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
               (__bridge id)kSecAttrService: service,
               (__bridge id)kSecAttrAccount: account } mutableCopy];
}

static NSError *UDErrorOf(OSStatus status, NSString *doing) {
    NSString *reason = CFBridgingRelease(SecCopyErrorMessageString(status, NULL)) ?: [NSString stringWithFormat:@"error %d", (int)status];
    return [UDSystemCredentialStore errorWithCode:status message:[NSString stringWithFormat:@"The Keychain couldn't %@: %@", doing, reason]];
}

- (NSString *)passwordForService:(NSString *)service account:(NSString *)account {
    NSMutableDictionary *query = UDQueryOf(service, account);
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef data = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &data) != errSecSuccess || !data) return nil;
    return [[NSString alloc] initWithData:CFBridgingRelease(data) encoding:NSUTF8StringEncoding];
}

- (BOOL)setPassword:(NSString *)password forService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    NSData *data = [password dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = UDQueryOf(service, account);
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)@{ (__bridge id)kSecValueData: data });
    if (status == errSecItemNotFound) {
        NSMutableDictionary *item = [query mutableCopy];
        item[(__bridge id)kSecValueData] = data;
        item[(__bridge id)kSecAttrLabel] = [NSString stringWithFormat:@"%@: %@", service, account];
        status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }
    if (status == errSecSuccess) return YES;
    if (error) *error = UDErrorOf(status, @"keep the password");
    return NO;
}

- (BOOL)removePasswordForService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)UDQueryOf(service, account));
    if (status == errSecSuccess || status == errSecItemNotFound) return YES;
    if (error) *error = UDErrorOf(status, @"forget the password");
    return NO;
}

@end
