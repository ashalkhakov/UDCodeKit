/*---------------------------------------------------------------------------------------------
 *  UDSystemCredentialStore.m (linux)
 *
 *  The Secret Service (GNOME Keyring, KWallet), through libsecret: built
 *  against its header, loaded when first needed, so UDCode runs without
 *  it, and without a D-Bus session (passwords in memory then). A
 *  password's attributes are its service and account, under UDCode's
 *  schema; its label says what it opens, as Seahorse shows it.
 *--------------------------------------------------------------------------------------------*/

#import "UDSystemCredentialStore.h"
#include <dlfcn.h>

#if __has_include(<libsecret/secret.h>)
#include <libsecret/secret.h>
#define UD_HAS_LIBSECRET 1
#endif

#ifdef UD_HAS_LIBSECRET

/// What is used of it, typed by its own declarations.
static struct {
    __typeof__(&secret_password_store_sync) store;
    __typeof__(&secret_password_lookup_sync) lookup;
    __typeof__(&secret_password_clear_sync) clear;
    __typeof__(&secret_password_free) free;
    void (*errorFree)(GError *error);
} UDSecret;

static const SecretSchema UDSchema = {
    "org.underivable.udcode.Password", SECRET_SCHEMA_NONE,
    { { "service", SECRET_SCHEMA_ATTRIBUTE_STRING }, { "account", SECRET_SCHEMA_ATTRIBUTE_STRING }, { NULL, 0 } },
};

static BOOL UDLoadSecret(void) {
    static int loaded = -1;
    if (loaded >= 0) return loaded;
    void *handle = dlopen("libsecret-1.so.0", RTLD_NOW | RTLD_LOCAL);
    if (handle) {
        UDSecret.store = (__typeof__(UDSecret.store))dlsym(handle, "secret_password_store_sync");
        UDSecret.lookup = (__typeof__(UDSecret.lookup))dlsym(handle, "secret_password_lookup_sync");
        UDSecret.clear = (__typeof__(UDSecret.clear))dlsym(handle, "secret_password_clear_sync");
        UDSecret.free = (__typeof__(UDSecret.free))dlsym(handle, "secret_password_free");
        // GLib's, which libsecret links
        UDSecret.errorFree = (void (*)(GError *))dlsym(handle, "g_error_free");
    }
    loaded = handle && UDSecret.store && UDSecret.lookup && UDSecret.clear && UDSecret.free && UDSecret.errorFree;
    return loaded;
}

static NSError *UDErrorOf(GError *failure, NSString *doing) {
    NSString *reason = failure && failure->message ? @(failure->message) : @"it said nothing";
    NSInteger code = failure ? failure->code : 0;
    if (failure) UDSecret.errorFree(failure);
    return [UDSystemCredentialStore errorWithCode:code message:[NSString stringWithFormat:@"The Secret Service couldn't %@: %@", doing, reason]];
}

@implementation UDSystemCredentialStore {
    BOOL _unreachable;      // its service didn't answer: memory from then on
}

/// Whether a D-Bus session runs: libsecret would launch one otherwise, and
/// wait on a keyring's prompt no one may see.
static BOOL UDHasSessionBus(void) {
    if (getenv("DBUS_SESSION_BUS_ADDRESS")) return YES;
    const char *runtime = getenv("XDG_RUNTIME_DIR");
    return runtime && [[NSFileManager defaultManager] fileExistsAtPath:[@(runtime) stringByAppendingPathComponent:@"bus"]];
}

+ (instancetype)systemStore {
    return UDHasSessionBus() && UDLoadSecret() ? [[self alloc] init] : nil;
}

- (NSString *)name {
    return _unreachable ? [super name] : @"the Secret Service";
}

- (BOOL)isPersistent {
    return !_unreachable;
}

- (NSString *)passwordForService:(NSString *)service account:(NSString *)account {
    if (_unreachable) return [super passwordForService:service account:account];
    GError *failure = NULL;
    gchar *found = UDSecret.lookup(&UDSchema, NULL, &failure, "service", service.UTF8String, "account", account.UTF8String, NULL);
    if (failure) {
        // no Secret Service running (no D-Bus session): memory, as without libsecret
        _unreachable = YES;
        UDSecret.errorFree(failure);
        return [super passwordForService:service account:account];
    }
    if (!found) return nil;
    NSString *password = @(found);
    UDSecret.free(found);
    return password;
}

- (BOOL)setPassword:(NSString *)password forService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    if (_unreachable) return [super setPassword:password forService:service account:account error:error];
    GError *failure = NULL;
    NSString *label = [NSString stringWithFormat:@"%@: %@", service, account];
    if (UDSecret.store(&UDSchema, SECRET_COLLECTION_DEFAULT, label.UTF8String, password.UTF8String, NULL, &failure,
                       "service", service.UTF8String, "account", account.UTF8String, NULL)) return YES;
    if (error) *error = UDErrorOf(failure, @"keep the password");
    else if (failure) UDSecret.errorFree(failure);
    return NO;
}

- (BOOL)removePasswordForService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    if (_unreachable) return [super removePasswordForService:service account:account error:error];
    GError *failure = NULL;
    UDSecret.clear(&UDSchema, NULL, &failure, "service", service.UTF8String, "account", account.UTF8String, NULL);
    if (!failure) return YES;
    if (error) *error = UDErrorOf(failure, @"forget the password");
    else UDSecret.errorFree(failure);
    return NO;
}

@end

#else

// Built without libsecret's header: no system store, passwords in memory.
@implementation UDSystemCredentialStore

+ (instancetype)systemStore {
    return nil;
}

@end

#endif
