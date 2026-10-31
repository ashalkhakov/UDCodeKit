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
