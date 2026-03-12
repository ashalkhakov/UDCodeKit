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
#import "UDWorkspaceModel.h"
#import <UDPieceTable/UDPieceTable.h>
#import "UDTextModel.h"

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
        // ---- Workspace file: deserialise via UDWorkspaceModel ----
        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:outError];
        if (!data) return NO;

        UDWorkspaceModel *model =
            [UDWorkspaceModel workspaceModelFromData:data error:outError];
        if (!model) return NO;

        _workspaceModel = model;

    } else {
        // ---- Plain file (e.g. JSON): single-tab workspace ----
        if (_workspaceModel) {
            // Window is already open — replace the primary document's content
            // (e.g. File > Revert to Saved, or external change reload).
            UDCodeDocument *doc = _workspaceModel.documents.firstObject;
            if (doc) {
                NSString *content = [NSString stringWithContentsOfURL:url
                                                             encoding:NSUTF8StringEncoding
                                                                error:outError];
                if (!content) return NO;
                UDTextModel *model = doc.textModel;
                NSInteger    len   = [model getLength];
                UDPosition   sp    = [model getPositionAt:0];
                UDPosition   ep    = [model getPositionAt:len];
                UDRange      r     = PTRangeMake(sp.line, sp.column, ep.line, ep.column);
                [model applyEdits:@[[[UDTextModelEdit alloc] initWithRange:r text:content]]];
                return YES;
            }
        }
        // Initial load — the window controller will open the file when it loads.
        _initialTabURLs = @[url];
    }
    return YES;
}

- (BOOL)writeToURL:(NSURL *)url
            ofType:(NSString *)typeName
             error:(NSError **)outError {

    if ([[url.pathExtension lowercaseString] isEqualToString:@"udworkspace"]) {
        // ---- Workspace file: serialise via workspace model ----
        UDDocumentWindowController *wc =
            (UDDocumentWindowController *)self.windowControllers.firstObject;

        // Build a lightweight model containing only the open file URLs so
        // we capture any tabs opened after the workspace was first loaded.
        UDWorkspaceModel *snapshot = [[UDWorkspaceModel alloc] init];
        for (NSURL *u in [wc currentOpenFileURLs]) {
            [snapshot addDocumentWithText:@"" fileURL:u];
        }

        NSData *data = [snapshot serializeToDataWithError:outError];
        if (!data) return NO;
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
