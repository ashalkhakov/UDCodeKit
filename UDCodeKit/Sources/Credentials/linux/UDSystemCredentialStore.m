/*---------------------------------------------------------------------------------------------
 *  UDSystemCredentialStore.m (linux)
 *
 *  The Secret Service (GNOME Keyring, KWallet), through libsecret: loaded
 *  when first needed, by its stable C ABI (declared here, so a build
 *  without its header still has it), so UDCode runs without it, and
 *  without a D-Bus session (passwords in memory then, and why said). A
 *  password's attributes are its service and account, under UDCode's
 *  schema; its label says what it opens, as Seahorse shows it.
 *--------------------------------------------------------------------------------------------*/

#import "UDSystemCredentialStore.h"
#include <dlfcn.h>

// libsecret's and GLib's, as their headers have them (libsecret 0.18 on)
typedef struct {
    unsigned int domain;
    int code;
    char *message;
} UDGError;

typedef struct {
    const char *name;
    int type;                       // SECRET_SCHEMA_ATTRIBUTE_STRING: 0
} UDSecretSchemaAttribute;

typedef struct {
    const char *name;
    int flags;                      // SECRET_SCHEMA_NONE: 0
    UDSecretSchemaAttribute attributes[32];
    int reserved;
    void *reserved1, *reserved2, *reserved3, *reserved4, *reserved5, *reserved6, *reserved7;
} UDSecretSchema;

/// What is used of it.
static struct {
    int (*store)(const UDSecretSchema *schema, const char *collection, const char *label, const char *password,
                 void *cancellable, UDGError **error, ...);
    char *(*lookup)(const UDSecretSchema *schema, void *cancellable, UDGError **error, ...);
    int (*clear)(const UDSecretSchema *schema, void *cancellable, UDGError **error, ...);
    void (*free)(char *password);
    void (*errorFree)(UDGError *error);
} UDSecret;

static const UDSecretSchema UDSchema = {
    "org.underivable.udcode.Password", 0,
    { { "service", 0 }, { "account", 0 }, { NULL, 0 } },
};

/// SECRET_COLLECTION_DEFAULT
static const char *const UDDefaultCollection = "default";

static NSString *UDUnavailable;     // why there is no store, once asked

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
        UDSecret.errorFree = (__typeof__(UDSecret.errorFree))dlsym(handle, "g_error_free");
    }
    loaded = handle && UDSecret.store && UDSecret.lookup && UDSecret.clear && UDSecret.free && UDSecret.errorFree;
    if (!loaded) {
        // why, as the loader says it (not there; there, but its libraries
        // not ours: an AppImage's)
        const char *why = handle ? NULL : dlerror();
        UDUnavailable = why ? [NSString stringWithFormat:@"libsecret, which UDCode keeps passwords with, can't be loaded: %s.", why]
                            : @"libsecret isn't installed (libsecret-1-0), which UDCode keeps passwords with.";
    }
    return loaded;
}

static NSError *UDErrorOf(UDGError *failure, NSString *doing) {
    NSString *reason = failure && failure->message ? @(failure->message) : @"it said nothing";
    NSInteger code = failure ? failure->code : 0;
    if (failure) UDSecret.errorFree(failure);
    return [UDSystemCredentialStore errorWithCode:code message:[NSString stringWithFormat:@"The Secret Service couldn't %@: %@", doing, reason]];
}

@implementation UDSystemCredentialStore {
    NSString *_unreachable;     // its service didn't answer (why): memory from then on
}

/// Whether a D-Bus session runs: libsecret would launch one otherwise, and
/// wait on a keyring's prompt no one may see.
static BOOL UDHasSessionBus(void) {
    if (getenv("DBUS_SESSION_BUS_ADDRESS")) return YES;
    const char *runtime = getenv("XDG_RUNTIME_DIR");
    if (runtime && [[NSFileManager defaultManager] fileExistsAtPath:[@(runtime) stringByAppendingPathComponent:@"bus"]]) return YES;
    UDUnavailable = @"There is no D-Bus session (DBUS_SESSION_BUS_ADDRESS), which the Secret Service answers on.";
    return NO;
}

+ (instancetype)systemStore {
    return UDHasSessionBus() && UDLoadSecret() ? [[self alloc] init] : nil;
}

+ (NSString *)unavailableReason {
    return UDUnavailable;
}

- (NSString *)name {
    return _unreachable ? [super name] : @"the Secret Service";
}

- (BOOL)isPersistent {
    return !_unreachable;
}

- (NSString *)unavailableReason {
    return _unreachable;
}

/// Its service not there (no keyring running): memory, as without libsecret.
- (void)_unreachable:(UDGError *)failure {
    NSString *message = failure->message ? @(failure->message) : @"it said nothing";
    _unreachable = [NSString stringWithFormat:@"The Secret Service (GNOME Keyring, KWallet) didn't answer: %@", message];
    UDSecret.errorFree(failure);
}

- (NSString *)passwordForService:(NSString *)service account:(NSString *)account {
    if (_unreachable) return [super passwordForService:service account:account];
    UDGError *failure = NULL;
    char *found = UDSecret.lookup(&UDSchema, NULL, &failure, "service", service.UTF8String, "account", account.UTF8String, NULL);
    if (failure) {
        [self _unreachable:failure];
        return [super passwordForService:service account:account];
    }
    if (!found) return nil;
    NSString *password = @(found);
    UDSecret.free(found);
    return password;
}

- (BOOL)setPassword:(NSString *)password forService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    if (_unreachable) return [super setPassword:password forService:service account:account error:error];
    UDGError *failure = NULL;
    NSString *label = [NSString stringWithFormat:@"%@: %@", service, account];
    if (UDSecret.store(&UDSchema, UDDefaultCollection, label.UTF8String, password.UTF8String, NULL, &failure,
                       "service", service.UTF8String, "account", account.UTF8String, NULL)) return YES;
    if (error) *error = UDErrorOf(failure, @"keep the password");
    else if (failure) UDSecret.errorFree(failure);
    return NO;
}

- (BOOL)removePasswordForService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    if (_unreachable) return [super removePasswordForService:service account:account error:error];
    UDGError *failure = NULL;
    UDSecret.clear(&UDSchema, NULL, &failure, "service", service.UTF8String, "account", account.UTF8String, NULL);
    if (!failure) return YES;
    if (error) *error = UDErrorOf(failure, @"forget the password");
    else UDSecret.errorFree(failure);
    return NO;
}

@end
