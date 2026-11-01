/*---------------------------------------------------------------------------------------------
 *  UDSQLValues.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLValues.h"

NSDateFormatter *UDSQLDateFormatter(void) {
    static NSDateFormatter *dates;
    if (!dates) {
        dates = [[NSDateFormatter alloc] init];
        dates.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    }
    return dates;
}

NSString *UDSQLTextOfValue(id value, NSString *name, NSString *type, UDSQLSchema *schema) {
    if (value == [NSNull null]) return @"NULL";
    if ([value isKindOfClass:[NSData class]]) return [NSString stringWithFormat:@"⟨%lu bytes⟩", (unsigned long)[value length]];
    if (schema.coreDataStore && [value isKindOfClass:[NSNumber class]]) {
        // a Core Data store's dates and entities, as such
        if (type && [type caseInsensitiveCompare:@"TIMESTAMP"] == NSOrderedSame) {
            return [UDSQLDateFormatter() stringFromDate:UDSQLDateOfCoreDataTimestamp([value doubleValue])];
        }
        if ([name isEqualToString:@"Z_ENT"] && schema.coreDataEntities[value]) {
            return [NSString stringWithFormat:@"%@ · %@", value, schema.coreDataEntities[value]];
        }
    }
    NSString *text = [value description];
    return [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@" ↵ "] stringByReplacingOccurrencesOfString:@"\n" withString:@" ↵ "];
}

id UDSQLCellOfValue(id value, NSString *name, NSString *type, UDSQLSchema *schema) {
    NSString *text = UDSQLTextOfValue(value, name, type, schema);
    if (value != [NSNull null] && ![value isKindOfClass:[NSData class]]) return text;
    // not the value itself: told apart
    return [[NSAttributedString alloc] initWithString:text attributes:@{
        NSForegroundColorAttributeName: [NSColor disabledControlTextColor],
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]] }];
}

// ---------------------------------------------------------------------------
// MARK: - A result exported
// ---------------------------------------------------------------------------

static NSString *UDCSVField(NSString *text) {
    if ([text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@",\"\r\n"]].location == NSNotFound) return text;
    return [NSString stringWithFormat:@"\"%@\"", [text stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

/// Whether @a value is a Core Data store's date (seconds since 2001):
/// exported as a date, not a number.
static BOOL UDIsCoreDataDate(id value, UDSQLColumn *column, UDSQLSchema *schema) {
    return schema.coreDataStore && [value isKindOfClass:[NSNumber class]] && column.type &&
           [column.type caseInsensitiveCompare:@"TIMESTAMP"] == NSOrderedSame;
}

/// A value as the export writes it: as it is (no ↵, Z_ENT its number), a
/// Core Data date as a date, a blob by its size; NULL none (nil).
static NSString *UDExportedText(id value, UDSQLColumn *column, UDSQLSchema *schema) {
    if (value == [NSNull null]) return nil;
    if (UDIsCoreDataDate(value, column, schema) || [value isKindOfClass:[NSData class]]) {
        return UDSQLTextOfValue(value, column.name, column.type, schema);
    }
    return [value description];
}

NSString *UDSQLCSVOfResult(UDSQLResult *result, UDSQLSchema *schema) {
    NSMutableString *csv = [NSMutableString string];
    NSMutableArray *names = [NSMutableArray array];
    for (UDSQLColumn *column in result.columns) [names addObject:UDCSVField(column.name)];
    [csv appendFormat:@"%@\r\n", [names componentsJoinedByString:@","]];
    for (NSArray *row in result.rows) {
        NSMutableArray *fields = [NSMutableArray array];
        for (NSUInteger i = 0; i < row.count; i++) {
            UDSQLColumn *column = i < result.columns.count ? result.columns[i] : nil;
            [fields addObject:UDCSVField(UDExportedText(row[i], column, schema) ?: @"")];
        }
        [csv appendFormat:@"%@\r\n", [fields componentsJoinedByString:@","]];
    }
    return csv;
}

static NSString *UDJSONString(NSString *text) {
    NSMutableString *out = [NSMutableString stringWithString:@"\""];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '"' || c == '\\') [out appendFormat:@"\\%C", c];
        else if (c == '\n') [out appendString:@"\\n"];
        else if (c == '\r') [out appendString:@"\\r"];
        else if (c == '\t') [out appendString:@"\\t"];
        else if (c < 0x20) [out appendFormat:@"\\u%04x", c];
        else [out appendFormat:@"%C", c];
    }
    [out appendString:@"\""];
    return out;
}

NSString *UDSQLJSONOfResult(UDSQLResult *result, UDSQLSchema *schema) {
    // written here, not by NSJSONSerialization: its columns in their order
    NSMutableString *json = [NSMutableString stringWithString:@"["];
    for (NSUInteger r = 0; r < result.rows.count; r++) {
        NSArray *row = result.rows[r];
        [json appendString:r ? @",\n  {" : @"\n  {"];
        for (NSUInteger i = 0; i < row.count && i < result.columns.count; i++) {
            UDSQLColumn *column = result.columns[i];
            id value = row[i];
            NSString *written;
            if (value == [NSNull null]) written = @"null";
            else if ([value isKindOfClass:[NSNumber class]] && !UDIsCoreDataDate(value, column, schema)) {
                written = isfinite([value doubleValue]) ? [value stringValue] : @"null";
            } else {
                written = UDJSONString(UDExportedText(value, column, schema));
            }
            [json appendFormat:@"%@%@: %@", i ? @", " : @"", UDJSONString(column.name), written];
        }
        [json appendString:@"}"];
    }
    [json appendString:result.rows.count ? @"\n]\n" : @"]\n"];
    return json;
}
