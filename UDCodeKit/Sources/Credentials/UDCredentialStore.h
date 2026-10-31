/*---------------------------------------------------------------------------------------------
 *  UDCredentialStore.h
 *
 *  Passwords kept where the system keeps them, never in settings or a
 *  project's files: the Keychain on macOS (a generic password: its service
 *  and account), the Secret Service on Linux (GNOME Keyring, KWallet:
 *  libsecret, loaded when first needed), Windows' Credential Manager. Where
 *  the system has none (no libsecret, no Secret Service running), they are
 *  kept in memory until UDCode quits, and the store says so (-persistent).
 *
 *  A password is named by its service ("UDCode database") and its account
 *  (what it opens: a connection's URL, without a password).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDCredentialStore : NSObject

/// The system's store, or one in memory where it has none.
+ (UDCredentialStore *)sharedStore;
/// Another as the shared one (the tests' own); nil: the system's again.
+ (void)setSharedStore:(nullable UDCredentialStore *)store;

/// A store kept in memory only, until UDCode quits.
+ (UDCredentialStore *)memoryStore;

/// Where it keeps them, as a sentence says it ("the Keychain", "the
/// Secret Service", "Windows Credential Manager", "memory, until UDCode
/// quits").
@property (nonatomic, readonly, copy) NSString *name;
/// Whether what it keeps outlives UDCode.
@property (nonatomic, readonly, getter=isPersistent) BOOL persistent;

/// @a account's password for @a service; nil when it keeps none.
- (nullable NSString *)passwordForService:(NSString *)service account:(NSString *)account;
/// @a password kept for them (in place of one before); NO and why in
/// @a error when the system won't.
- (BOOL)setPassword:(NSString *)password forService:(NSString *)service account:(NSString *)account
              error:(NSError *_Nullable *_Nullable)error;
/// Their password forgotten (none kept: YES).
- (BOOL)removePasswordForService:(NSString *)service account:(NSString *)account error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
