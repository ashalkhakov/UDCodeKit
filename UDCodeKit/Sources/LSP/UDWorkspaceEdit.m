/*---------------------------------------------------------------------------------------------
 *  UDWorkspaceEdit.m
 *--------------------------------------------------------------------------------------------*/

#import "UDWorkspaceEdit.h"
#import <UDPieceTable/UDPieceTable.h>

@implementation UDWorkspaceEdit

/// Each file's TextEdits, by its URL, from either of LSP's shapes.
+ (NSDictionary<NSURL *, NSArray<NSDictionary *> *> *)_editsByFile:(NSDictionary *)edit {
    NSMutableDictionary<NSURL *, NSMutableArray *> *files = [NSMutableDictionary dictionary];
    NSDictionary *changes = [edit[@"changes"] isKindOfClass:[NSDictionary class]] ? edit[@"changes"] : nil;
    for (NSString *uri in changes) {
        NSURL *url = [NSURL URLWithString:uri];
        if (!url || ![changes[uri] isKindOfClass:[NSArray class]]) continue;
        if (!files[url]) files[url] = [NSMutableArray array];
        [files[url] addObjectsFromArray:changes[uri]];
    }
    NSArray *documentChanges = [edit[@"documentChanges"] isKindOfClass:[NSArray class]] ? edit[@"documentChanges"] : nil;
    for (NSDictionary *change in documentChanges) {
        if (![change isKindOfClass:[NSDictionary class]] || ![change[@"edits"] isKindOfClass:[NSArray class]]) continue;
        NSString *uri = [change[@"textDocument"] isKindOfClass:[NSDictionary class]] ? change[@"textDocument"][@"uri"] : nil;
        NSURL *url = [uri isKindOfClass:[NSString class]] ? [NSURL URLWithString:uri] : nil;
        if (!url) continue;
        if (!files[url]) files[url] = [NSMutableArray array];
        [files[url] addObjectsFromArray:change[@"edits"]];
    }
    return files;
}

+ (NSArray<NSURL *> *)applyEdit:(NSDictionary *)edit documents:(id<UDWorkspaceEditDocuments>)documents error:(NSError **)error {
    NSMutableArray<NSURL *> *changed = [NSMutableArray array];
    if (![edit isKindOfClass:[NSDictionary class]]) return changed;
    NSDictionary<NSURL *, NSArray *> *files = [self _editsByFile:edit];
    for (NSURL *url in files) {
        NSArray *edits = files[url];
        if (!edits.count) continue;
        UDTextModel *model = [documents textModelForFileURL:url];
        if (model) {
            [self applyTextEdits:edits toTextModel:model];
            [changed addObject:url];
            continue;
        }
        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
        NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (!text) continue;
        NSString *edited = [self string:text withTextEdits:edits];
        if ([edited writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:error]) [changed addObject:url];
    }
    return changed;
}

+ (NSArray<NSDictionary *> *)textEditsOfFileURL:(NSURL *)url inEdit:(NSDictionary *)edit {
    NSDictionary<NSURL *, NSArray *> *files = [self _editsByFile:edit];
    NSString *path = url.path.stringByStandardizingPath;
    for (NSURL *file in files) {
        if ([file.path.stringByStandardizingPath isEqualToString:path]) return files[file];
    }
    return @[];
}

+ (NSDictionary *)edit:(NSDictionary *)edit withNewText:(NSString *)text excludingFileURL:(NSURL *)url {
    NSDictionary<NSURL *, NSArray *> *files = [self _editsByFile:edit];
    NSString *path = url.path.stringByStandardizingPath;
    NSMutableDictionary<NSString *, NSArray *> *changes = [NSMutableDictionary dictionary];
    for (NSURL *file in files) {
        if (path && [file.path.stringByStandardizingPath isEqualToString:path]) continue;
        NSMutableArray *edits = [NSMutableArray array];
        for (NSDictionary *textEdit in files[file]) {
            if (![textEdit isKindOfClass:[NSDictionary class]]) continue;
            NSMutableDictionary *renamed = [textEdit mutableCopy];
            renamed[@"newText"] = text;
            [edits addObject:renamed];
        }
        changes[file.absoluteString] = edits;
    }
    return @{ @"changes": changes };
}

/// A position ({line, character}) as an index of @a lineStarts' text.
static NSUInteger UDIndexOfPosition(NSDictionary *position, NSArray<NSNumber *> *lineStarts, NSUInteger length) {
    NSInteger line = [position[@"line"] integerValue];
    NSInteger character = [position[@"character"] integerValue];
    if (line < 0) return 0;
    if ((NSUInteger)line >= lineStarts.count) return length;
    NSUInteger start = lineStarts[(NSUInteger)line].unsignedIntegerValue;
    NSUInteger next = (NSUInteger)line + 1 < lineStarts.count ? lineStarts[(NSUInteger)line + 1].unsignedIntegerValue : length;
    return MIN(start + (NSUInteger)MAX(character, 0), next);
}

/// The edits, last first (so an earlier one's indexes still hold), sorted by their start.
static NSArray<NSDictionary *> *UDEditsLastFirst(NSArray<NSDictionary *> *edits) {
    return [edits sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSDictionary *sa = a[@"range"][@"start"], *sb = b[@"range"][@"start"];
        NSInteger la = [sa[@"line"] integerValue], lb = [sb[@"line"] integerValue];
        if (la != lb) return la > lb ? NSOrderedAscending : NSOrderedDescending;
        NSInteger ca = [sa[@"character"] integerValue], cb = [sb[@"character"] integerValue];
        return ca > cb ? NSOrderedAscending : ca < cb ? NSOrderedDescending : NSOrderedSame;
    }];
}

+ (NSString *)string:(NSString *)text withTextEdits:(NSArray<NSDictionary *> *)edits {
    NSMutableArray<NSNumber *> *lineStarts = [NSMutableArray arrayWithObject:@0];
    for (NSUInteger i = 0; i < text.length; i++) {
        if ([text characterAtIndex:i] == '\n') [lineStarts addObject:@(i + 1)];
    }
    NSMutableString *result = [text mutableCopy];
    for (NSDictionary *edit in UDEditsLastFirst(edits)) {
        if (![edit isKindOfClass:[NSDictionary class]]) continue;
        NSUInteger from = UDIndexOfPosition(edit[@"range"][@"start"], lineStarts, text.length);
        NSUInteger to = UDIndexOfPosition(edit[@"range"][@"end"], lineStarts, text.length);
        if (to < from) continue;
        NSString *replacement = [edit[@"newText"] isKindOfClass:[NSString class]] ? edit[@"newText"] : @"";
        [result replaceCharactersInRange:NSMakeRange(from, to - from) withString:replacement];
    }
    return result;
}

+ (void)applyTextEdits:(NSArray<NSDictionary *> *)edits toTextModel:(UDTextModel *)model {
    NSMutableArray<UDTextModelEdit *> *modelEdits = [NSMutableArray array];
    for (NSDictionary *edit in UDEditsLastFirst(edits)) {
        if (![edit isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *start = edit[@"range"][@"start"], *end = edit[@"range"][@"end"];
        // the model's lines and columns are 1-based
        UDRange range = PTRangeMake([start[@"line"] integerValue] + 1, [start[@"character"] integerValue] + 1,
                                    [end[@"line"] integerValue] + 1, [end[@"character"] integerValue] + 1);
        NSString *replacement = [edit[@"newText"] isKindOfClass:[NSString class]] ? edit[@"newText"] : @"";
        [modelEdits addObject:[[UDTextModelEdit alloc] initWithRange:range text:replacement]];
    }
    if (modelEdits.count) [model applyEdits:modelEdits];
}

@end
