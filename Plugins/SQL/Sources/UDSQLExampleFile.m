/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleFile.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLExampleFile.h"

static NSString *const UDKind = @"UDCode query by example";

@implementation UDSQLExampleFileSkeleton

+ (instancetype)skeletonOfTable:(NSString *)table schema:(NSString *)schema {
    UDSQLExampleFileSkeleton *skeleton = [[self alloc] init];
    skeleton.table = table;
    skeleton.schema = schema;
    skeleton.rows = @[ [UDSQLExampleRow rowWithEntries:@{}] ];
    return skeleton;
}

@end

/// A JSON boolean, as such (an NSNumber's boxing isn't the same everywhere).
@interface UDJSONBoolean : NSObject
+ (instancetype)of:(BOOL)value;
@property (nonatomic, readonly) BOOL value;
@end

@implementation UDJSONBoolean

+ (instancetype)of:(BOOL)value {
    UDJSONBoolean *boolean = [[self alloc] init];
    boolean->_value = value;
    return boolean;
}

@end

/// @a value as JSON, the same everywhere (as git diffs it): keys sorted,
/// two spaces a level, an empty array or object on one line.
static void UDWriteJSON(id value, NSMutableString *out, NSUInteger depth) {
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    NSString *inner = [@"" stringByPaddingToLength:(depth + 1) * 2 withString:@" " startingAtIndex:0];
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [[value allKeys] sortedArrayUsingSelector:@selector(compare:)];
        if (!keys.count) {
            [out appendString:@"{}"];
            return;
        }
        [out appendString:@"{\n"];
        for (NSUInteger i = 0; i < keys.count; i++) {
            [out appendString:inner];
            UDWriteJSON(keys[i], out, depth + 1);
            [out appendString:@": "];
            UDWriteJSON(value[keys[i]], out, depth + 1);
            [out appendString:i + 1 < keys.count ? @",\n" : @"\n"];
        }
        [out appendFormat:@"%@}", indent];
    } else if ([value isKindOfClass:[NSArray class]]) {
        NSArray *items = value;
        if (!items.count) {
            [out appendString:@"[]"];
            return;
        }
        [out appendString:@"[\n"];
        for (NSUInteger i = 0; i < items.count; i++) {
            [out appendString:inner];
            UDWriteJSON(items[i], out, depth + 1);
            [out appendString:i + 1 < items.count ? @",\n" : @"\n"];
        }
        [out appendFormat:@"%@]", indent];
    } else if ([value isKindOfClass:[NSString class]]) {
        NSMutableString *text = [NSMutableString stringWithString:@"\""];
        for (NSUInteger i = 0; i < [value length]; i++) {
            unichar c = [value characterAtIndex:i];
            if (c == '"' || c == '\\') [text appendFormat:@"\\%C", c];
            else if (c == '\n') [text appendString:@"\\n"];
            else if (c == '\t') [text appendString:@"\\t"];
            else if (c == '\r') [text appendString:@"\\r"];
            else if (c < 0x20) [text appendFormat:@"\\u%04x", c];
            else [text appendFormat:@"%C", c];
        }
        [text appendString:@"\""];
        [out appendString:text];
    } else if ([value isKindOfClass:[UDJSONBoolean class]]) {
        [out appendString:[(UDJSONBoolean *)value value] ? @"true" : @"false"];
    } else {
        [out appendString:[value description]];
    }
}

@implementation UDSQLExampleFile

- (instancetype)init {
    self = [super init];
    if (self) {
        _skeletons = @[];
        _order = @[];
        _conditions = @[];
    }
    return self;
}

static NSError *UDFileError(NSString *message) {
    return [NSError errorWithDomain:UDSQLErrorDomain code:-1 userInfo:@{ NSLocalizedDescriptionKey: message }];
}

+ (instancetype)fileWithData:(NSData *)data error:(NSError **)error {
    NSError *failure = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&failure];
    if (![root isKindOfClass:[NSDictionary class]] || ![root[@"kind"] isEqual:UDKind]) {
        if (error) *error = failure ?: UDFileError(@"This isn't a query by example's file.");
        return nil;
    }
    if ([root[@"version"] integerValue] > 1) {
        if (error) *error = UDFileError(@"This query by example was saved by a newer UDCode.");
        return nil;
    }
    UDSQLExampleFile *file = [[self alloc] init];
    NSMutableArray *skeletons = [NSMutableArray array];
    for (NSDictionary *kept in [root[@"skeletons"] isKindOfClass:[NSArray class]] ? root[@"skeletons"] : @[]) {
        if (![kept isKindOfClass:[NSDictionary class]] || ![kept[@"table"] isKindOfClass:[NSString class]]) continue;
        UDSQLExampleFileSkeleton *skeleton = [UDSQLExampleFileSkeleton skeletonOfTable:kept[@"table"]
                                                                                schema:[kept[@"schema"] isKindOfClass:[NSString class]] ? kept[@"schema"] : nil];
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *row in [kept[@"rows"] isKindOfClass:[NSArray class]] ? kept[@"rows"] : @[]) {
            if (![row isKindOfClass:[NSDictionary class]]) continue;
            NSMutableDictionary *entries = [NSMutableDictionary dictionary];
            NSDictionary *typed = [row[@"entries"] isKindOfClass:[NSDictionary class]] ? row[@"entries"] : @{};
            for (NSString *column in typed) if ([typed[column] isKindOfClass:[NSString class]]) entries[column] = typed[column];
            UDSQLExampleRow *made = [UDSQLExampleRow rowWithEntries:entries];
            made.negated = [row[@"negated"] boolValue];
            made.inclusive = [row[@"inclusive"] boolValue];
            [rows addObject:made];
        }
        if (rows.count) skeleton.rows = rows;
        [skeletons addObject:skeleton];
    }
    file.skeletons = skeletons;
    NSMutableArray *order = [NSMutableArray array];
    for (NSDictionary *key in [root[@"order"] isKindOfClass:[NSArray class]] ? root[@"order"] : @[]) {
        if (![key isKindOfClass:[NSDictionary class]] || ![key[@"column"] isKindOfClass:[NSString class]]) continue;
        [order addObject:[NSSortDescriptor sortDescriptorWithKey:key[@"column"] ascending:key[@"ascending"] ? [key[@"ascending"] boolValue] : YES]];
    }
    file.order = order;
    NSMutableArray *conditions = [NSMutableArray array];
    for (NSString *line in [root[@"conditions"] isKindOfClass:[NSArray class]] ? root[@"conditions"] : @[]) {
        if ([line isKindOfClass:[NSString class]]) [conditions addObject:line];
    }
    file.conditions = conditions;
    return file;
}

- (NSData *)data {
    NSMutableArray *skeletons = [NSMutableArray array];
    for (UDSQLExampleFileSkeleton *skeleton in _skeletons) {
        NSMutableArray *rows = [NSMutableArray array];
        for (UDSQLExampleRow *row in skeleton.rows) {
            // what is typed only: an empty entry kept by none
            NSMutableDictionary *entries = [NSMutableDictionary dictionary];
            for (NSString *column in row.entries) {
                NSString *typed = [row.entries[column] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (typed.length) entries[column] = typed;
            }
            NSMutableDictionary *kept = [@{ @"entries": entries } mutableCopy];
            if (row.negated) kept[@"negated"] = [UDJSONBoolean of:YES];
            if (row.inclusive) kept[@"inclusive"] = [UDJSONBoolean of:YES];
            [rows addObject:kept];
        }
        NSMutableDictionary *kept = [@{ @"table": skeleton.table, @"rows": rows } mutableCopy];
        if (skeleton.schema.length) kept[@"schema"] = skeleton.schema;
        [skeletons addObject:kept];
    }
    NSMutableArray *order = [NSMutableArray array];
    for (NSSortDescriptor *key in _order) [order addObject:@{ @"column": key.key, @"ascending": [UDJSONBoolean of:key.ascending] }];
    NSMutableDictionary *root = [@{ @"kind": UDKind, @"version": @1, @"skeletons": skeletons, @"order": order } mutableCopy];
    // the condition box's lines, typed ones (none: not written)
    NSMutableArray *conditions = [NSMutableArray array];
    for (NSString *line in _conditions) {
        NSString *typed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (typed.length) [conditions addObject:typed];
    }
    if (conditions.count) root[@"conditions"] = conditions;
    NSMutableString *json = [NSMutableString string];
    UDWriteJSON(root, json, 0);
    [json appendString:@"\n"];
    return [json dataUsingEncoding:NSUTF8StringEncoding];
}

- (UDSQLExampleQuery *)queryForSchema:(UDSQLSchema *)schema dialect:(UDSQLDialect)dialect databaseName:(NSString *)name
                                error:(NSError **)error {
    NSMutableArray *skeletons = [NSMutableArray array];
    for (UDSQLExampleFileSkeleton *kept in _skeletons) {
        UDSQLTable *table = nil;
        for (UDSQLTable *candidate in schema.tables) {
            BOOL sameSchema = !kept.schema.length || [candidate.schema isEqualToString:kept.schema];
            if ([candidate.name isEqualToString:kept.table] && sameSchema) table = candidate;
        }
        if (!table) {
            NSString *named = kept.schema.length ? [NSString stringWithFormat:@"%@.%@", kept.schema, kept.table] : kept.table;
            if (error) *error = UDFileError([NSString stringWithFormat:@"%@ has no table %@.", name, named]);
            return nil;
        }
        [skeletons addObject:[UDSQLExampleSkeleton skeletonOf:table rows:kept.rows]];
    }
    UDSQLExampleQuery *query = [[UDSQLExampleQuery alloc] initWithSchema:schema dialect:dialect];
    query.skeletons = skeletons;
    query.order = _order;
    query.conditions = _conditions;
    return query;
}

@end
