/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleSyntax.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLExampleSyntax.h"
#import "UDSQLExampleCondition.h"

/// Each kind's pattern and colour, in the order they are laid on (text in
/// quotes last: what is in it is only text).
static NSArray<NSArray *> *UDPatterns(void) {
    static NSArray *patterns;
    if (!patterns) {
        NSRegularExpressionOptions options = NSRegularExpressionCaseInsensitive;
        NSRegularExpression *(^re)(NSString *) = ^NSRegularExpression *(NSString *pattern) {
            return [NSRegularExpression regularExpressionWithPattern:pattern options:options error:NULL];
        };
        patterns = @[
            @[ re(@"(<=|>=|<>|!=|=|<|>|\\.\\.|\\b(AND|OR|NOT|IS|NULL)\\b)"), [NSColor secondaryLabelColor], @NO ],
            @[ re(@"(?<![A-Za-z0-9_])[PG]\\."), [NSColor systemBlueColor], @YES ],
            @[ re(@"(?<![A-Za-z0-9_])(SUM|AVG|MIN|MAX|CNT)\\.((ALL|UNQ)\\.)?"), [NSColor systemPurpleColor], @YES ],
            @[ re(@"(?<![A-Za-z0-9])_[A-Za-z0-9_]+"), [NSColor systemOrangeColor], @NO ],
            @[ re(@"'(?:[^']|'')*'?"), [NSColor systemBrownColor], @NO ],
        ];
    }
    return patterns;
}

static void UDColour(NSMutableAttributedString *text, NSFont *font) {
    NSFont *bold = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSBoldFontMask];
    NSString *string = text.string;
    for (NSArray *pattern in UDPatterns()) {
        NSRegularExpression *expression = pattern[0];
        for (NSTextCheckingResult *match in [expression matchesInString:string options:0 range:NSMakeRange(0, string.length)]) {
            [text addAttribute:NSForegroundColorAttributeName value:pattern[1] range:match.range];
            [text addAttribute:NSFontAttributeName value:[pattern[2] boolValue] ? bold : font range:match.range];
        }
    }
}

NSAttributedString *UDSQLExampleHighlighted(NSString *text, NSFont *font, NSColor *color) {
    NSMutableAttributedString *coloured = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: font, NSForegroundColorAttributeName: color }];
    UDColour(coloured, font);
    return coloured;
}

void UDSQLExampleHighlight(NSTextStorage *storage) {
    NSRange all = NSMakeRange(0, storage.length);
    NSFont *font = storage.length ? [storage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] : nil;
    font = font ? [[NSFontManager sharedFontManager] convertFont:font toNotHaveTrait:NSBoldFontMask] : [NSFont userFixedPitchFontOfSize:0];
    [storage beginEditing];
    [storage addAttribute:NSForegroundColorAttributeName value:[NSColor textColor] range:all];
    [storage addAttribute:NSFontAttributeName value:font range:all];
    UDColour(storage, font);
    [storage endEditing];
}

// ---------------------------------------------------------------------------
// MARK: - Said in words
// ---------------------------------------------------------------------------

static NSString *UDAggregateMeaning(NSString *function) {
    NSDictionary *meanings = @{ @"SUM": @"the sum of its values", @"AVG": @"the average of its values",
                                @"MIN": @"its least value", @"MAX": @"its greatest value", @"COUNT": @"how many values it has" };
    return meanings[function];
}

static BOOL UDIsElementText(NSString *text) {
    NSRegularExpression *element = [NSRegularExpression regularExpressionWithPattern:@"^_[A-Za-z0-9_]+$" options:0 error:NULL];
    return [element firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

NSString *UDSQLExampleExplanation(NSString *typed) {
    NSString *text = [typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) return nil;
    NSMutableArray *lines = [NSMutableArray array];
    NSCharacterSet *spaces = [NSCharacterSet whitespaceCharacterSet];
    for (BOOL more = YES; more;) {
        more = NO;
        if ([text.uppercaseString hasPrefix:@"P."]) {
            [lines addObject:@"P. — printed: a column of the answer"];
            more = YES;
        } else if ([text.uppercaseString hasPrefix:@"G."]) {
            [lines addObject:@"G. — grouped by it: rows alike in it are one row of the answer"];
            more = YES;
        }
        if (more) text = [[text substringFromIndex:2] stringByTrimmingCharactersInSet:spaces];
    }
    BOOL distinct = NO;
    NSString *rest = nil;
    NSString *function = UDSQLAggregateOf(text, &rest, &distinct);
    if (function) {
        NSString *zloof = UDSQLZloofName(function);
        [lines addObject:[NSString stringWithFormat:@"%@.%@ — %@ in each group (%@)", zloof, distinct ? @"UNQ." : @"",
                                                    UDAggregateMeaning(function),
                                                    distinct ? @"UNQ.: each distinct value once" : @"ALL., the default: every value"]];
        text = rest;
        if (text.length && !UDIsElementText(text)) {
            [lines addObject:[NSString stringWithFormat:@"%@ — the groups whose %@ is so (HAVING)", text, [zloof stringByAppendingString:@"."]]];
            text = @"";
        }
    }
    if (UDIsElementText(text)) {
        [lines addObject:[NSString stringWithFormat:@"%@ — an example element: its value here; the same element in another row's "
                                                    "column links the two (a join), and the condition box may name it", text]];
    } else if (text.length) {
        BOOL compared = NO;
        for (NSString *op in @[ @"<=", @">=", @"<>", @"!=", @"=", @"<", @">" ]) {
            if (![text hasPrefix:op]) continue;
            NSString *operand = [[text substringFromIndex:op.length] stringByTrimmingCharactersInSet:spaces];
            if (UDIsElementText(operand)) {
                [lines addObject:[NSString stringWithFormat:@"%@ — its value compared with %@'s, where that is bound", text, operand]];
                compared = YES;
            }
            break;
        }
        if (!compared) [lines addObject:[NSString stringWithFormat:@"%@ — the rows whose value is so", text]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

NSString *UDSQLExampleConditionHelp(void) {
    return @"The condition box: what no column can say, of example elements (_x), a condition a line, all of them held:\n"
            "  _s > _b * 2 — compared, with + - * /\n"
            "  _c = 'Oslo' OR _c = 'Rome' — AND, OR, NOT, ( )\n"
            "  _d IS NOT NULL\n"
            "  CNT.ALL._e > 5 — of an aggregate (SUM. AVG. MIN. MAX. CNT., ALL. or UNQ.): the groups kept (HAVING)\n"
            "Its elements are those the rows give a value (put alone under a column).";
}
