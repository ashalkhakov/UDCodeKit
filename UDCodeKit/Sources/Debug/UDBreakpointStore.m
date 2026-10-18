/*---------------------------------------------------------------------------------------------
 *  UDBreakpointStore.m
 *--------------------------------------------------------------------------------------------*/

#import "UDBreakpointStore.h"

NSNotificationName const UDBreakpointStoreDidChangeNotification = @"UDBreakpointStoreDidChangeNotification";
NSNotificationName const UDBreakpointStoreDidMoveInstructionPointerNotification =
    @"UDBreakpointStoreDidMoveInstructionPointerNotification";
NSString * const UDBreakpointStoreFileKey = @"UDBreakpointStoreFileKey";
NSNotificationName const UDBreakpointStoreDidChangeWatchExpressionsNotification =
    @"UDBreakpointStoreDidChangeWatchExpressionsNotification";
NSNotificationName const UDBreakpointStoreDidChangeExceptionFiltersNotification =
    @"UDBreakpointStoreDidChangeExceptionFiltersNotification";

NSString * const UDBreakpointDecorationOwner = @"debug.breakpoint";
NSString * const UDInstructionPointerDecorationOwner = @"debug.instructionPointer";

// ---------------------------------------------------------------------------
// MARK: - UDBreakpoint
// ---------------------------------------------------------------------------

@interface UDBreakpoint ()
@property (nonatomic, copy) NSString *path;
@property (nonatomic) NSInteger line;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, getter=isVerified) BOOL verified;
@property (nonatomic, copy, nullable) NSString *message;
@property (nonatomic, copy, nullable) NSString *condition;
@property (nonatomic, copy, nullable) NSString *hitCondition;
@property (nonatomic, copy, nullable) NSString *logMessage;
/// Its decoration in the file's attached text model.
@property (nonatomic, copy, nullable) NSString *decorationID;
@end

@implementation UDBreakpoint

- (BOOL)isConditional {
    return _condition.length > 0 || _hitCondition.length > 0;
}

- (BOOL)isLogpoint {
    return _logMessage.length > 0;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@:%ld%@>", NSStringFromClass([self class]),
            [_path lastPathComponent], (long)_line, _enabled ? @"" : @" disabled"];
}

@end

// ---------------------------------------------------------------------------
// MARK: - UDBreakpointStore
// ---------------------------------------------------------------------------

@implementation UDBreakpointStore {
    NSMutableDictionary<NSString *, NSMutableArray<UDBreakpoint *> *> *_breakpoints;
    NSMapTable<NSString *, UDTextModel *> *_models;          // weak
    NSString *_instructionPointerFile;
    NSInteger _instructionPointerLine;
    NSString *_instructionPointerDecorationID;
    __weak UDTextModel *_instructionPointerModel;
    NSMutableArray<NSString *> *_watchExpressions;
    NSMutableDictionary<NSString *, NSNumber *> *_exceptionFilterStates;   // filter → on, as chosen
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _breakpoints = [NSMutableDictionary dictionary];
    _models = [NSMapTable strongToWeakObjectsMapTable];
    _watchExpressions = [NSMutableArray array];
    _exceptionFilters = @[];
    _exceptionFilterStates = [NSMutableDictionary dictionary];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

static NSString *UDStandardPath(NSString *path) {
    return [path stringByStandardizingPath];
}

- (NSArray<NSString *> *)files {
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *path in _breakpoints) {
        if ([_breakpoints[path] count]) [files addObject:path];
    }
    return [files sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<UDBreakpoint *> *)allBreakpoints {
    NSMutableArray *all = [NSMutableArray array];
    for (NSString *path in self.files) [all addObjectsFromArray:_breakpoints[path]];
    return all;
}

- (NSArray<UDBreakpoint *> *)breakpointsInFile:(NSString *)path {
    return [_breakpoints[UDStandardPath(path)] copy] ?: @[];
}

- (UDBreakpoint *)breakpointAtLine:(NSInteger)line inFile:(NSString *)path {
    for (UDBreakpoint *breakpoint in _breakpoints[UDStandardPath(path)]) {
        if (breakpoint.line == line) return breakpoint;
    }
    return nil;
}

- (void)_postChangeInFile:(NSString *)path {
    [self _scheduleAutosave];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDBreakpointStoreDidChangeNotification object:self
                                                      userInfo:@{ UDBreakpointStoreFileKey: path }];
}

static void UDSortByLine(NSMutableArray<UDBreakpoint *> *breakpoints) {
    [breakpoints sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"line" ascending:YES] ]];
}

// ---------------------------------------------------------------------------
// MARK: - Editing
// ---------------------------------------------------------------------------

- (UDBreakpoint *)addBreakpointAtLine:(NSInteger)line inFile:(NSString *)path {
    path = UDStandardPath(path);
    UDBreakpoint *existing = [self breakpointAtLine:line inFile:path];
    if (existing) return existing;
    UDBreakpoint *breakpoint = [[UDBreakpoint alloc] init];
    breakpoint.path = path;
    breakpoint.line = MAX(line, 1);
    breakpoint.enabled = YES;
    breakpoint.verified = YES;
    NSMutableArray *list = _breakpoints[path];
    if (!list) _breakpoints[path] = list = [NSMutableArray array];
    [list addObject:breakpoint];
    UDSortByLine(list);
    UDTextModel *model = [_models objectForKey:path];
    if (model) [self _decorate:@[ breakpoint ] inModel:model];
    [self _postChangeInFile:path];
    return breakpoint;
}

- (void)removeBreakpoint:(UDBreakpoint *)breakpoint {
    NSMutableArray *list = _breakpoints[breakpoint.path];
    if (![list containsObject:breakpoint]) return;
    UDTextModel *model = [_models objectForKey:breakpoint.path];
    if (model && breakpoint.decorationID) {
        [model deltaDecorations:@[ breakpoint.decorationID ] newDecorations:@[] owner:UDBreakpointDecorationOwner];
    }
    breakpoint.decorationID = nil;
    [list removeObject:breakpoint];
    [self _postChangeInFile:breakpoint.path];
}

- (void)setBreakpoint:(UDBreakpoint *)breakpoint enabled:(BOOL)enabled {
    if (breakpoint.enabled == enabled) return;
    breakpoint.enabled = enabled;
    // A disabled breakpoint is not the adapter's to bind.
    breakpoint.verified = YES;
    breakpoint.message = nil;
    [self _postChangeInFile:breakpoint.path];
}

static NSString *UDNonEmpty(NSString *text) {
    return text.length ? [text copy] : nil;
}

static BOOL UDSame(NSString *a, NSString *b) {
    return a == b || [a isEqualToString:b];
}

- (void)setBreakpoint:(UDBreakpoint *)breakpoint condition:(NSString *)condition
         hitCondition:(NSString *)hitCondition logMessage:(NSString *)logMessage {
    condition = UDNonEmpty(condition);
    hitCondition = UDNonEmpty(hitCondition);
    logMessage = UDNonEmpty(logMessage);
    if (UDSame(breakpoint.condition, condition) && UDSame(breakpoint.hitCondition, hitCondition) &&
        UDSame(breakpoint.logMessage, logMessage)) return;
    breakpoint.condition = condition;
    breakpoint.hitCondition = hitCondition;
    breakpoint.logMessage = logMessage;
    [self _postChangeInFile:breakpoint.path];
}

- (void)setAllBreakpointsEnabled:(BOOL)enabled {
    for (NSString *path in self.files) {
        BOOL changed = NO;
        for (UDBreakpoint *breakpoint in _breakpoints[path]) {
            if (breakpoint.enabled == enabled) continue;
            breakpoint.enabled = enabled;
            breakpoint.verified = YES;
            breakpoint.message = nil;
            changed = YES;
        }
        if (changed) [self _postChangeInFile:path];
    }
}

- (void)removeAllBreakpoints {
    for (NSString *path in self.files) {
        UDTextModel *model = [_models objectForKey:path];
        NSMutableArray *ids = [NSMutableArray array];
        for (UDBreakpoint *breakpoint in _breakpoints[path]) {
            if (breakpoint.decorationID) [ids addObject:breakpoint.decorationID];
            breakpoint.decorationID = nil;
        }
        if (model && ids.count) [model deltaDecorations:ids newDecorations:@[] owner:UDBreakpointDecorationOwner];
        [_breakpoints[path] removeAllObjects];
        [self _postChangeInFile:path];
    }
}

- (void)clickBreakpointAtLine:(NSInteger)line inFile:(NSString *)path {
    UDBreakpoint *breakpoint = [self breakpointAtLine:line inFile:path];
    if (breakpoint) {
        [self setBreakpoint:breakpoint enabled:!breakpoint.enabled];
    } else {
        [self addBreakpointAtLine:line inFile:path];
    }
}

- (void)toggleBreakpointAtLine:(NSInteger)line inFile:(NSString *)path {
    UDBreakpoint *breakpoint = [self breakpointAtLine:line inFile:path];
    if (breakpoint) {
        [self removeBreakpoint:breakpoint];
    } else {
        [self addBreakpointAtLine:line inFile:path];
    }
}

- (void)setBreakpoint:(UDBreakpoint *)breakpoint verified:(BOOL)verified message:(NSString *)message {
    if (breakpoint.verified == verified && (message == breakpoint.message || [message isEqual:breakpoint.message])) return;
    breakpoint.verified = verified;
    breakpoint.message = message;
    [self _postChangeInFile:breakpoint.path];
}

- (void)resetVerification {
    for (NSString *path in [_breakpoints allKeys]) {
        BOOL changed = NO;
        for (UDBreakpoint *breakpoint in _breakpoints[path]) {
            if (breakpoint.verified && !breakpoint.message) continue;
            breakpoint.verified = YES;
            breakpoint.message = nil;
            changed = YES;
        }
        if (changed) [self _postChangeInFile:path];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Open files: breakpoints as decorations that follow the edits
// ---------------------------------------------------------------------------

/// The whole of @a line, clamped to the model's: a decoration that moves
/// with the line's text (an insertion at its start pushes it down, one at
/// its end leaves it).
static UDRange UDLineRange(UDTextModel *model, NSInteger line) {
    line = MAX(1, MIN(line, [model getLineCount]));
    return PTRangeMake(line, 1, line, [model getLineMaxColumn:line]);
}

- (NSString *)_decorateLine:(NSInteger)line inModel:(UDTextModel *)model owner:(NSString *)owner {
    UDDecorationOptions *options = [[UDDecorationOptions alloc] initWithClassName:owner userInfo:nil];
    UDModelDeltaDecoration *decoration = [[UDModelDeltaDecoration alloc] initWithRange:UDLineRange(model, line)
                                                                               options:options];
    decoration.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
    return [model deltaDecorations:nil newDecorations:@[ decoration ] owner:owner].firstObject;
}

- (void)_decorate:(NSArray<UDBreakpoint *> *)breakpoints inModel:(UDTextModel *)model {
    for (UDBreakpoint *breakpoint in breakpoints) {
        breakpoint.decorationID = [self _decorateLine:breakpoint.line inModel:model owner:UDBreakpointDecorationOwner];
    }
}

- (void)attachTextModel:(UDTextModel *)textModel toFile:(NSString *)path {
    path = UDStandardPath(path);
    UDTextModel *old = [_models objectForKey:path];
    if (old == textModel) return;
    if (old) {
        [self _readLinesOfFile:path];
        NSMutableArray *ids = [NSMutableArray array];
        for (UDBreakpoint *breakpoint in _breakpoints[path]) {
            if (breakpoint.decorationID) [ids addObject:breakpoint.decorationID];
        }
        [old deltaDecorations:ids newDecorations:@[] owner:UDBreakpointDecorationOwner];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UDTextModelDidChangeNotification object:old];
    }
    [_models setObject:textModel forKey:path];
    [self _decorate:_breakpoints[path] ?: @[] inModel:textModel];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textModelDidChange:)
                                                 name:UDTextModelDidChangeNotification object:textModel];
    if ([_instructionPointerFile isEqualToString:path]) {
        [self _placeInstructionPointer];
        [self _postInstructionPointerMoveFrom:nil];
    }
}

- (UDTextModel *)textModelForFile:(NSString *)path {
    return [_models objectForKey:UDStandardPath(path)];
}

- (void)_textModelDidChange:(NSNotification *)note {
    for (NSString *path in [[_models keyEnumerator] allObjects]) {
        if ([_models objectForKey:path] != note.object) continue;
        if ([self _readLinesOfFile:path]) [self _postChangeInFile:path];
    }
}

/// The breakpoints' lines as their decorations have them now; two that
/// came to one line are one. Whether any moved.
- (BOOL)_readLinesOfFile:(NSString *)path {
    UDTextModel *model = [_models objectForKey:path];
    NSMutableArray<UDBreakpoint *> *list = _breakpoints[path];
    if (!model || !list.count) return NO;
    BOOL moved = NO;
    for (UDBreakpoint *breakpoint in list) {
        if (!breakpoint.decorationID) continue;
        UDRange range = [model rangeForDecoration:breakpoint.decorationID];
        if (range.startLineNumber < 1 || range.startLineNumber == breakpoint.line) continue;
        breakpoint.line = range.startLineNumber;
        moved = YES;
    }
    if (!moved) return NO;
    UDSortByLine(list);
    for (NSInteger i = (NSInteger)list.count - 1; i > 0; i--) {
        UDBreakpoint *breakpoint = list[(NSUInteger)i];
        if (breakpoint.line != list[(NSUInteger)i - 1].line) continue;
        if (breakpoint.decorationID) {
            [model deltaDecorations:@[ breakpoint.decorationID ] newDecorations:@[] owner:UDBreakpointDecorationOwner];
        }
        [list removeObjectAtIndex:(NSUInteger)i];
    }
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Watch expressions
// ---------------------------------------------------------------------------

- (NSArray<NSString *> *)watchExpressions {
    return [_watchExpressions copy];
}

- (void)_postWatchExpressionsChange {
    [self _scheduleAutosave];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDBreakpointStoreDidChangeWatchExpressionsNotification
                                                        object:self];
}

static NSString *UDTrimmed(NSString *text) {
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (void)addWatchExpression:(NSString *)expression {
    expression = UDTrimmed(expression);
    if (!expression.length) return;
    [_watchExpressions addObject:expression];
    [self _postWatchExpressionsChange];
}

- (void)replaceWatchExpressionAtIndex:(NSUInteger)index withExpression:(NSString *)expression {
    if (index >= _watchExpressions.count) return;
    expression = UDTrimmed(expression);
    if (!expression.length) {
        [self removeWatchExpressionAtIndex:index];
        return;
    }
    if ([_watchExpressions[index] isEqualToString:expression]) return;
    _watchExpressions[index] = expression;
    [self _postWatchExpressionsChange];
}

- (void)removeWatchExpressionAtIndex:(NSUInteger)index {
    if (index >= _watchExpressions.count) return;
    [_watchExpressions removeObjectAtIndex:index];
    [self _postWatchExpressionsChange];
}

- (void)removeAllWatchExpressions {
    if (!_watchExpressions.count) return;
    [_watchExpressions removeAllObjects];
    [self _postWatchExpressionsChange];
}

// ---------------------------------------------------------------------------
// MARK: - Exception filters
// ---------------------------------------------------------------------------

- (void)_postExceptionFiltersChange {
    [self _scheduleAutosave];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDBreakpointStoreDidChangeExceptionFiltersNotification
                                                        object:self];
}

- (void)setExceptionFilters:(NSArray<NSDictionary *> *)exceptionFilters {
    exceptionFilters = exceptionFilters ?: @[];
    if ([_exceptionFilters isEqualToArray:exceptionFilters]) return;
    _exceptionFilters = [exceptionFilters copy];
    [self _postExceptionFiltersChange];
}

- (BOOL)isExceptionFilterEnabled:(NSString *)filterID {
    NSNumber *chosen = _exceptionFilterStates[filterID];
    if (chosen) return chosen.boolValue;
    for (NSDictionary *filter in _exceptionFilters) {
        if ([filter[@"filter"] isEqual:filterID]) return [filter[@"default"] boolValue];
    }
    return NO;
}

- (void)setExceptionFilter:(NSString *)filterID enabled:(BOOL)enabled {
    if (!filterID || ([self isExceptionFilterEnabled:filterID] == enabled && _exceptionFilterStates[filterID])) return;
    _exceptionFilterStates[filterID] = @(enabled);
    [self _postExceptionFiltersChange];
}

// ---------------------------------------------------------------------------
// MARK: - Keeping it
// ---------------------------------------------------------------------------

- (NSDictionary *)propertyList {
    NSMutableArray *breakpoints = [NSMutableArray array];
    for (UDBreakpoint *breakpoint in self.allBreakpoints) {
        NSMutableDictionary *item = [@{ @"path": breakpoint.path, @"line": @(breakpoint.line),
                                        @"enabled": @(breakpoint.enabled) } mutableCopy];
        if (breakpoint.condition) item[@"condition"] = breakpoint.condition;
        if (breakpoint.hitCondition) item[@"hitCondition"] = breakpoint.hitCondition;
        if (breakpoint.logMessage) item[@"logMessage"] = breakpoint.logMessage;
        [breakpoints addObject:item];
    }
    return @{ @"breakpoints": breakpoints,
              @"watchExpressions": [_watchExpressions copy],
              @"exceptionFilters": _exceptionFilters,
              @"exceptionFilterStates": [_exceptionFilterStates copy] };
}

static id UDKindOf(id value, Class kind) {
    return [value isKindOfClass:kind] ? value : nil;
}

- (void)restorePropertyList:(NSDictionary *)propertyList {
    if (![propertyList isKindOfClass:[NSDictionary class]]) return;
    [self removeAllBreakpoints];
    for (NSDictionary *item in UDKindOf(propertyList[@"breakpoints"], [NSArray class])) {
        NSString *path = UDKindOf(item, [NSDictionary class]) ? UDKindOf(item[@"path"], [NSString class]) : nil;
        NSInteger line = [UDKindOf(item[@"line"], [NSNumber class]) integerValue];
        if (!path.length || line < 1) continue;
        UDBreakpoint *breakpoint = [self addBreakpointAtLine:line inFile:path];
        NSNumber *enabled = UDKindOf(item[@"enabled"], [NSNumber class]);
        if (enabled && !enabled.boolValue) [self setBreakpoint:breakpoint enabled:NO];
        [self setBreakpoint:breakpoint condition:UDKindOf(item[@"condition"], [NSString class])
               hitCondition:UDKindOf(item[@"hitCondition"], [NSString class])
                 logMessage:UDKindOf(item[@"logMessage"], [NSString class])];
    }
    [_watchExpressions removeAllObjects];
    for (NSString *expression in UDKindOf(propertyList[@"watchExpressions"], [NSArray class])) {
        if (UDKindOf(expression, [NSString class]) && UDTrimmed(expression).length) [_watchExpressions addObject:expression];
    }
    [self _postWatchExpressionsChange];
    NSMutableArray *filters = [NSMutableArray array];
    for (NSDictionary *filter in UDKindOf(propertyList[@"exceptionFilters"], [NSArray class])) {
        if (UDKindOf(filter, [NSDictionary class]) && UDKindOf(filter[@"filter"], [NSString class])) [filters addObject:filter];
    }
    _exceptionFilters = filters;
    [_exceptionFilterStates removeAllObjects];
    NSDictionary *states = UDKindOf(propertyList[@"exceptionFilterStates"], [NSDictionary class]);
    for (NSString *filterID in states) {
        if (UDKindOf(states[filterID], [NSNumber class])) _exceptionFilterStates[filterID] = states[filterID];
    }
    [self _postExceptionFiltersChange];
}

- (void)setAutosaveName:(NSString *)autosaveName {
    _autosaveName = [autosaveName copy];
    NSDictionary *saved = autosaveName ? [[NSUserDefaults standardUserDefaults] dictionaryForKey:autosaveName] : nil;
    if (saved) [self restorePropertyList:saved];
}

/// Saved once whatever changes now has changed (an edit can move many).
- (void)_scheduleAutosave {
    if (!_autosaveName) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_autosave) object:nil];
    // AppKit's modal and tracking modes too, by name: the store is Foundation's.
    [self performSelector:@selector(_autosave) withObject:nil afterDelay:0
                  inModes:@[ NSDefaultRunLoopMode, @"NSModalPanelRunLoopMode", @"NSEventTrackingRunLoopMode" ]];
}

- (void)_autosave {
    if (_autosaveName) [[NSUserDefaults standardUserDefaults] setObject:[self propertyList] forKey:_autosaveName];
}

// ---------------------------------------------------------------------------
// MARK: - The instruction pointer
// ---------------------------------------------------------------------------

- (NSString *)instructionPointerFile {
    return _instructionPointerFile;
}

- (NSInteger)instructionPointerLine {
    UDTextModel *model = _instructionPointerModel;
    if (model && _instructionPointerDecorationID) {
        UDRange range = [model rangeForDecoration:_instructionPointerDecorationID];
        if (range.startLineNumber >= 1) return range.startLineNumber;
    }
    return _instructionPointerLine;
}

- (void)setInstructionPointerFile:(NSString *)path line:(NSInteger)line {
    path = path ? UDStandardPath(path) : nil;
    if ((path == _instructionPointerFile || [path isEqualToString:_instructionPointerFile]) &&
        line == self.instructionPointerLine) return;
    NSString *old = _instructionPointerFile;
    [self _removeInstructionPointer];
    _instructionPointerFile = [path copy];
    _instructionPointerLine = path ? line : 0;
    [self _placeInstructionPointer];
    [self _postInstructionPointerMoveFrom:old];
}

- (void)_removeInstructionPointer {
    UDTextModel *model = _instructionPointerModel;
    if (model && _instructionPointerDecorationID) {
        [model deltaDecorations:@[ _instructionPointerDecorationID ] newDecorations:@[]
                          owner:UDInstructionPointerDecorationOwner];
    }
    _instructionPointerDecorationID = nil;
    _instructionPointerModel = nil;
}

- (void)_placeInstructionPointer {
    [self _removeInstructionPointer];
    UDTextModel *model = _instructionPointerFile ? [_models objectForKey:_instructionPointerFile] : nil;
    if (!model) return;
    _instructionPointerModel = model;
    _instructionPointerDecorationID = [self _decorateLine:_instructionPointerLine inModel:model
                                                    owner:UDInstructionPointerDecorationOwner];
}

- (void)_postInstructionPointerMoveFrom:(NSString *)old {
    NSMutableArray *files = [NSMutableArray array];
    if (old) [files addObject:old];
    if (_instructionPointerFile && ![files containsObject:_instructionPointerFile]) [files addObject:_instructionPointerFile];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDBreakpointStoreDidMoveInstructionPointerNotification
                                                        object:self userInfo:@{ UDBreakpointStoreFileKey: files }];
}

@end
