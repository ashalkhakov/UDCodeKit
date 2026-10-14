/*---------------------------------------------------------------------------------------------
 *  UDWorkspaceModel.m
 *--------------------------------------------------------------------------------------------*/

#import "UDWorkspaceModel.h"

NSNotificationName const UDWorkspaceModelDidChangeNotification =
    @"UDWorkspaceModelDidChangeNotification";

@implementation UDWorkspaceModel {
    NSMutableArray<UDCodeDocument *> *_documents;
}

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _documents = [NSMutableArray array];
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - KVO accessor
// ---------------------------------------------------------------------------

- (NSArray<UDCodeDocument *> *)documents {
    return [_documents copy];
}

// ---------------------------------------------------------------------------
// MARK: - Document management
// ---------------------------------------------------------------------------

- (UDCodeDocument *)addDocumentWithText:(NSString *)text
                                fileURL:(nullable NSURL *)fileURL {
    return [self addDocumentWithText:text fileURL:fileURL languageMode:nil];
}

- (UDCodeDocument *)addDocumentWithText:(NSString *)text
                                fileURL:(nullable NSURL *)fileURL
                           languageMode:(nullable UDLanguageMode *)languageMode {
    if (fileURL) {
        UDCodeDocument *existing = [self documentForFileURL:fileURL];
        if (existing) return existing;
    }
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:text fileURL:fileURL languageMode:languageMode];
    [self _appendDocument:doc];
    return doc;
}

- (nullable UDCodeDocument *)addDocumentFromURL:(NSURL *)url
                                          error:(NSError *__autoreleasing *)outError {
    UDCodeDocument *existing = [self documentForFileURL:url];
    if (existing) return existing;

    UDCodeDocument *doc = [UDCodeDocument documentFromURL:url error:outError];
    if (!doc) return nil;

    [self _appendDocument:doc];
    return doc;
}

- (void)removeDocument:(UDCodeDocument *)document {
    if (![_documents containsObject:document]) return;
    [self willChangeValueForKey:@"documents"];
    [_documents removeObject:document];
    [self didChangeValueForKey:@"documents"];
    [self _postChangeNotification];
}

- (nullable UDCodeDocument *)documentForFileURL:(NSURL *)url {
    for (UDCodeDocument *doc in _documents) {
        if ([doc.fileURL isEqual:url]) return doc;
    }
    return nil;
}

- (nullable UDCodeDocument *)documentForDiagnosticStore:(UDDiagnosticStore *)store {
    for (UDCodeDocument *doc in _documents) {
        if (doc.diagnosticStore == store) return doc;
    }
    return nil;
}

// ---------------------------------------------------------------------------
// MARK: - Serialisation
// ---------------------------------------------------------------------------

+ (nullable instancetype)workspaceModelFromData:(NSData *)data
                                          error:(NSError *__autoreleasing *)outError {
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:outError];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        if (outError && !*outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                           code:NSFileReadCorruptFileError
                                       userInfo:nil];
        }
        return nil;
    }

    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];

    NSArray *entries = obj[@"openFiles"];
    if ([entries isKindOfClass:[NSArray class]]) {
        for (id entry in entries) {
            NSString *path = ([entry isKindOfClass:[NSDictionary class]])
                                ? entry[@"path"] : nil;
            if (!path.length) continue;

            NSURL *url = [NSURL fileURLWithPath:path];
            NSError *loadErr = nil;
            [model addDocumentFromURL:url error:&loadErr];
            if (loadErr) {
                NSLog(@"[UDWorkspaceModel] Cannot load '%@': %@", path, loadErr);
            }
        }
    }
    return model;
}

- (nullable NSData *)serializeToDataWithError:(NSError *__autoreleasing *)outError {
    NSMutableArray<NSDictionary *> *files =
        [NSMutableArray arrayWithCapacity:_documents.count];
    for (UDCodeDocument *doc in _documents) {
        if (doc.fileURL) [files addObject:@{@"path": doc.fileURL.path}];
    }
    NSDictionary *ws = @{@"version": @1, @"openFiles": files};
    return [NSJSONSerialization dataWithJSONObject:ws
                                           options:NSJSONWritingPrettyPrinted
                                             error:outError];
}

// ---------------------------------------------------------------------------
// MARK: - Private helpers
// ---------------------------------------------------------------------------

- (void)_appendDocument:(UDCodeDocument *)doc {
    [self willChangeValueForKey:@"documents"];
    [_documents addObject:doc];
    [self didChangeValueForKey:@"documents"];
    [self _postChangeNotification];
}

- (void)_postChangeNotification {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:UDWorkspaceModelDidChangeNotification
                      object:self];
}

@end
