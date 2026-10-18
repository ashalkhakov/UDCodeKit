/*---------------------------------------------------------------------------------------------
 *  UDWorkspaceEdit.h
 *
 *  A language server's WorkspaceEdit (a rename's, a code action's, a
 *  formatting's text edits), applied as VS Code applies one: each file's edits
 *  at once, an open file's in its text model (one undoable edit, the editor
 *  following), a file no editor has rewritten on disk. Both of LSP's shapes:
 *  "changes" ({ uri: [TextEdit] }) and "documentChanges" ([{ textDocument,
 *  edits }]; create, rename and delete operations are not done).
 *
 *  Positions are LSP's: 0-based lines, UTF-16 characters, as NSString counts them.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

@class UDTextModel;

NS_ASSUME_NONNULL_BEGIN

@protocol UDWorkspaceEditDocuments <NSObject>
/// The text model of the file at @a url when an editor has it, nil otherwise.
- (nullable UDTextModel *)textModelForFileURL:(NSURL *)url;
@end

@interface UDWorkspaceEdit : NSObject

/// Applies @a edit; returns the files it changed (none: nothing applied).
/// A file that can't be read or written is left as it was, and says so in @a error.
+ (NSArray<NSURL *> *)applyEdit:(NSDictionary *)edit documents:(nullable id<UDWorkspaceEditDocuments>)documents
                          error:(NSError * _Nullable * _Nullable)error;

/// TextEdits ([{ range, newText }]) to one text model, at once.
+ (void)applyTextEdits:(NSArray<NSDictionary *> *)edits toTextModel:(UDTextModel *)model;
/// TextEdits to a string: the string they make.
+ (NSString *)string:(NSString *)text withTextEdits:(NSArray<NSDictionary *> *)edits;

@end

NS_ASSUME_NONNULL_END
