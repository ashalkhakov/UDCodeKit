/*---------------------------------------------------------------------------------------------
 *  UDDocument.m — UDWorkspace implementation.
 *
 *  Handles file I/O for two document kinds:
 *
 *    .udworkspace  JSON  {"version":1, "openFiles":[{"path":"/abs/path"},...]}
 *    anything else       The raw file content (treated as a single-tab workspace).
 *--------------------------------------------------------------------------------------------*/

#import "UDDocument.h"
#import "UDDocumentWindowController.h"
#import <UDPieceTable/UDPieceTable.h>

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface UDWorkspace ()
@end

// ---------------------------------------------------------------------------

@implementation UDWorkspace

// ---------------------------------------------------------------------------
// MARK: - Read / write
// ---------------------------------------------------------------------------

- (BOOL)readFromURL:(NSURL *)url
             ofType:(NSString *)typeName
              error:(NSError **)outError {

    if ([[url.pathExtension lowercaseString] isEqualToString:@"udworkspace"]) {
        // ---- Workspace file: parse JSON and restore the tab list ----
        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:outError];
        if (!data) return NO;

        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:outError];
        if (![obj isKindOfClass:[NSDictionary class]]) {
            if (outError && !*outError) {
                *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                               code:NSFileReadCorruptFileError
                                           userInfo:nil];
            }
            return NO;
        }

        NSMutableArray<NSURL *> *urls = [NSMutableArray array];
        NSArray *entries = obj[@"openFiles"];
        for (id entry in ([entries isKindOfClass:[NSArray class]] ? entries : @[])) {
            NSString *path = ([entry isKindOfClass:[NSDictionary class]])
                                ? entry[@"path"] : nil;
            if (path.length) [urls addObject:[NSURL fileURLWithPath:path]];
        }
        _initialTabURLs = [urls copy];

    } else {
        // ---- Plain file (e.g. JSON): single-tab workspace ----
        if (_primaryTextStorage) {
            // Window is already open — replace the primary tab's content
            // (e.g. File > Revert to Saved, or external change reload).
            NSString *content = [NSString stringWithContentsOfURL:url
                                                         encoding:NSUTF8StringEncoding
                                                            error:outError];
            if (!content) return NO;

            UDTextModel *model = _primaryTextStorage.textModel;
            NSInteger    len   = [model getLength];
            UDPosition   sp    = [model getPositionAt:0];
            UDPosition   ep    = [model getPositionAt:len];
            UDRange      r     = PTRangeMake(sp.line, sp.column, ep.line, ep.column);
            [model applyEdits:@[[[UDTextModelEdit alloc] initWithRange:r text:content]]];
        } else {
            // Initial load — the window controller will read the file when it opens.
            _initialTabURLs = @[url];
        }
    }
    return YES;
}

- (BOOL)writeToURL:(NSURL *)url
            ofType:(NSString *)typeName
             error:(NSError **)outError {

    if ([[url.pathExtension lowercaseString] isEqualToString:@"udworkspace"]) {
        // ---- Workspace file: serialise the current tab list ----
        UDDocumentWindowController *wc =
            (UDDocumentWindowController *)self.windowControllers.firstObject;
        NSArray<NSURL *> *openURLs = wc ? [wc currentOpenFileURLs] : @[];

        NSMutableArray<NSDictionary *> *files =
            [NSMutableArray arrayWithCapacity:openURLs.count];
        for (NSURL *u in openURLs) {
            [files addObject:@{@"path": u.path}];
        }
        NSDictionary *ws = @{@"version": @1, @"openFiles": files};

        NSError *jsonErr = nil;
        NSData  *data    = [NSJSONSerialization dataWithJSONObject:ws
                                                           options:NSJSONWritingPrettyPrinted
                                                             error:&jsonErr];
        if (!data) { if (outError) *outError = jsonErr; return NO; }
        return [data writeToURL:url options:NSDataWritingAtomic error:outError];

    } else {
        // ---- Plain file: write the primary tab's text content ----
        NSString *text = _primaryTextStorage
            ? [_primaryTextStorage.textModel getValue]
            : @"";
        return [text writeToURL:url
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:outError];
    }
}

- (BOOL)writeSafelyToURL:(NSURL *)url
                  ofType:(NSString *)typeName
        forSaveOperation:(NSSaveOperationType)op
                   error:(NSError **)outError {
    UDDocumentWindowController *wc =
        (UDDocumentWindowController *)self.windowControllers.firstObject;
    [wc documentWillSave];
    BOOL ok = [super writeSafelyToURL:url ofType:typeName
                      forSaveOperation:op error:outError];
    [wc documentDidSave:ok];
    return ok;
}

// ---------------------------------------------------------------------------
// MARK: - Window controllers
// ---------------------------------------------------------------------------

- (void)makeWindowControllers {
    UDDocumentWindowController *wc = [[UDDocumentWindowController alloc] init];
    [self addWindowController:wc];
}

// ---------------------------------------------------------------------------
// MARK: - Close
// ---------------------------------------------------------------------------

- (void)close {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super close];
}

@end
