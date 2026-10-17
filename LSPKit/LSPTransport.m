//
//  LSPTransport.m
//  LSPKit
//

#import "LSPTransport.h"

#include <signal.h>

/// The modes the streams are read in: a menu being tracked or a modal panel
/// does not hold the messages back.
static NSArray<NSString *> *LSPTransportModes(void) {
    return [NSArray arrayWithObjects:NSDefaultRunLoopMode, @"NSModalPanelRunLoopMode",
            @"NSEventTrackingRunLoopMode", nil];
}

@interface LSPTransport () {
    NSMutableData *_buffer;
    NSFileHandle *_readHandle;
    NSFileHandle *_writeHandle;
    NSFileHandle *_errorHandle;
    BOOL _open;
    BOOL _closed;       // the delegate has heard, or was told nothing more
}
@end

@implementation LSPTransport

- (instancetype)initWithLaunchPath:(NSString *)path
                         arguments:(NSArray<NSString *> *)arguments
              currentDirectoryPath:(NSString *)directory {
    self = [super init];
    if (!self) return nil;
    // A process that has ended must not end the app with it: writing to its
    // pipe then fails (and -sendMessage: says so) instead of raising SIGPIPE.
    signal(SIGPIPE, SIG_IGN);
    NSPipe *input = [NSPipe pipe], *output = [NSPipe pipe], *error = [NSPipe pipe];
    _task = [[NSTask alloc] init];
    [_task setStandardInput:input];
    [_task setStandardOutput:output];
    [_task setStandardError:error];
    if (directory) [_task setCurrentDirectoryPath:directory];
    [_task setLaunchPath:path];
    [_task setArguments:arguments];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_taskDidTerminate:)
                                                 name:NSTaskDidTerminateNotification object:_task];
    @try {
        [_task launch];
    } @catch (NSException *e) {
        NSString *reason = [NSString stringWithFormat:@"Could not start %@: %@", path, [e reason]];
        _launchError = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT
                                       userInfo:[NSDictionary dictionaryWithObject:reason forKey:NSLocalizedDescriptionKey]];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        _task = nil;
        [self performSelector:@selector(_didClose) withObject:nil afterDelay:0 inModes:LSPTransportModes()];
        return self;
    }
    [self _openReading:[output fileHandleForReading] writing:[input fileHandleForWriting]];
    _errorHandle = [error fileHandleForReading];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_errorRead:)
                                                 name:NSFileHandleReadCompletionNotification object:_errorHandle];
    [_errorHandle readInBackgroundAndNotifyForModes:LSPTransportModes()];
    return self;
}

- (instancetype)initWithReadHandle:(NSFileHandle *)readHandle writeHandle:(NSFileHandle *)writeHandle {
    self = [super init];
    if (!self) return nil;
    signal(SIGPIPE, SIG_IGN);
    [self _openReading:readHandle writing:writeHandle];
    return self;
}

- (void)_openReading:(NSFileHandle *)readHandle writing:(NSFileHandle *)writeHandle {
    _buffer = [NSMutableData data];
    _readHandle = readHandle;
    _writeHandle = writeHandle;
    _open = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_read:)
                                                 name:NSFileHandleReadCompletionNotification object:_readHandle];
    [_readHandle readInBackgroundAndNotifyForModes:LSPTransportModes()];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isOpen {
    return _open;
}

#pragma mark Reading

- (void)_read:(NSNotification *)note {
    // The delegate may let go of whoever holds this, at any message.
    __attribute__((objc_precise_lifetime)) LSPTransport *keep = self;
    NSData *data = [[note userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if ([data length] == 0) {
        // The end. A process's is its termination, which says how it ended.
        if (_task == nil) [self _didClose];
        return;
    }
    [self _didReceiveData:data];
    if (_open) [[note object] readInBackgroundAndNotifyForModes:LSPTransportModes()];
}

- (void)_errorRead:(NSNotification *)note {
    NSData *data = [[note userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if ([data length] == 0) return;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    id<LSPTransportDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(transport:didReceiveErrorOutput:)]) {
        [delegate transport:self didReceiveErrorOutput:text ?: @""];
    } else {
        NSLog(@"stderr: %@", text);
    }
    if (_open) [[note object] readInBackgroundAndNotifyForModes:LSPTransportModes()];
}

/// The header fields of a message ("Name: value" lines), by name.
static NSDictionary *LSPParseHeaders(NSData *header) {
    NSString *text = [[NSString alloc] initWithData:header encoding:NSASCIIStringEncoding];
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSString *line in [text componentsSeparatedByString:@"\r\n"]) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *name = [[line substringToIndex:colon.location]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value = [[line substringFromIndex:NSMaxRange(colon)]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [fields setObject:value forKey:[name lowercaseString]];
    }
    return fields;
}

/// Messages as they arrive: a header ending in a blank line, then
/// Content-Length bytes of JSON. Data may hold part of one, or several.
- (void)_didReceiveData:(NSData *)data {
    [_buffer appendData:data];
    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    while (_open) {
        NSRange end = [_buffer rangeOfData:separator options:0 range:NSMakeRange(0, [_buffer length])];
        if (end.location == NSNotFound) return;
        NSDictionary *headers = LSPParseHeaders([_buffer subdataWithRange:NSMakeRange(0, end.location)]);
        NSUInteger length = (NSUInteger)[[headers objectForKey:@"content-length"] integerValue];
        NSUInteger bodyStart = NSMaxRange(end);
        if ([_buffer length] < bodyStart + length) return;   // the rest is still coming
        NSData *body = [_buffer subdataWithRange:NSMakeRange(bodyStart, length)];
        [_buffer replaceBytesInRange:NSMakeRange(0, bodyStart + length) withBytes:NULL length:0];

        NSError *error = nil;
        NSDictionary *message = [NSJSONSerialization JSONObjectWithData:body options:0 error:&error];
        if (![message isKindOfClass:[NSDictionary class]]) {
            NSLog(@"LSPKit: not a JSON object: %@", error);
            continue;
        }
        [_delegate transport:self didReceiveMessage:message];
    }
}

#pragma mark Writing

+ (NSData *)frameForMessage:(NSDictionary *)message {
    NSData *json = [NSJSONSerialization dataWithJSONObject:message options:0 error:NULL];
    if (json == nil) return nil;
    NSString *header = [NSString stringWithFormat:@"Content-Length: %lu\r\n\r\n", (unsigned long)[json length]];
    NSMutableData *frame = [NSMutableData dataWithData:[header dataUsingEncoding:NSASCIIStringEncoding]];
    [frame appendData:json];
    return frame;
}

- (void)sendMessage:(NSDictionary *)message {
    if (!_open) return;
    NSData *frame = [[self class] frameForMessage:message];
    if (frame == nil) {
        NSLog(@"LSPKit: not JSON: %@", message);
        return;
    }
    @try {
        [_writeHandle writeData:frame];
    } @catch (NSException *e) {
        NSLog(@"LSPKit: the other end is not reading: %@", [e reason]);
    }
}

#pragma mark Closing

- (void)_taskDidTerminate:(NSNotification *)note {
    __attribute__((objc_precise_lifetime)) LSPTransport *keep = self;
    [self _didClose];
}

- (void)_didClose {
    if (_closed) return;
    _closed = YES;
    [self _closeStreams];
    id<LSPTransportDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(transportDidClose:)]) {
        [delegate transportDidClose:self];
    }
}

- (void)_closeStreams {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    _open = NO;
    @try {
        [_writeHandle closeFile];
        [_readHandle closeFile];
        [_errorHandle closeFile];
    } @catch (NSException *e) {
    }
}

- (void)terminate {
    if ([_task isRunning]) {
        [_task terminate];
    } else if (_task == nil) {
        [self _didClose];
    }
}

- (void)close {
    _closed = YES;
    [self _closeStreams];
    if ([_task isRunning]) [_task terminate];
}

@end
