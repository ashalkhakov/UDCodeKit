/*---------------------------------------------------------------------------------------------
 *  UDSQLRunner.h
 *
 *  A database's work, off the main thread: one runner a connection, its
 *  operations (connecting, reading the schema, running statements) one at a
 *  time on a queue of its own, each told to its target on the main thread —
 *  a run after each of its statements, so results show as they come. A run
 *  stops at its first failing statement; -stop stops the one running.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDSQLConnection.h"
#import "UDSQLSchema.h"

NS_ASSUME_NONNULL_BEGIN

/// A statement to run: its text as written (shown), as the driver takes it
/// (its placeholders converted), and its parameters' values in their order.
@interface UDSQLStatement : NSObject
- (instancetype)initWithText:(NSString *)text SQL:(NSString *)sql parameters:(NSArray *)parameters;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly, copy) NSString *SQL;
@property (nonatomic, readonly, copy) NSArray *parameters;
@end

/// A run of statements, as far as it got: each one's result, the error that
/// stopped it (and which statement's).
@interface UDSQLRun : NSObject
@property (nonatomic, readonly, copy) NSArray<UDSQLStatement *> *statements;
@property (nonatomic, readonly, copy) NSArray<UDSQLResult *> *results;
@property (nonatomic, readonly, nullable) NSError *error;
@property (nonatomic, readonly) NSUInteger failedStatement;
@property (nonatomic, readonly, getter=isFinished) BOOL finished;
@end

@interface UDSQLRunner : NSObject

/// A runner for a connection to @a url (@a password apart from it), not yet
/// made: -connectWithTarget:action: makes it.
- (instancetype)initWithURL:(NSURL *)url password:(nullable NSString *)password;

@property (nonatomic, readonly, copy) NSURL *URL;
/// The connection once made; nil before, or when it failed.
@property (atomic, readonly, nullable) UDSQLConnection *connection;
@property (atomic, readonly, getter=isRunning) BOOL running;

/// Connects: @a action gets nil, or the NSError why not.
- (void)connectWithTarget:(id)target action:(SEL)action;
/// Reads the schema: @a action gets the UDSQLSchema, or an NSError.
- (void)readSchemaWithTarget:(id)target action:(SEL)action;
/// Runs @a statements, keeping @a maxRows rows of each result: @a action
/// gets the UDSQLRun after each statement, and once it is finished.
- (void)run:(NSArray<UDSQLStatement *> *)statements maxRows:(NSUInteger)maxRows target:(id)target action:(SEL)action;
/// Runs @a statements and waits for them (the tests'; the main thread's
/// work is done meanwhile, none of it told).
- (UDSQLRun *)runAndWait:(NSArray<UDSQLStatement *> *)statements maxRows:(NSUInteger)maxRows;

/// The statement running stopped, the run with it.
- (void)stop;
/// The connection closed, once what it runs is done.
- (void)close;

@end

NS_ASSUME_NONNULL_END
