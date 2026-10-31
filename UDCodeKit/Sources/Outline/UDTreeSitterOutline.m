/*---------------------------------------------------------------------------------------------
 *  UDTreeSitterOutline.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTreeSitterOutline.h"
#import <tree_sitter/api.h>

@implementation UDTreeSitterOutline {
    TSQuery *_query;
    TSQueryCursor *_cursor;
}

- (instancetype)initWithLanguageFunc:(LanguageFunc)languageFunc query:(NSString *)query {
    self = [super init];
    if (!self) return nil;
    const TSLanguage *language = languageFunc ? languageFunc() : NULL;
    const char *utf8 = [query cStringUsingEncoding:NSUTF8StringEncoding];
    if (!language || !utf8) return nil;
    uint32_t errorOffset = 0;
    TSQueryError error = TSQueryErrorNone;
    _query = ts_query_new(language, utf8, (uint32_t)strlen(utf8), &errorOffset, &error);
    if (!_query || error != TSQueryErrorNone) {
        NSLog(@"UDTreeSitterOutline: outline query error %d at offset %u", error, errorOffset);
        if (_query) ts_query_delete(_query);
        _query = NULL;
        return nil;
    }
    _cursor = ts_query_cursor_new();
    return self;
}

- (void)dealloc {
    if (_cursor) ts_query_cursor_delete(_cursor);
    if (_query) ts_query_delete(_query);
}

static NSRange UDRangeOfNode(TSNode node) {
    NSUInteger start = UDCharIndexFromByte(ts_node_start_byte(node)), end = UDCharIndexFromByte(ts_node_end_byte(node));
    return NSMakeRange(start, end > start ? end - start : 0);
}

static NSInteger UDCompareByLocation(NSDictionary *a, NSDictionary *b, void *context) {
    NSUInteger x = [a[@"range"] rangeValue].location, y = [b[@"range"] rangeValue].location;
    return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
}

- (NSArray<UDDocumentSymbol *> *)symbolsOfTree:(const void *)tree text:(NSString *)text {
    if (!tree) return @[];
    // each match: its node's range, kind, level (0: none), name and the name's range
    NSMutableArray<NSDictionary *> *found = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSDictionary *> *seen = [NSMutableDictionary dictionary];
    ts_query_cursor_exec(_cursor, _query, ts_tree_root_node((const TSTree *)tree));
    TSQueryMatch match;
    while (ts_query_cursor_next_match(_cursor, &match)) {
        NSRange range = NSMakeRange(NSNotFound, 0), selection = NSMakeRange(NSNotFound, 0);
        UDSymbolKind kind = 0;
        NSInteger level = 0;
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        NSMutableString *selector = [NSMutableString string];
        for (uint16_t i = 0; i < match.capture_count; i++) {
            TSQueryCapture capture = match.captures[i];
            uint32_t length = 0;
            const char *bytes = ts_query_capture_name_for_id(_query, capture.index, &length);
            NSString *captureName = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
            NSRange nodeRange = UDRangeOfNode(capture.node);
            if (NSMaxRange(nodeRange) > text.length) continue;
            if ([captureName isEqualToString:@"name"] || [captureName isEqualToString:@"selector"]) {
                NSString *name = [[text substringWithRange:nodeRange] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                // a selector's parts: Objective-C's initWithA:b:
                if ([captureName isEqualToString:@"selector"]) [selector appendFormat:@"%@:", name];
                else if (name.length) [names addObject:name];
                if (selection.location == NSNotFound) {
                    // the name's own text: past what it starts with (a heading's space)
                    NSString *raw = [text substringWithRange:nodeRange];
                    NSRange start = [raw rangeOfCharacterFromSet:[[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet]];
                    NSUInteger skip = start.location == NSNotFound ? 0 : start.location;
                    selection = NSMakeRange(nodeRange.location + skip, nodeRange.length - skip);
                }
            } else if ([captureName hasPrefix:@"symbol."]) {
                NSArray<NSString *> *parts = [captureName componentsSeparatedByString:@"."];
                kind = [UDDocumentSymbol kindNamed:parts[1]];
                level = parts.count > 2 ? [parts[2] integerValue] : 0;
                range = nodeRange;
            }
        }
        if (selector.length) [names addObject:selector];
        if (range.location == NSNotFound || !kind || !names.count) continue;
        NSString *name = [[names componentsJoinedByString:@" "] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        NSDictionary *symbol = @{ @"range": [NSValue valueWithRange:range], @"selection": [NSValue valueWithRange:selection],
                                  @"kind": @(kind), @"level": @(level), @"name": name };
        // two patterns, one symbol: the fuller name kept (a category's "Foo Cat")
        NSString *key = [NSString stringWithFormat:@"%@ %ld", NSStringFromRange(range), (long)kind];
        NSDictionary *before = seen[key];
        if (before && [before[@"name"] length] >= name.length) continue;
        if (before) [found removeObjectIdenticalTo:before];
        seen[key] = symbol;
        [found addObject:symbol];
    }
    [found sortUsingFunction:UDCompareByLocation context:NULL];
    NSMutableArray<UDDocumentSymbol *> *symbols = [NSMutableArray array];
    for (NSUInteger i = 0; i < found.count; i++) {
        NSDictionary *item = found[i];
        NSRange range = [item[@"range"] rangeValue];
        NSInteger level = [item[@"level"] integerValue];
        if (level > 0) {
            // a heading: up to the next of its level or above
            NSUInteger end = text.length;
            for (NSUInteger j = i + 1; j < found.count; j++) {
                NSInteger next = [found[j][@"level"] integerValue];
                if (next > 0 && next <= level) {
                    end = [found[j][@"range"] rangeValue].location;
                    break;
                }
            }
            range = NSMakeRange(range.location, MAX(end, NSMaxRange(range)) - range.location);
        }
        [symbols addObject:[[UDDocumentSymbol alloc] initWithName:item[@"name"] detail:nil kind:[item[@"kind"] integerValue]
                                                           range:range selectionRange:[item[@"selection"] rangeValue]]];
    }
    return [UDDocumentSymbol treeOfSymbols:symbols];
}

@end
