/*---------------------------------------------------------------------------------------------
 *  UDSQLRunner.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLRunner.h"

@implementation UDSQLStatement

- (instancetype)initWithText:(NSString *)text SQL:(NSString *)sql parameters:(NSArray *)parameters {
    self = [super init];
    if (self) {
        _text = [text copy];
        _SQL = [sql copy];
        _parameters = [parameters copy];
    }
    return self;
}

@end

@interface UDSQLRun ()
@property (nonatomic, readwrite, copy) NSArray<UDSQLStatement *> *statements;
@property (nonatomic, readwrite, copy) NSArray<UDSQLResult *> *results;
@property (nonatomic, readwrite, nullable) NSError *error;
@property (nonatomic, readwrite) NSUInteger failedStatement;
@property (nonatomic, readwrite, getter=isFinished) BOOL finished;
@end

@implementation UDSQLRun
@end

/// What an operation tells, and to whom, on the main thread.
@interface UDSQLReply : NSObject
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
@property (nonatomic, strong, nullable) id value;
@end

@implementation UDSQLReply

- (void)send {
    id target = _target;
    if (!target || !_action) return;
    ((void (*)(id, SEL, id))[target methodForSelector:_action])(target, _action, _value);
}

@end

@interface UDSQLRunner ()
@property (atomic, readwrite, nullable) UDSQLConnection *connection;
@property (atomic, readwrite, getter=isRunning) BOOL running;
@end

@implementation UDSQLRunner {
    NSOperationQueue *_queue;
    NSString *_password;
    BOOL _stopped;          // the run asked to stop (read on the queue)
}

- (instancetype)initWithURL:(NSURL *)url password:(NSString *)password {
    self = [super init];
    if (self) {
        _URL = [url copy];
        _password = [password copy];
        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 1;
        _queue.name = [NSString stringWithFormat:@"UDCode database %@", url.lastPathComponent ?: url.host ?: @""];
    }
    return self;
}

- (void)dealloc {
    [_queue cancelAllOperations];
}

- (void)_enqueue:(SEL)selector argument:(id)argument {
    NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithTarget:self selector:selector object:argument];
    [_queue addOperation:operation];
}

static UDSQLReply *UDReply(id target, SEL action) {
    UDSQLReply *reply = [[UDSQLReply alloc] init];
    reply.target = target;
    reply.action = action;
    return reply;
}

- (void)_tell:(UDSQLReply *)reply value:(id)value {
    reply.value = value;
    [reply performSelectorOnMainThread:@selector(send) withObject:nil waitUntilDone:NO
                                 modes:@[ NSDefaultRunLoopMode, @"NSModalPanelRunLoopMode", @"NSEventTrackingRunLoopMode" ]];
}

/// On the queue: the connection, made when it isn't; nil and @a error when
/// it can't be.
- (UDSQLConnection *)_connection:(NSError **)error {
    UDSQLConnection *connection = self.connection;
    if (connection) return connection;
    connection = [UDSQLConnection connectionToURL:_URL password:_password error:error];
    self.connection = connection;
    return connection;
}

- (void)connectWithTarget:(id)target action:(SEL)action {
    [self _enqueue:@selector(_connect:) argument:UDReply(target, action)];
}

- (void)_connect:(UDSQLReply *)reply {
    NSError *error = nil;
    [self _connection:&error];
    [self _tell:reply value:error];
}

- (void)readSchemaWithTarget:(id)target action:(SEL)action {
    [self _enqueue:@selector(_readSchema:) argument:UDReply(target, action)];
}

- (void)_readSchema:(UDSQLReply *)reply {
    NSError *error = nil;
    UDSQLConnection *connection = [self _connection:&error];
    UDSQLSchema *schema = connection ? [UDSQLSchema schemaOfConnection:connection error:&error] : nil;
    [self _tell:reply value:schema ?: (id)error];
}

- (void)run:(NSArray<UDSQLStatement *> *)statements maxRows:(NSUInteger)maxRows target:(id)target action:(SEL)action {
    self.running = YES;
    @synchronized (self) {
        _stopped = NO;
    }
    [self _enqueue:@selector(_run:) argument:@[ statements, @(maxRows), UDReply(target, action) ]];
}

- (UDSQLRun *)_runStatements:(NSArray<UDSQLStatement *> *)statements maxRows:(NSUInteger)maxRows reply:(UDSQLReply *)reply {
    UDSQLRun *run = [[UDSQLRun alloc] init];
    run.statements = statements;
    run.results = @[];
    NSError *error = nil;
    UDSQLConnection *connection = [self _connection:&error];
    if (!connection) {
        run.error = error;
        run.finished = YES;
        return run;
    }
    NSMutableArray<UDSQLResult *> *results = [NSMutableArray array];
    for (NSUInteger i = 0; i < statements.count; i++) {
        BOOL stopped;
        @synchronized (self) {
            stopped = _stopped;
        }
        if (stopped) {
            run.error = UDSQLError(0, @"Stopped.", nil);
            run.failedStatement = i;
            break;
        }
        UDSQLResult *result = [connection execute:statements[i].SQL parameters:statements[i].parameters maxRows:maxRows error:&error];
        if (!result) {
            run.error = error;
            run.failedStatement = i;
            break;
        }
        result.statement = statements[i].text;
        [results addObject:result];
        run.results = results;
        if (reply && i + 1 < statements.count) {
            // told as it goes: a copy, the run going on meanwhile
            UDSQLRun *sofar = [[UDSQLRun alloc] init];
            sofar.statements = statements;
            sofar.results = results;
            [self _tell:UDReply(reply.target, reply.action) value:sofar];
        }
    }
    run.results = results;
    run.finished = YES;
    return run;
}

- (void)_run:(NSArray *)arguments {
    UDSQLReply *reply = arguments[2];
    UDSQLRun *run = [self _runStatements:arguments[0] maxRows:[arguments[1] unsignedIntegerValue] reply:reply];
    self.running = NO;
    [self _tell:reply value:run];
}

- (UDSQLRun *)runAndWait:(NSArray<UDSQLStatement *> *)statements maxRows:(NSUInteger)maxRows {
    [_queue waitUntilAllOperationsAreFinished];
    return [self _runStatements:statements maxRows:maxRows reply:nil];
}

- (void)stop {
    @synchronized (self) {
        _stopped = YES;
    }
    [self.connection cancel];
}

- (void)close {
    [_queue cancelAllOperations];
    [self stop];
    [self _enqueue:@selector(_close:) argument:nil];
}

- (void)_close:(id)unused {
    [self.connection close];
    self.connection = nil;
}

@end
