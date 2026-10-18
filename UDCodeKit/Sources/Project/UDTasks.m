/*---------------------------------------------------------------------------------------------
 *  UDTasks.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTasks.h"
#import "UDProject.h"

#ifdef __APPLE__
static NSString * const UDVSCodePlatformKey = @"osx";
#else
static NSString * const UDVSCodePlatformKey = @"linux";
#endif

@interface UDTask ()
@property (nonatomic, readwrite, copy) NSString *label;
@property (nonatomic, readwrite, copy) NSString *commandLine;
@property (nonatomic, readwrite, copy) NSString *directory;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, readwrite, copy, nullable) NSString *group;
@property (nonatomic, readwrite) BOOL defaultOfGroup;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *dependsOn;
@end

@implementation UDTask
@end

@interface UDLaunchConfiguration ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *request;
@property (nonatomic, readwrite, copy) NSString *type;
@property (nonatomic, readwrite, copy, nullable) NSString *debugger;
@property (nonatomic, readwrite, copy, nullable) NSString *debuggerPath;
@property (nonatomic, readwrite, copy, nullable) NSString *program;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *arguments;
@property (nonatomic, readwrite, copy, nullable) NSString *directory;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, readwrite, copy, nullable) NSString *preLaunchTask;
@property (nonatomic, readwrite) NSInteger processID;
@end

@implementation UDLaunchConfiguration
@end

@implementation UDTasks {
    NSURL *_folderURL;
    NSURL *_fileURL;
}

- (instancetype)initWithFolderURL:(NSURL *)folderURL currentFileURL:(NSURL *)fileURL {
    if (!(self = [super init])) return nil;
    _folderURL = [folderURL copy];
    _fileURL = [fileURL copy];
    NSURL *vscode = [folderURL URLByAppendingPathComponent:@".vscode"];
    id tasks = [UDTasks objectOfJSONC:[NSData dataWithContentsOfURL:[vscode URLByAppendingPathComponent:@"tasks.json"]] ?: [NSData data]];
    id launch = [UDTasks objectOfJSONC:[NSData dataWithContentsOfURL:[vscode URLByAppendingPathComponent:@"launch.json"]] ?: [NSData data]];
    _tasks = [self _readTasks:[tasks isKindOfClass:[NSDictionary class]] ? tasks : @{}];
    _configurations = [self _readConfigurations:[launch isKindOfClass:[NSDictionary class]] ? launch : @{}];
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - JSONC
// ---------------------------------------------------------------------------

+ (id)objectOfJSONC:(NSData *)data {
    if (!data.length) return nil;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return nil;
    // comments out (not in strings), then commas before a closing bracket
    NSMutableString *json = [NSMutableString stringWithCapacity:text.length];
    NSUInteger length = text.length;
    BOOL inString = NO;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [text characterAtIndex:i];
        unichar next = i + 1 < length ? [text characterAtIndex:i + 1] : 0;
        if (inString) {
            [json appendFormat:@"%C", c];
            if (c == '\\' && next) {
                [json appendFormat:@"%C", next];
                i++;
            } else if (c == '"') {
                inString = NO;
            }
        } else if (c == '"') {
            inString = YES;
            [json appendString:@"\""];
        } else if (c == '/' && next == '/') {
            while (i < length && [text characterAtIndex:i] != '\n') i++;
            [json appendString:@"\n"];
        } else if (c == '/' && next == '*') {
            i += 2;
            while (i + 1 < length && !([text characterAtIndex:i] == '*' && [text characterAtIndex:i + 1] == '/')) i++;
            i++;
        } else {
            [json appendFormat:@"%C", c];
        }
    }
    // a comma, then only white space, then } or ]: the comma goes
    NSMutableString *clean = [NSMutableString stringWithCapacity:json.length];
    inString = NO;
    for (NSUInteger i = 0; i < json.length; i++) {
        unichar c = [json characterAtIndex:i];
        if (inString) {
            [clean appendFormat:@"%C", c];
            if (c == '\\' && i + 1 < json.length) [clean appendFormat:@"%C", [json characterAtIndex:++i]];
            else if (c == '"') inString = NO;
            continue;
        }
        if (c == '"') inString = YES;
        if (c == ',') {
            NSUInteger j = i + 1;
            while (j < json.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[json characterAtIndex:j]]) j++;
            if (j < json.length && ([json characterAtIndex:j] == '}' || [json characterAtIndex:j] == ']')) continue;
        }
        [clean appendFormat:@"%C", c];
    }
    return [NSJSONSerialization JSONObjectWithData:[clean dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
}

// ---------------------------------------------------------------------------
// MARK: - Variables
// ---------------------------------------------------------------------------

- (NSString *)substitute:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || [text rangeOfString:@"${"].location == NSNotFound) return text;
    NSString *folder = _folderURL.path;
    NSString *file = _fileURL.path;
    NSMutableDictionary<NSString *, NSString *> *values = [@{
        @"workspaceFolder": folder, @"workspaceRoot": folder,
        @"workspaceFolderBasename": folder.lastPathComponent,
        @"cwd": folder, @"userHome": NSHomeDirectory(), @"pathSeparator": @"/",
    } mutableCopy];
    if (file) {
        values[@"file"] = file;
        values[@"fileBasename"] = file.lastPathComponent;
        values[@"fileBasenameNoExtension"] = file.lastPathComponent.stringByDeletingPathExtension;
        values[@"fileDirname"] = file.stringByDeletingLastPathComponent;
        values[@"fileExtname"] = file.pathExtension.length ? [@"." stringByAppendingString:file.pathExtension] : @"";
        NSString *prefix = [folder stringByAppendingString:@"/"];
        values[@"relativeFile"] = [file hasPrefix:prefix] ? [file substringFromIndex:prefix.length] : file;
    }
    NSMutableString *result = [NSMutableString string];
    NSUInteger at = 0;
    while (at < text.length) {
        NSRange open = [text rangeOfString:@"${" options:0 range:NSMakeRange(at, text.length - at)];
        if (open.location == NSNotFound) break;
        NSRange close = [text rangeOfString:@"}" options:0 range:NSMakeRange(NSMaxRange(open), text.length - NSMaxRange(open))];
        if (close.location == NSNotFound) break;
        [result appendString:[text substringWithRange:NSMakeRange(at, open.location - at)]];
        NSString *name = [text substringWithRange:NSMakeRange(NSMaxRange(open), close.location - NSMaxRange(open))];
        NSString *value = values[name];
        if ([name hasPrefix:@"env:"]) value = [[NSProcessInfo processInfo] environment][[name substringFromIndex:4]] ?: @"";
        [result appendString:value ?: [text substringWithRange:NSMakeRange(open.location, NSMaxRange(close) - open.location)]];
        at = NSMaxRange(close);
    }
    [result appendString:[text substringFromIndex:at]];
    return result;
}

- (NSDictionary<NSString *, NSString *> *)_substituteEnvironment:(id)environment {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if ([environment isKindOfClass:[NSDictionary class]]) {
        for (NSString *name in environment) {
            id value = environment[name];
            if ([value isKindOfClass:[NSString class]]) result[name] = [self substitute:value];
            else if ([value isKindOfClass:[NSNumber class]]) result[name] = [value stringValue];
        }
    } else if ([environment isKindOfClass:[NSArray class]]) {
        // the C/C++ extension's: [{ "name": …, "value": … }]
        for (NSDictionary *pair in environment) {
            if (![pair isKindOfClass:[NSDictionary class]] || ![pair[@"name"] isKindOfClass:[NSString class]]) continue;
            id value = pair[@"value"];
            result[pair[@"name"]] = [value isKindOfClass:[NSString class]] ? [self substitute:value] : [value description] ?: @"";
        }
    }
    return result;
}

/// @a item with its "osx"/"linux" properties over the rest (options key by key).
static NSDictionary *UDOnThisSystem(NSDictionary *item) {
    NSDictionary *platform = [item[UDVSCodePlatformKey] isKindOfClass:[NSDictionary class]] ? item[UDVSCodePlatformKey] : nil;
    if (!platform) return item;
    NSMutableDictionary *merged = [item mutableCopy];
    for (NSString *key in platform) {
        if ([key isEqualToString:@"options"] && [merged[key] isKindOfClass:[NSDictionary class]] &&
            [platform[key] isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *options = [merged[key] mutableCopy];
            [options addEntriesFromDictionary:platform[key]];
            merged[key] = options;
        } else {
            merged[key] = platform[key];
        }
    }
    return merged;
}

/// A word as sh reads it: quoted when it has to be.
static NSString *UDShellQuoted(NSString *word) {
    if (!word.length) return @"''";
    NSCharacterSet *plain = [NSCharacterSet characterSetWithCharactersInString:
                             @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:,+@%"];
    if ([word rangeOfCharacterFromSet:plain.invertedSet].location == NSNotFound) return word;
    return [NSString stringWithFormat:@"'%@'", [word stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

// ---------------------------------------------------------------------------
// MARK: - Tasks
// ---------------------------------------------------------------------------

- (NSArray<UDTask *> *)_readTasks:(NSDictionary *)file {
    NSMutableArray<UDTask *> *tasks = [NSMutableArray array];
    NSDictionary *topOptions = [file[@"options"] isKindOfClass:[NSDictionary class]] ? file[@"options"] : @{};
    for (NSDictionary *raw in [file[@"tasks"] isKindOfClass:[NSArray class]] ? file[@"tasks"] : @[]) {
        if (![raw isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *item = UDOnThisSystem(raw);
        UDTask *task = [[UDTask alloc] init];
        NSString *command = [item[@"command"] isKindOfClass:[NSString class]] ? [self substitute:item[@"command"]] : nil;
        task.label = [item[@"label"] isKindOfClass:[NSString class]] ? item[@"label"] : command ?: @"task";
        NSString *type = [item[@"type"] isKindOfClass:[NSString class]] ? item[@"type"] : @"shell";
        NSMutableArray<NSString *> *words = [NSMutableArray array];
        for (id argument in [item[@"args"] isKindOfClass:[NSArray class]] ? item[@"args"] : @[]) {
            id value = [argument isKindOfClass:[NSDictionary class]] ? argument[@"value"] : argument;
            if ([value isKindOfClass:[NSString class]]) [words addObject:UDShellQuoted([self substitute:value])];
        }
        if (command.length) {
            // a shell task's command is shell text; a process's, a program
            NSString *first = [type isEqualToString:@"shell"] ? command : UDShellQuoted(command);
            task.commandLine = [[@[ first ] arrayByAddingObjectsFromArray:words] componentsJoinedByString:@" "];
        } else {
            task.commandLine = @"";
        }
        NSMutableDictionary *options = [topOptions mutableCopy];
        if ([item[@"options"] isKindOfClass:[NSDictionary class]]) [options addEntriesFromDictionary:item[@"options"]];
        NSString *cwd = [options[@"cwd"] isKindOfClass:[NSString class]] ? [self substitute:options[@"cwd"]] : nil;
        task.directory = cwd.length ? (cwd.isAbsolutePath ? cwd : [_folderURL.path stringByAppendingPathComponent:cwd]) : _folderURL.path;
        task.environment = [self _substituteEnvironment:options[@"env"]];
        id group = item[@"group"];
        if ([group isKindOfClass:[NSString class]]) {
            task.group = group;
        } else if ([group isKindOfClass:[NSDictionary class]]) {
            task.group = [group[@"kind"] isKindOfClass:[NSString class]] ? group[@"kind"] : nil;
            task.defaultOfGroup = [group[@"isDefault"] isEqual:@YES];
        }
        id depends = item[@"dependsOn"];
        task.dependsOn = [depends isKindOfClass:[NSString class]] ? @[ depends ]
                       : [depends isKindOfClass:[NSArray class]] ? [depends filteredArrayUsingPredicate:
                                                                    [NSPredicate predicateWithFormat:@"self isKindOfClass: %@", [NSString class]]]
                       : @[];
        [tasks addObject:task];
    }
    return tasks;
}

- (UDTask *)taskLabelled:(NSString *)label {
    for (UDTask *task in _tasks) if ([task.label isEqualToString:label]) return task;
    return nil;
}

- (UDTask *)buildTask {
    UDTask *first = nil;
    for (UDTask *task in _tasks) {
        if (![task.group isEqualToString:@"build"]) continue;
        if (task.defaultOfGroup) return task;
        if (!first) first = task;
    }
    return first;
}

- (NSString *)commandLineRunning:(UDTask *)task {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [self _add:task to:lines seen:[NSMutableSet set]];
    return [lines componentsJoinedByString:@" && "];
}

/// What @a task depends on, then itself: each in its folder, with its environment.
- (void)_add:(UDTask *)task to:(NSMutableArray<NSString *> *)lines seen:(NSMutableSet<NSString *> *)seen {
    if ([seen containsObject:task.label]) return;
    [seen addObject:task.label];
    for (NSString *label in task.dependsOn) {
        UDTask *before = [self taskLabelled:label];
        if (before) [self _add:before to:lines seen:seen];
    }
    if (!task.commandLine.length) return;
    NSMutableString *line = [NSMutableString stringWithFormat:@"(cd %@ && ", UDShellQuoted(task.directory)];
    for (NSString *name in task.environment) {
        [line appendFormat:@"%@=%@ ", name, UDShellQuoted(task.environment[name])];
    }
    [line appendFormat:@"%@)", task.commandLine];
    [lines addObject:line];
}

// ---------------------------------------------------------------------------
// MARK: - Launch configurations
// ---------------------------------------------------------------------------

- (NSArray<UDLaunchConfiguration *> *)_readConfigurations:(NSDictionary *)file {
    NSMutableArray<UDLaunchConfiguration *> *configurations = [NSMutableArray array];
    for (NSDictionary *raw in [file[@"configurations"] isKindOfClass:[NSArray class]] ? file[@"configurations"] : @[]) {
        if (![raw isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *item = UDOnThisSystem(raw);
        UDLaunchConfiguration *configuration = [[UDLaunchConfiguration alloc] init];
        configuration.name = [item[@"name"] isKindOfClass:[NSString class]] ? item[@"name"] : @"Launch";
        configuration.request = [item[@"request"] isKindOfClass:[NSString class]] ? item[@"request"] : @"launch";
        configuration.type = [item[@"type"] isKindOfClass:[NSString class]] ? item[@"type"] : @"";
        NSString *type = configuration.type;
        NSString *mode = [item[@"MIMode"] isKindOfClass:[NSString class]] ? item[@"MIMode"] : nil;
        if ([type isEqualToString:@"lldb"] || [type isEqualToString:@"lldb-dap"] || [type isEqualToString:@"lldb-vscode"]
            || ([type isEqualToString:@"cppdbg"] && [mode isEqualToString:@"lldb"])) {
            configuration.debugger = @"lldb";
        } else if ([type isEqualToString:@"gdb"] || ([type isEqualToString:@"cppdbg"] && (!mode || [mode isEqualToString:@"gdb"]))) {
            configuration.debugger = @"gdb";
        }
        NSString *debuggerPath = [item[@"miDebuggerPath"] isKindOfClass:[NSString class]] ? [self substitute:item[@"miDebuggerPath"]] : nil;
        configuration.debuggerPath = debuggerPath.length ? debuggerPath : nil;
        NSString *program = [item[@"program"] isKindOfClass:[NSString class]] ? [self substitute:item[@"program"]] : nil;
        if (program.length && !program.isAbsolutePath) program = [_folderURL.path stringByAppendingPathComponent:program];
        configuration.program = program.length ? program : nil;
        NSMutableArray *arguments = [NSMutableArray array];
        id args = item[@"args"];
        if ([args isKindOfClass:[NSString class]]) args = [UDProject argumentsOfCommandLine:[self substitute:args]];
        for (id argument in [args isKindOfClass:[NSArray class]] ? args : @[]) {
            if ([argument isKindOfClass:[NSString class]]) [arguments addObject:[self substitute:argument]];
        }
        configuration.arguments = arguments;
        NSString *cwd = [item[@"cwd"] isKindOfClass:[NSString class]] ? [self substitute:item[@"cwd"]] : nil;
        if (cwd.length && !cwd.isAbsolutePath) cwd = [_folderURL.path stringByAppendingPathComponent:cwd];
        configuration.directory = cwd.length ? cwd : nil;
        configuration.environment = [self _substituteEnvironment:item[@"env"] ?: item[@"environment"]];
        configuration.preLaunchTask = [item[@"preLaunchTask"] isKindOfClass:[NSString class]] ? item[@"preLaunchTask"] : nil;
        id pid = item[@"processId"] ?: item[@"pid"];
        configuration.processID = [pid respondsToSelector:@selector(integerValue)] ? [pid integerValue] : 0;
        [configurations addObject:configuration];
    }
    return configurations;
}

@end
