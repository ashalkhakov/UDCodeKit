/*---------------------------------------------------------------------------------------------
 *  UDExtensionUpdates.m
 *--------------------------------------------------------------------------------------------*/

#import "UDExtensionUpdates.h"
#include <stdint.h>
#include <string.h>

NSNotificationName const UDExtensionUpdatesDidChangeNotification = @"UDExtensionUpdatesDidChangeNotification";

static NSString *const UDExtensionsUpdateAutomaticallyKey = @"UDExtensionsUpdateAutomatically";
static NSString *const UDExtensionsLastUpdateCheckKey = @"UDExtensionsLastUpdateCheck";
static NSString *const UDShippedExtensionsInstalledKey = @"UDShippedExtensionsInstalled";

static NSError *UDUpdateError(NSString *message) {
    return [NSError errorWithDomain:UDExtensionErrorDomain code:2 userInfo:@{ NSLocalizedDescriptionKey: message }];
}

@interface UDExtensionUpdate ()
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *installedVersion;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSURL *packageURL;
@property (nonatomic, copy) NSString *sha256;
@end

@implementation UDExtensionUpdate
@end

// ---------------------------------------------------------------------------
// MARK: - SHA-256 (FIPS 180-4), the same on every system
// ---------------------------------------------------------------------------

static const uint32_t UDSHA256K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

#define UDRotateRight(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void UDSHA256Block(uint32_t state[8], const uint8_t block[64]) {
    uint32_t w[64];
    for (int i = 0; i < 16; i++) {
        w[i] = (uint32_t)block[4 * i] << 24 | (uint32_t)block[4 * i + 1] << 16 | (uint32_t)block[4 * i + 2] << 8 | block[4 * i + 3];
    }
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = UDRotateRight(w[i - 15], 7) ^ UDRotateRight(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = UDRotateRight(w[i - 2], 17) ^ UDRotateRight(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = state[0], b = state[1], c = state[2], d = state[3], e = state[4], f = state[5], g = state[6], h = state[7];
    for (int i = 0; i < 64; i++) {
        uint32_t t1 = h + (UDRotateRight(e, 6) ^ UDRotateRight(e, 11) ^ UDRotateRight(e, 25)) + ((e & f) ^ (~e & g)) + UDSHA256K[i] + w[i];
        uint32_t t2 = (UDRotateRight(a, 2) ^ UDRotateRight(a, 13) ^ UDRotateRight(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
        h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

@implementation UDExtensionUpdates {
    NSMutableArray<UDExtensionUpdate *> *_available;
}

+ (NSString *)SHA256OfData:(NSData *)data {
    uint32_t state[8] = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };
    const uint8_t *bytes = data.bytes;
    uint64_t length = data.length;
    uint64_t whole = length / 64 * 64;
    for (uint64_t offset = 0; offset < whole; offset += 64) UDSHA256Block(state, bytes + offset);
    // the rest, a 1 bit, zeros, and the length in bits: one block or two
    uint8_t tail[128] = { 0 };
    size_t rest = (size_t)(length - whole);
    if (rest) memcpy(tail, bytes + whole, rest);
    tail[rest] = 0x80;
    size_t blocks = rest + 9 > 64 ? 2 : 1;
    uint64_t bits = length * 8;
    for (int i = 0; i < 8; i++) tail[blocks * 64 - 1 - i] = (uint8_t)(bits >> (8 * i));
    for (size_t i = 0; i < blocks; i++) UDSHA256Block(state, tail + 64 * i);
    NSMutableString *hex = [NSMutableString stringWithCapacity:64];
    for (int i = 0; i < 8; i++) [hex appendFormat:@"%08x", state[i]];
    return hex;
}

// ---------------------------------------------------------------------------
// MARK: - Settings
// ---------------------------------------------------------------------------

+ (instancetype)sharedUpdates {
    static UDExtensionUpdates *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[UDExtensionUpdates alloc] init]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _available = [NSMutableArray array];
    return self;
}

- (UDExtensionFetch)fetch {
    if (_fetch) return _fetch;
    return ^(NSURL *url, void (^completion)(NSData *, NSError *)) {
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 200;
                if (!error && (status < 200 || status >= 300)) {
                    error = UDUpdateError([NSString stringWithFormat:@"%@ answered %ld.", url.host ?: url.absoluteString, (long)status]);
                    data = nil;
                }
                completion(error ? nil : data, error);
            }];
        [task resume];
    };
}

- (BOOL)automaticallyUpdates {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:UDExtensionsUpdateAutomaticallyKey];
    return value ? [value boolValue] : YES;
}

- (void)setAutomaticallyUpdates:(BOOL)automaticallyUpdates {
    [[NSUserDefaults standardUserDefaults] setBool:automaticallyUpdates forKey:UDExtensionsUpdateAutomaticallyKey];
}

- (NSDate *)lastCheck {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:UDExtensionsLastUpdateCheckKey];
    return [value isKindOfClass:[NSDate class]] ? value : nil;
}

- (NSArray<UDExtensionUpdate *> *)available {
    return [_available copy];
}

- (UDExtensionUpdate *)updateForIdentifier:(NSString *)identifier {
    for (UDExtensionUpdate *update in _available) {
        if ([update.identifier isEqualToString:identifier.lowercaseString]) return update;
    }
    return nil;
}

// ---------------------------------------------------------------------------
// MARK: - Feeds
// ---------------------------------------------------------------------------

+ (UDExtensionUpdate *)updateInFeed:(NSData *)feed forExtension:(UDExtensionInfo *)extension error:(NSError **)outError {
    id root = [NSJSONSerialization JSONObjectWithData:feed options:0 error:NULL];
    NSArray *versions = [root isKindOfClass:[NSDictionary class]] ? root[@"versions"] : nil;
    if (![versions isKindOfClass:[NSArray class]]) {
        if (outError) *outError = UDUpdateError(@"Its feed has no versions: it isn't a UDCode extension's feed.");
        return nil;
    }
    NSString *name = root[@"name"];
    if ([name isKindOfClass:[NSString class]] && ![name.lowercaseString isEqualToString:extension.identifier]) {
        if (outError) *outError = UDUpdateError([NSString stringWithFormat:@"Its feed is %@'s, not %@'s.", name, extension.identifier]);
        return nil;
    }
    NSString *host = [UDInstalledExtensions hostVersion], *platform = [UDInstalledExtensions hostPlatform];
    NSString *installed = extension.version ?: @"0.0.0";
    UDExtensionUpdate *best = nil;
    for (NSDictionary *entry in versions) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *version = entry[@"version"];
        if (![version isKindOfClass:[NSString class]]) continue;
        if ([UDInstalledExtensions compareVersion:version toVersion:installed] != NSOrderedDescending) continue;
        if (best && [UDInstalledExtensions compareVersion:version toVersion:best.version] != NSOrderedDescending) continue;
        // for this UDCode, and this platform (or any: "universal")
        NSDictionary *engines = [entry[@"engines"] isKindOfClass:[NSDictionary class]] ? entry[@"engines"] : nil;
        NSString *engine = [engines[@"udcode"] isKindOfClass:[NSString class]] ? engines[@"udcode"] : nil;
        if (!engine || ![UDInstalledExtensions version:host satisfies:engine]) continue;
        NSDictionary *packages = [entry[@"packages"] isKindOfClass:[NSDictionary class]] ? entry[@"packages"] : nil;
        NSDictionary *package = packages[platform] ?: packages[@"universal"];
        if (![package isKindOfClass:[NSDictionary class]]) continue;
        NSString *url = package[@"url"], *sha256 = package[@"sha256"];
        if (![url isKindOfClass:[NSString class]] || ![sha256 isKindOfClass:[NSString class]] || sha256.length != 64) continue;
        NSURL *packageURL = [NSURL URLWithString:url];
        if (!packageURL) continue;
        best = [[UDExtensionUpdate alloc] init];
        best.identifier = extension.identifier;
        best.displayName = extension.displayName;
        best.installedVersion = installed;
        best.version = version;
        best.packageURL = packageURL;
        best.sha256 = sha256.lowercaseString;
    }
    return best;
}

- (void)_setAvailable:(UDExtensionUpdate *)update forIdentifier:(NSString *)identifier {
    UDExtensionUpdate *old = [self updateForIdentifier:identifier];
    if (old) [_available removeObject:old];
    if (update) [_available addObject:update];
}

- (void)checkExtensions:(NSArray<UDExtensionInfo *> *)extensions completion:(void (^)(NSArray<UDExtensionUpdate *> *))completion {
    NSMutableArray<UDExtensionInfo *> *withFeeds = [NSMutableArray array];
    for (UDExtensionInfo *extension in extensions) {
        if (extension.location == UDExtensionLocationInstalled && extension.updatesURL) [withFeeds addObject:extension];
    }
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:UDExtensionsLastUpdateCheckKey];
    if (!withFeeds.count) {
        if (completion) completion(@[]);
        return;
    }
    __block NSUInteger left = withFeeds.count;
    NSMutableArray<UDExtensionUpdate *> *found = [NSMutableArray array];
    UDExtensionFetch fetch = self.fetch;
    for (UDExtensionInfo *extension in withFeeds) {
        fetch(extension.updatesURL, ^(NSData *data, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *problem = error;
                UDExtensionUpdate *update = data ? [UDExtensionUpdates updateInFeed:data forExtension:extension error:&problem] : nil;
                if (problem) NSLog(@"UDExtensionUpdates: %@'s feed (%@): %@", extension.identifier, extension.updatesURL, problem.localizedDescription);
                [self _setAvailable:update forIdentifier:extension.identifier];
                if (update) [found addObject:update];
                if (--left > 0) return;
                if (found.count) [[NSNotificationCenter defaultCenter] postNotificationName:UDExtensionUpdatesDidChangeNotification object:self];
                if (completion) completion(found);
            });
        });
    }
}

- (void)installUpdate:(UDExtensionUpdate *)update completion:(void (^)(UDExtensionInfo *, NSError *))completion {
    self.fetch(update.packageURL, ^(NSData *data, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *problem = error;
            UDExtensionInfo *installed = nil;
            if (data && ![[UDExtensionUpdates SHA256OfData:data] isEqualToString:update.sha256]) {
                problem = UDUpdateError([NSString stringWithFormat:@"%@ %@'s package isn't the one its feed names (its SHA-256 differs).",
                                                                   update.displayName, update.version]);
            } else if (data) {
                NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                     [NSString stringWithFormat:@"%@-%@.udcx", [[NSUUID UUID] UUIDString], update.version]];
                if ([data writeToFile:path atomically:YES]) {
                    installed = [UDInstalledExtensions installPackageAtPath:path error:&problem];
                    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
                } else {
                    problem = UDUpdateError(@"Its package couldn't be saved to be installed.");
                }
            }
            if (installed) {
                [self _setAvailable:nil forIdentifier:update.identifier];
                [[NSNotificationCenter defaultCenter] postNotificationName:UDExtensionUpdatesDidChangeNotification object:self];
            } else if (problem) {
                NSLog(@"UDExtensionUpdates: %@ %@ not installed: %@", update.identifier, update.version, problem.localizedDescription);
            }
            if (completion) completion(installed, installed ? nil : problem);
        });
    });
}

/// @a updates installed, when they are to be.
- (void)_installIfAutomatic:(NSArray<UDExtensionUpdate *> *)updates {
    if (!self.automaticallyUpdates) return;
    for (UDExtensionUpdate *update in updates) [self installUpdate:update completion:nil];
}

- (void)checkAtStart {
    NSDate *last = self.lastCheck;
    if (last && -[last timeIntervalSinceNow] < 24 * 60 * 60) return;
    [self checkExtensions:[UDInstalledExtensions installed] completion:^(NSArray<UDExtensionUpdate *> *updates) {
        [self _installIfAutomatic:updates];
    }];
}

- (void)checkNowCompletion:(void (^)(NSArray<UDExtensionUpdate *> *))completion {
    [self checkExtensions:[UDInstalledExtensions installed] completion:^(NSArray<UDExtensionUpdate *> *updates) {
        [self _installIfAutomatic:updates];
        if (completion) completion(updates);
    }];
}

// ---------------------------------------------------------------------------
// MARK: - Shipped with UDCode
// ---------------------------------------------------------------------------

+ (NSArray<UDExtensionInfo *> *)installShippedPackagesInFolder:(NSString *)folder {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *done = [[defaults arrayForKey:UDShippedExtensionsInstalledKey] mutableCopy] ?: [NSMutableArray array];
    NSMutableArray<UDExtensionInfo *> *installed = [NSMutableArray array];
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        // each package once: one installed, then updated or uninstalled, is left so
        if (![name.pathExtension isEqualToString:@"udcx"] || [done containsObject:name]) continue;
        NSError *error = nil;
        UDExtensionInfo *info = [UDInstalledExtensions installPackageAtPath:[folder stringByAppendingPathComponent:name] error:&error];
        if (!info) {
            NSLog(@"UDExtensionUpdates: %@, shipped with UDCode, not installed: %@", name, error.localizedDescription);
            continue;
        }
        [installed addObject:info];
        [done addObject:name];
    }
    [defaults setObject:done forKey:UDShippedExtensionsInstalledKey];
    return installed;
}

@end
