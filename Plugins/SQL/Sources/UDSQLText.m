/*---------------------------------------------------------------------------------------------
 *  UDSQLText.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLText.h"

/// What one pass over the text found: where its statements end, and its
/// parameters (each its range and name).
typedef struct {
    NSMutableArray<NSValue *> *semicolons;
    NSMutableArray<NSValue *> *parameters;
    NSMutableArray<NSString *> *names;
} UDScan;

static BOOL UDIsNameStart(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c > 127;
}

static BOOL UDIsNamePart(unichar c) {
    return UDIsNameStart(c) || (c >= '0' && c <= '9');
}

static BOOL UDIsDigit(unichar c) {
    return c >= '0' && c <= '9';
}

/// The end of a quoted run starting at @a i (its quote @a quote), a doubled
/// quote inside it one character; backslashes escape in MySQL's strings and
/// PostgreSQL's E'…'.
static NSUInteger UDSkipQuoted(NSString *text, NSUInteger i, unichar quote, BOOL backslashes) {
    NSUInteger length = text.length;
    for (i++; i < length; i++) {
        unichar c = [text characterAtIndex:i];
        if (backslashes && c == '\\') {
            i++;
        } else if (c == quote) {
            if (i + 1 < length && [text characterAtIndex:i + 1] == quote) i++;
            else return i + 1;
        }
    }
    return length;
}

/// The end of SQLite's [identifier] starting at @a i.
static NSUInteger UDSkipBracketed(NSString *text, NSUInteger i) {
    NSRange end = [text rangeOfString:@"]" options:0 range:NSMakeRange(i, text.length - i)];
    return end.location == NSNotFound ? text.length : NSMaxRange(end);
}

static void UDScanText(NSString *text, UDSQLDialect dialect, UDScan *scan) {
    NSUInteger length = text.length, i = 0;
    NSUInteger plain = 0;           // plain ?s so far
    while (i < length) {
        unichar c = [text characterAtIndex:i];
        unichar next = i + 1 < length ? [text characterAtIndex:i + 1] : 0;
        if (c == '-' && next == '-') {
            NSRange line = [text rangeOfString:@"\n" options:0 range:NSMakeRange(i, length - i)];
            i = line.location == NSNotFound ? length : NSMaxRange(line);
        } else if (c == '#' && dialect == UDSQLDialectMySQL) {
            NSRange line = [text rangeOfString:@"\n" options:0 range:NSMakeRange(i, length - i)];
            i = line.location == NSNotFound ? length : NSMaxRange(line);
        } else if (c == '/' && next == '*') {
            NSRange end = [text rangeOfString:@"*/" options:0 range:NSMakeRange(i + 2, length - i - 2)];
            i = end.location == NSNotFound ? length : NSMaxRange(end);
        } else if (c == '\'') {
            BOOL escaped = dialect == UDSQLDialectMySQL ||
                           (i > 0 && ([text characterAtIndex:i - 1] == 'E' || [text characterAtIndex:i - 1] == 'e'));
            i = UDSkipQuoted(text, i, '\'', escaped);
        } else if (c == '"' || (c == '`' && dialect == UDSQLDialectMySQL) || (c == '[' && dialect == UDSQLDialectSQLite)) {
            i = c == '[' ? UDSkipBracketed(text, i) : UDSkipQuoted(text, i, c, dialect == UDSQLDialectMySQL && c == '"');
        } else if (c == '$' && dialect == UDSQLDialectPostgreSQL && (next == '$' || UDIsNameStart(next)) &&
                   !(i > 0 && UDIsNamePart([text characterAtIndex:i - 1]))) {
            // a dollar-quoted string: $tag$ … $tag$
            NSUInteger tagEnd = i + 1;
            while (tagEnd < length && UDIsNamePart([text characterAtIndex:tagEnd])) tagEnd++;
            if (tagEnd < length && [text characterAtIndex:tagEnd] == '$') {
                NSString *tag = [text substringWithRange:NSMakeRange(i, tagEnd + 1 - i)];
                NSRange end = [text rangeOfString:tag options:0 range:NSMakeRange(tagEnd + 1, length - tagEnd - 1)];
                i = end.location == NSNotFound ? length : NSMaxRange(end);
            } else {
                i = tagEnd;
            }
        } else if (c == ';') {
            [scan->semicolons addObject:[NSValue valueWithRange:NSMakeRange(i, 1)]];
            i++;
        } else if (c == '?' && !(dialect == UDSQLDialectPostgreSQL && (next == '|' || next == '&' || next == '-' || next == '#'))) {
            // ?, ?N (PostgreSQL's ?| ?& jsonb operators aren't parameters)
            NSUInteger end = i + 1;
            while (end < length && UDIsDigit([text characterAtIndex:end])) end++;
            NSString *name = end > i + 1 ? [text substringWithRange:NSMakeRange(i, end - i)]
                                         : [NSString stringWithFormat:@"?%lu", (unsigned long)++plain];
            [scan->parameters addObject:[NSValue valueWithRange:NSMakeRange(i, end - i)]];
            [scan->names addObject:name];
            i = end;
        } else if (c == '$' && UDIsDigit(next) && !(i > 0 && UDIsNamePart([text characterAtIndex:i - 1]))) {
            NSUInteger end = i + 1;
            while (end < length && UDIsDigit([text characterAtIndex:end])) end++;
            [scan->parameters addObject:[NSValue valueWithRange:NSMakeRange(i, end - i)]];
            [scan->names addObject:[text substringWithRange:NSMakeRange(i, end - i)]];
            i = end;
        } else if ((c == ':' || (c == '@' && dialect != UDSQLDialectMySQL)) && UDIsNameStart(next) &&
                   !(i > 0 && ([text characterAtIndex:i - 1] == ':' || UDIsNamePart([text characterAtIndex:i - 1])))) {
            // :name, @name; not PostgreSQL's ::type, nor a:b
            NSUInteger end = i + 1;
            while (end < length && UDIsNamePart([text characterAtIndex:end])) end++;
            [scan->parameters addObject:[NSValue valueWithRange:NSMakeRange(i, end - i)]];
            [scan->names addObject:[text substringWithRange:NSMakeRange(i, end - i)]];
            i = end;
        } else if (UDIsNamePart(c)) {
            // a word at once (its $ or : inside isn't a parameter's)
            while (i < length && (UDIsNamePart([text characterAtIndex:i]) || [text characterAtIndex:i] == '$')) i++;
        } else {
            i++;
        }
    }
}

static UDScan UDScanOf(NSString *text, UDSQLDialect dialect) {
    UDScan scan = { [NSMutableArray array], [NSMutableArray array], [NSMutableArray array] };
    UDScanText(text, dialect, &scan);
    return scan;
}

@implementation UDSQLText

static NSRange UDTrimmed(NSString *text, NSRange range) {
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    while (range.length && [space characterIsMember:[text characterAtIndex:range.location]]) {
        range.location++;
        range.length--;
    }
    while (range.length && [space characterIsMember:[text characterAtIndex:NSMaxRange(range) - 1]]) range.length--;
    return range;
}

+ (NSArray<NSValue *> *)statementRangesOfText:(NSString *)text dialect:(UDSQLDialect)dialect {
    UDScan scan = UDScanOf(text, dialect);
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSUInteger start = 0;
    NSMutableArray<NSValue *> *ends = [scan.semicolons mutableCopy];
    [ends addObject:[NSValue valueWithRange:NSMakeRange(text.length, 0)]];
    for (NSValue *end in ends) {
        NSRange statement = UDTrimmed(text, NSMakeRange(start, end.rangeValue.location - start));
        if (statement.length && [self _hasCode:[text substringWithRange:statement] dialect:dialect]) {
            [ranges addObject:[NSValue valueWithRange:statement]];
        }
        start = NSMaxRange(end.rangeValue);
    }
    return ranges;
}

/// Whether @a statement is more than comments.
+ (BOOL)_hasCode:(NSString *)statement dialect:(UDSQLDialect)dialect {
    NSUInteger length = statement.length, i = 0;
    while (i < length) {
        unichar c = [statement characterAtIndex:i];
        unichar next = i + 1 < length ? [statement characterAtIndex:i + 1] : 0;
        if ((c == '-' && next == '-') || (c == '#' && dialect == UDSQLDialectMySQL)) {
            NSRange line = [statement rangeOfString:@"\n" options:0 range:NSMakeRange(i, length - i)];
            i = line.location == NSNotFound ? length : NSMaxRange(line);
        } else if (c == '/' && next == '*') {
            NSRange end = [statement rangeOfString:@"*/" options:0 range:NSMakeRange(i + 2, length - i - 2)];
            i = end.location == NSNotFound ? length : NSMaxRange(end);
        } else if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) {
            i++;
        } else {
            return YES;
        }
    }
    return NO;
}

+ (NSRange)statementRangeAtIndex:(NSUInteger)index ofText:(NSString *)text dialect:(UDSQLDialect)dialect {
    NSRange before = NSMakeRange(NSNotFound, 0);
    for (NSValue *value in [self statementRangesOfText:text dialect:dialect]) {
        NSRange range = value.rangeValue;
        if (index >= range.location && index <= NSMaxRange(range)) return range;
        if (NSMaxRange(range) <= index) before = range;
    }
    // past a statement's semicolon, on its line: that one
    if (before.location != NSNotFound) {
        NSRange line = [text lineRangeForRange:NSMakeRange(MIN(index, text.length), 0)];
        if (NSMaxRange(before) >= line.location) return before;
    }
    return NSMakeRange(NSNotFound, 0);
}

+ (NSArray<NSString *> *)parametersOfStatement:(NSString *)statement dialect:(UDSQLDialect)dialect {
    UDScan scan = UDScanOf(statement, dialect);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *name in scan.names) {
        if (![names containsObject:name]) [names addObject:name];
    }
    return names;
}

+ (NSString *)statement:(NSString *)statement convertedForDialect:(UDSQLDialect)dialect order:(NSArray<NSString *> **)order {
    UDScan scan = UDScanOf(statement, dialect);
    NSMutableString *converted = [statement mutableCopy];
    NSMutableArray<NSString *> *bound = [NSMutableArray array];
    NSMutableArray<NSString *> *distinct = [NSMutableArray array];
    // back to front, so the ranges still hold
    for (NSInteger i = (NSInteger)scan.parameters.count - 1; i >= 0; i--) {
        NSString *name = scan.names[(NSUInteger)i];
        NSString *placeholder = @"?";
        if (dialect == UDSQLDialectPostgreSQL) {
            NSArray *firsts = [self parametersOfStatement:statement dialect:dialect];
            placeholder = [NSString stringWithFormat:@"$%lu", (unsigned long)[firsts indexOfObject:name] + 1];
        }
        [converted replaceCharactersInRange:scan.parameters[(NSUInteger)i].rangeValue withString:placeholder];
        [bound insertObject:name atIndex:0];
    }
    if (dialect == UDSQLDialectPostgreSQL) {
        for (NSString *name in scan.names) if (![distinct containsObject:name]) [distinct addObject:name];
        bound = distinct;
    }
    if (order) *order = bound;
    return converted;
}

+ (NSString *)statement:(NSString *)statement withParametersReplacedBy:(NSArray<NSString *> *)literals dialect:(UDSQLDialect)dialect {
    UDScan scan = UDScanOf(statement, dialect);
    NSMutableString *replaced = [statement mutableCopy];
    NSUInteger count = MIN(scan.parameters.count, literals.count);
    for (NSInteger i = (NSInteger)count - 1; i >= 0; i--) {
        [replaced replaceCharactersInRange:scan.parameters[(NSUInteger)i].rangeValue withString:literals[(NSUInteger)i]];
    }
    return replaced;
}

@end
