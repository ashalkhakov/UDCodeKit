/*---------------------------------------------------------------------------------------------
 *  UDSQLValues.h
 *
 *  A value of a result's, as a grid shows it: NULL told apart from text, a
 *  blob by its size, a line break as ↵, and a Core Data store's dates
 *  (TIMESTAMP, seconds since 2001) and entities (Z_ENT) as such. The
 *  results under a query and a table's browser show values alike.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import "UDSQLSchema.h"

NS_ASSUME_NONNULL_BEGIN

/// @a value (NSString, NSNumber, NSData, NSNull) of the column named
/// @a name, of @a type (nil: unknown), as text; @a schema says whether it
/// is a Core Data store's.
FOUNDATION_EXPORT NSString *UDSQLTextOfValue(id value, NSString *_Nullable name, NSString *_Nullable type,
                                             UDSQLSchema *_Nullable schema);

/// What a grid's cell shows for it: its text, NULL and a blob's size
/// dimmed (not the value itself).
FOUNDATION_EXPORT id UDSQLCellOfValue(id value, NSString *_Nullable name, NSString *_Nullable type,
                                      UDSQLSchema *_Nullable schema);

/// The format dates are shown in (and a Core Data date is typed in).
FOUNDATION_EXPORT NSDateFormatter *UDSQLDateFormatter(void);

@class UDSQLResult;

/// @a result as CSV (RFC 4180: its names a first line; a field quoted
/// where it holds a comma, quote or line break; NULL empty; CRLF lines),
/// its values as text (a Core Data date as a date).
FOUNDATION_EXPORT NSString *UDSQLCSVOfResult(UDSQLResult *result, UDSQLSchema *_Nullable schema);
/// @a result as JSON: an array of objects, a column's name to its value
/// (numbers as numbers, NULL as null, the rest as text), in their order.
FOUNDATION_EXPORT NSString *UDSQLJSONOfResult(UDSQLResult *result, UDSQLSchema *_Nullable schema);

NS_ASSUME_NONNULL_END
