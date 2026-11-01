/*---------------------------------------------------------------------------------------------
 *  UDSystemCredentialStore.m (windows)
 *
 *  Windows' Credential Manager: a generic credential, named by its service
 *  and account ("UDCode database:postgresql://ann@db/app"), its password
 *  in UTF-16 as Windows' own tools keep it; kept for this user, on this
 *  machine.
 *--------------------------------------------------------------------------------------------*/

#import "UDSystemCredentialStore.h"
#include <windows.h>
#include <wincred.h>

@implementation UDSystemCredentialStore

+ (instancetype)systemStore {
    return [[self alloc] init];
}

+ (NSString *)unavailableReason {
    return nil;
}

- (NSString *)name {
    return @"Windows Credential Manager";
}

- (BOOL)isPersistent {
    return YES;
}

static NSData *UDWide(NSString *text) {
    NSMutableData *wide = [[text dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
    [wide appendBytes:"\0\0" length:2];
    return wide;
}

static NSData *UDTargetOf(NSString *service, NSString *account) {
    return UDWide([NSString stringWithFormat:@"%@:%@", service, account]);
}

static NSError *UDErrorOf(DWORD code, NSString *doing) {
    return [UDSystemCredentialStore errorWithCode:(NSInteger)code
                                          message:[NSString stringWithFormat:@"Credential Manager couldn't %@ (error %lu).", doing, (unsigned long)code]];
}

- (NSString *)passwordForService:(NSString *)service account:(NSString *)account {
    PCREDENTIALW credential = NULL;
    if (!CredReadW((LPCWSTR)UDTargetOf(service, account).bytes, CRED_TYPE_GENERIC, 0, &credential)) return nil;
    NSString *password = [[NSString alloc] initWithBytes:credential->CredentialBlob length:credential->CredentialBlobSize
                                                encoding:NSUTF16LittleEndianStringEncoding];
    CredFree(credential);
    return password;
}

- (BOOL)setPassword:(NSString *)password forService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    NSData *target = UDTargetOf(service, account), *user = UDWide(account);
    NSData *blob = [password dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    CREDENTIALW credential = { 0 };
    credential.Type = CRED_TYPE_GENERIC;
    credential.TargetName = (LPWSTR)target.bytes;
    credential.UserName = (LPWSTR)user.bytes;
    credential.CredentialBlobSize = (DWORD)blob.length;
    credential.CredentialBlob = (LPBYTE)blob.bytes;
    credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
    if (CredWriteW(&credential, 0)) return YES;
    if (error) *error = UDErrorOf(GetLastError(), @"keep the password");
    return NO;
}

- (BOOL)removePasswordForService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    if (CredDeleteW((LPCWSTR)UDTargetOf(service, account).bytes, CRED_TYPE_GENERIC, 0)) return YES;
    DWORD code = GetLastError();
    if (code == ERROR_NOT_FOUND) return YES;
    if (error) *error = UDErrorOf(code, @"forget the password");
    return NO;
}

@end
