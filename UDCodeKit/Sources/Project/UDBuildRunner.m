/*---------------------------------------------------------------------------------------------
 *  UDBuildRunner.m
 *--------------------------------------------------------------------------------------------*/

#import "UDBuildRunner.h"
#import "UDProject.h"
#import "UDDiagnosticItem.h"
#include <signal.h>

UDDiagnosticSource const UDDiagnosticSourceBuild = @"build";

@implementation UDBuildRunner {
    NSTask *_task;
    NSFileHandle *_reading;
    NSMutableString *_output;
    NSMutableString *_pending;               // a line not yet ended
    NSMutableArray<NSString *> *_folders;    // where make is (Entering/Leaving directory)
    NSMutableDictionary<NSString *, UDDiagnosticStore *> *_diagnostics;
    NSMutableDictionary<NSString *, NSMutableArray<UDDiagnosticItem *> *> *_items;
    BOOL _stopped;
}

- (instancetype)initWithProject:(UDProject *)project {
    if (!(self = [super init])) return nil;
    _project = project;
    _output = [NSMutableString string];
    _diagnostics = [NSMutableDictionary dictionary];
    _items = [NSMutableDictionary dictionary];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// Until its output is all read and the delegate told (the process may have
/// ended before).
- (BOOL)isRunning {
    return _task != nil;
}

- (NSString *)output {
    return [_output copy];
}

- (NSDictionary<NSString *, UDDiagnosticStore *> *)diagnostics {
    return [_diagnostics copy];
}

- (BOOL)runCommand:(NSString *)command {
    if (self.running || !command.length) return NO;
    [_output setString:@""];
    _pending = [NSMutableString string];
    _folders = [NSMutableArray arrayWithObject:_project.folderURL.path];
    // the last build's diagnostics go (the stores stay: who shows them sees them empty)
    for (UDDiagnosticStore *store in _diagnostics.allValues) [store clearSource:UDDiagnosticSourceBuild];
    [_items removeAllObjects];
    _errorCount = 0;
    _warningCount = 0;
    _stopped = NO;
    _terminationStatus = 0;
    _command = [command copy];

    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    // exec: the shell is the command, so stopping it stops make
    task.launchPath = @"/bin/sh";
    task.arguments = @[ @"-c", [@"exec 2>&1; " stringByAppendingString:command] ];
    task.currentDirectoryPath = _project.folderURL.path;
    task.environment = [_project buildEnvironment];
    task.standardOutput = pipe;
    task.standardError = pipe;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    _reading = pipe.fileHandleForReading;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_didRead:) name:NSFileHandleReadCompletionNotification object:_reading];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        [center removeObserver:self name:NSFileHandleReadCompletionNotification object:_reading];
        _reading = nil;
        return NO;
    }
    _task = task;
    [_reading readInBackgroundAndNotify];
    return YES;
}

- (void)stop {
    if (!self.running) return;
    _stopped = YES;
    [_task terminate];
}

- (void)_didRead:(NSNotification *)note {
    NSData *data = note.userInfo[NSFileHandleNotificationDataItem];
    if (data.length) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                      ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        [_output appendString:text];
        [self _readLines:text];
        if ([_delegate respondsToSelector:@selector(buildRunner:didOutput:)]) [_delegate buildRunner:self didOutput:text];
        [_reading readInBackgroundAndNotify];
        return;
    }
    // the end of its output: the end of it
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object:_reading];
    _reading = nil;
    if (_pending.length) [self _readLine:_pending];
    [_task waitUntilExit];
    _terminationStatus = _task.terminationStatus;
    _succeeded = !_stopped && _terminationStatus == 0;
    _task = nil;
    if ([_delegate respondsToSelector:@selector(buildRunnerDidFinish:)]) [_delegate buildRunnerDidFinish:self];
}

- (void)_readLines:(NSString *)text {
    [_pending appendString:text];
    NSRange newline;
    while ((newline = [_pending rangeOfString:@"\n"]).location != NSNotFound) {
        NSString *line = [_pending substringToIndex:newline.location];
        [_pending deleteCharactersInRange:NSMakeRange(0, NSMaxRange(newline))];
        [self _readLine:line];
    }
}

- (void)_readLine:(NSString *)line {
    // make[1]: Entering directory '/path'  (or `/path')
    NSRange entering = [line rangeOfString:@": Entering directory "];
    NSRange leaving = [line rangeOfString:@": Leaving directory "];
    if (entering.location != NSNotFound) {
        NSString *folder = [[line substringFromIndex:NSMaxRange(entering)]
                            stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"'`\" \r"]];
        if (folder.length) [_folders addObject:folder];
        return;
    }
    if (leaving.location != NSNotFound) {
        if (_folders.count > 1) [_folders removeLastObject];
        return;
    }
    NSString *path = nil;
    UDDiagnosticItem *item = [UDBuildRunner diagnosticOfLine:line inFolder:_folders.lastObject path:&path];
    if (!item) return;
    if (item.severity == UDDiagnosticSeverityError) _errorCount++;
    else if (item.severity == UDDiagnosticSeverityWarning) _warningCount++;
    UDDiagnosticStore *store = _diagnostics[path];
    if (!store) {
        store = [[UDDiagnosticStore alloc] init];
        _diagnostics[path] = store;
    }
    NSMutableArray *items = _items[path] ?: [NSMutableArray array];
    _items[path] = items;
    [items addObject:item];
    [store setDiagnostics:items forSource:UDDiagnosticSourceBuild];
}

+ (UDDiagnosticItem *)diagnosticOfLine:(NSString *)line inFolder:(NSString *)folder path:(NSString **)path {
    // <file>:<line>[:<column>]: <severity>: <message>
    NSArray<NSString *> *severities = @[ @"fatal error", @"error", @"warning", @"note" ];
    for (NSString *severity in severities) {
        NSRange marker = [line rangeOfString:[NSString stringWithFormat:@": %@: ", severity]];
        if (marker.location == NSNotFound) continue;
        NSArray<NSString *> *where = [[line substringToIndex:marker.location] componentsSeparatedByString:@":"];
        if (where.count < 2) return nil;
        // the last one or two parts are numbers: the line, and the column
        NSInteger lineNumber = 0, column = 0, numbers = 0;
        for (NSInteger i = (NSInteger)where.count - 1; i >= 1 && numbers < 2; i--) {
            NSString *part = where[(NSUInteger)i];
            if (!part.length || [part rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet].invertedSet].location != NSNotFound) break;
            numbers++;
        }
        if (numbers == 0) return nil;
        if (numbers == 2) {
            lineNumber = where[where.count - 2].integerValue;
            column = where[where.count - 1].integerValue;
        } else {
            lineNumber = where[where.count - 1].integerValue;
        }
        NSString *file = [[where subarrayWithRange:NSMakeRange(0, where.count - (NSUInteger)numbers)] componentsJoinedByString:@":"];
        file = [file stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!file.length || [file hasPrefix:@"make"] || [file hasPrefix:@"ld"]) return nil;
        if (!file.isAbsolutePath) file = [folder stringByAppendingPathComponent:file];
        *path = file.stringByStandardizingPath;
        UDDiagnosticSeverity level = [severity isEqualToString:@"warning"] ? UDDiagnosticSeverityWarning
                                   : [severity isEqualToString:@"note"] ? UDDiagnosticSeverityInfo
                                   : UDDiagnosticSeverityError;
        NSString *message = [line substringFromIndex:NSMaxRange(marker)];
        return [[UDDiagnosticItem alloc] initWithLine:MAX(lineNumber, 1) column:MAX(column - 1, 0)
                                              message:message severity:level source:UDDiagnosticSourceBuild];
    }
    return nil;
}

@end
