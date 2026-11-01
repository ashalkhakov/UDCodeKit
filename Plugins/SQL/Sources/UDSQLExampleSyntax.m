/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleSyntax.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLExampleSyntax.h"
#import "UDSQLExampleCondition.h"

/// A named system colour where the SDK has it, else a fixed one
/// (XFormsKit's XFDSystemColor).
static NSColor *UDSystemColor(NSString *selectorName, CGFloat r, CGFloat g, CGFloat b) {
    SEL selector = NSSelectorFromString(selectorName);
    if ([NSColor respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSColor *color = [NSColor performSelector:selector];
#pragma clang diagnostic pop
        if (color) return color;
    }
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1];
}

NSColor *UDSQLExampleTokenColor(NSString *kind) {
    if ([kind isEqualToString:@"string"]) return UDSystemColor(@"systemRedColor", 0.77, 0.10, 0.09);
    if ([kind isEqualToString:@"number"]) return UDSystemColor(@"systemBlueColor", 0.11, 0.00, 0.81);
    if ([kind isEqualToString:@"function"]) return UDSystemColor(@"systemPurpleColor", 0.42, 0.13, 0.66);
    if ([kind isEqualToString:@"command"]) return UDSystemColor(@"systemBrownColor", 0.42, 0.30, 0.16);
    if ([kind isEqualToString:@"variable"]) return UDSystemColor(@"systemTealColor", 0.00, 0.46, 0.54);
    if ([kind isEqualToString:@"operator"]) return UDSystemColor(@"systemOrangeColor", 0.64, 0.35, 0.00);
    if ([kind isEqualToString:@"punct"]) return [NSColor disabledControlTextColor];
    return [NSColor controlTextColor];   // name
}

NSAttributedString *UDSQLExampleAttributedString(NSString *expression, NSFont *font) {
    NSString *text = expression ?: @"";
    NSMutableDictionary *base = [NSMutableDictionary dictionary];
    if (font) base[NSFontAttributeName] = font;
    base[NSForegroundColorAttributeName] = [NSColor controlTextColor];
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] initWithString:text attributes:base];
    for (NSDictionary *token in [UDSQLExampleCondition highlightTokensForString:text]) {
        NSRange range = [token[@"range"] rangeValue];
        if (range.length && NSMaxRange(range) <= text.length) {
            [out addAttribute:NSForegroundColorAttributeName value:UDSQLExampleTokenColor(token[@"kind"]) range:range];
        }
    }
    return out;
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
