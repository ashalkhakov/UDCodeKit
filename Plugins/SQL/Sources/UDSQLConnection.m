/*---------------------------------------------------------------------------------------------
 *  UDSQLConnection.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLDrivers.h"
#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

NSErrorDomain const UDSQLErrorDomain = @"UDSQLErrorDomain";
NSString *const UDSQLStateErrorKey = @"UDSQLState";

NSError *UDSQLError(NSInteger code, NSString *message, NSString *state) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message ?: @"The database failed." forKey:NSLocalizedDescriptionKey];
    if (state.length) info[UDSQLStateErrorKey] = state;
    return [NSError errorWithDomain:UDSQLErrorDomain code:code userInfo:info];
}

@implementation UDSQLColumn

- (instancetype)initWithName:(NSString *)name type:(NSString *)type {
    self = [super init];
    if (self) {
        _name = [name copy];
        _type = [type copy];
    }
    return self;
}

@end

@implementation UDSQLResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _statement = @"";
        _columns = @[];
        _rows = @[];
        _rowsAffected = -1;
    }
    return self;
}

@end

@implementation UDSQLConnection

+ (NSArray<NSString *> *)schemes {
    return @[ @"file", @"sqlite", @"postgresql", @"postgres", @"mysql", @"mariadb" ];
}

+ (NSInteger)dialectOfURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"file"] || [scheme isEqualToString:@"sqlite"]) return UDSQLDialectSQLite;
    if ([scheme isEqualToString:@"postgresql"] || [scheme isEqualToString:@"postgres"]) return UDSQLDialectPostgreSQL;
    if ([scheme isEqualToString:@"mysql"] || [scheme isEqualToString:@"mariadb"]) return UDSQLDialectMySQL;
    return -1;
}

+ (instancetype)connectionToURL:(NSURL *)url password:(NSString *)password error:(NSError **)error {
    switch ([self dialectOfURL:url]) {
        case UDSQLDialectSQLite: return [UDSQLiteConnection openURL:url password:password error:error];
        case UDSQLDialectPostgreSQL: return [UDPostgreSQLConnection openURL:url password:password error:error];
        case UDSQLDialectMySQL: return [UDMySQLConnection openURL:url password:password error:error];
        default:
            if (error) *error = UDSQLError(0, [NSString stringWithFormat:@"No driver speaks “%@:”.", url.scheme ?: @""], nil);
            return nil;
    }
}

- (instancetype)initWithURL:(NSURL *)url dialect:(UDSQLDialect)dialect {
    self = [super init];
    if (self) {
        _URL = [url copy];
        _dialect = dialect;
        _serverDescription = @"";
    }
    return self;
}

- (UDSQLResult *)execute:(NSString *)sql parameters:(NSArray *)parameters maxRows:(NSUInteger)maxRows error:(NSError **)error {
    if (error) *error = UDSQLError(0, @"Not connected.", nil);
    return nil;
}

- (void)cancel {
}

- (void)close {
}

- (NSString *)quotedIdentifier:(NSString *)name {
    return [NSString stringWithFormat:@"\"%@\"", [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

@end

// ---------------------------------------------------------------------------
// MARK: - A library loaded when first needed
// ---------------------------------------------------------------------------

@implementation UDSQLLibrary {
    void *_handle;
}

+ (NSString *)ownDirectory {
#if defined(__APPLE__)
    return [NSBundle mainBundle].privateFrameworksPath;
#elif defined(_WIN32)
    // beside gnustep-base's DLL (where the installer puts them, the packager
    // the DLLs they link in the runtime's bin): not UDCode.exe's folder,
    // where they would stand in for the runtime's own
    HMODULE base = NULL;
    wchar_t file[MAX_PATH];
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCWSTR)(void *)&NSLog, &base)) return nil;
    DWORD length = GetModuleFileNameW(base, file, MAX_PATH);
    if (!length || length >= MAX_PATH) return nil;
    NSString *path = [[NSString alloc] initWithBytes:file length:length * sizeof(wchar_t) encoding:NSUTF16LittleEndianStringEncoding];
    return [path stringByDeletingLastPathComponent];
#else
    // the AppImage's, when UDCode is the app it runs (APPDIR is inherited
    // by whatever an app in another image starts)
    NSString *image = [[NSProcessInfo processInfo] environment][@"APPDIR"];
    if (!image.length || ![[NSBundle mainBundle].bundlePath hasPrefix:image]) return nil;
    return [image stringByAppendingPathComponent:@"usr/lib"];
#endif
}

+ (NSArray<NSString *> *)candidatesForNames:(NSArray<NSString *> *)names {
    NSMutableArray *candidates = [NSMutableArray array];
    NSString *own = [self ownDirectory];
    for (NSString *name in names) {
        if (own.length && [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\"]].location == NSNotFound) {
            [candidates addObject:[own stringByAppendingPathComponent:name]];
        }
    }
    [candidates addObjectsFromArray:names];
    return candidates;
}

+ (instancetype)libraryForKey:(NSString *)key names:(NSArray<NSString *> *)names install:(NSString *)install error:(NSError **)error {
    static NSMutableDictionary<NSString *, UDSQLLibrary *> *loaded;
    @synchronized (self) {
        if (!loaded) loaded = [NSMutableDictionary dictionary];
        UDSQLLibrary *library = loaded[key];
        if (library) return library;
        NSString *own = [self ownDirectory];
        for (NSString *name in [self candidatesForNames:names]) {
#ifdef _WIN32
            // a library's own libraries looked for beside it first (UDCode's
            // copies), then where Windows looks; which wants backslashes
            NSString *file = [name stringByReplacingOccurrencesOfString:@"/" withString:@"\\"];
            void *handle = (void *)LoadLibraryExW((const wchar_t *)[file cStringUsingEncoding:NSUTF16LittleEndianStringEncoding], NULL,
                                                  [name isAbsolutePath] ? LOAD_WITH_ALTERED_SEARCH_PATH : 0);
#else
            void *handle = dlopen(name.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
#endif
            if (!handle) continue;
            library = [[UDSQLLibrary alloc] init];
            library->_handle = handle;
            library->_path = [name copy];
            library->_own = own.length && [[name stringByDeletingLastPathComponent] isEqualToString:own];
            loaded[key] = library;
            return library;
        }
        if (error) {
            *error = UDSQLError(0, [NSString stringWithFormat:@"%@ isn't installed. %@", key, install], nil);
        }
        return nil;
    }
}

- (void *)function:(const char *)name {
#ifdef _WIN32
    return (void *)GetProcAddress((HMODULE)_handle, name);
#else
    return dlsym(_handle, name);
#endif
}

@end
