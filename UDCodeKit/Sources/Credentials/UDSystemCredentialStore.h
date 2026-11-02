/*---------------------------------------------------------------------------------------------
 *  UDSystemCredentialStore.h
 *
 *  The system's credential store, one implementation in each system's
 *  folder: apple (the Keychain), linux (the Secret Service, through
 *  libsecret loaded when first needed), windows (Credential Manager).
 *--------------------------------------------------------------------------------------------*/

#import "UDCredentialStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDSystemCredentialStore : UDCredentialStore

/// The system's store; nil where it has none.
+ (nullable instancetype)systemStore;
/// Why +systemStore is nil, as a sentence; nil where it isn't.
+ (nullable NSString *)unavailableReason;

@end

@interface UDSystemCredentialStore (Errors)
/// An error of the store's: @a message, the system's @a code.
+ (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message;
@end

NS_ASSUME_NONNULL_END
