/*---------------------------------------------------------------------------------------------
 *  UDSQLSheets.h
 *
 *  What the SQL extension asks (UDSQLSheets.xib's, a fresh set each time):
 *  a connection (its kind, name, file or server, where it is kept, tested),
 *  a statement's parameters' values (numbers as numbers, '…' for text that
 *  looks like one, or NULL), a server's password.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import "UDSQLConnection.h"

NS_ASSUME_NONNULL_BEGIN

@class UDSQLDatabase;

/// The password given for @a url this session (kept till UDCode quits, never
/// written), and remembered.
FOUNDATION_EXPORT NSString *_Nullable UDSQLPasswordOfURL(NSURL *url);
FOUNDATION_EXPORT void UDSQLRememberPassword(NSURL *url, NSString *_Nullable password);

@interface UDSQLSheets : NSObject <NSTableViewDataSource, NSTableViewDelegate>

/// A server's password, asked in an alert after @a message; nil: cancelled.
+ (nullable NSString *)askPasswordOfDatabase:(NSString *)name message:(NSString *)message window:(nullable NSWindow *)window;

/// @a names' values asked for in a sheet on @a window, @a previous offered;
/// @a action gets @[ the values (a dictionary by name), or NSNull when
/// cancelled, @a context ].
+ (void)askValuesOfParameters:(NSArray<NSString *> *)names previous:(NSDictionary *)previous window:(nullable NSWindow *)window
                      context:(id)context target:(id)target action:(SEL)action;

/// A connection made or changed in a sheet on @a window (@a database's, or a
/// new one of @a dialect); @a action gets the UDSQLDatabase, or NSNull when
/// cancelled. @a inProject: whether "This Project" can be chosen.
+ (void)editDatabase:(nullable UDSQLDatabase *)database dialect:(UDSQLDialect)dialect inProject:(BOOL)inProject
              window:(nullable NSWindow *)window target:(id)target action:(SEL)action;

/// A typed value as bound: a number as a number, '…' as the text inside,
/// else the text.
+ (id)valueOfText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
