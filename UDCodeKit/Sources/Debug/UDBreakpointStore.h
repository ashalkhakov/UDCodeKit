/*---------------------------------------------------------------------------------------------
 *  UDBreakpointStore.h
 *
 *  The breakpoints of a workspace's files, and where the debugger stands in
 *  them: one store per window (or per workspace), shared by its editors,
 *  which show and set the breakpoints in their gutters, by the breakpoint
 *  navigator, which lists them, and by the debug session, which sends them
 *  to the adapter and puts the instruction pointer there. A breakpoint may
 *  have a condition, a hit count and a log message (a logpoint), as VS
 *  Code's.
 *
 *  And what else a workspace keeps of the debugger: the watch expressions
 *  (the debug area's), and the exception filters the last adapter offered
 *  with which of them are on (the breakpoint navigator's). All of it is a
 *  property list (-propertyList, -restorePropertyList:) for the host to
 *  keep with its workspace, or kept in the user defaults under an
 *  autosaveName.
 *
 *  Files are named by path. While a file is open its breakpoints follow its
 *  edits: an editor attaches its text model (UDCodeEditorViewController's
 *  -showBreakpointsOfStore:forFile: does), each breakpoint is a decoration
 *  in it, and a line that moves takes its breakpoint along. A file not open
 *  keeps its breakpoints at the lines they last had.
 *
 *  Changes are posted (UDBreakpointStoreDidChangeNotification, with the
 *  file); the session sends that file's breakpoints again.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDPieceTable.h>

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

@class UDDebugSession;

NS_ASSUME_NONNULL_BEGIN

/// The breakpoints of a file changed: added, removed, enabled or disabled,
/// moved by an edit, or verified by the adapter. The object is the store;
/// UDBreakpointStoreFileKey names the file.
UDCODEKIT_EXPORT NSNotificationName const UDBreakpointStoreDidChangeNotification;
/// The instruction pointer moved, or went: the object is the store;
/// UDBreakpointStoreFileKey names the file it was in and the one it is in
/// now (an array of one or two paths).
UDCODEKIT_EXPORT NSNotificationName const UDBreakpointStoreDidMoveInstructionPointerNotification;
UDCODEKIT_EXPORT NSString * const UDBreakpointStoreFileKey;
/// The watch expressions changed. The object is the store.
UDCODEKIT_EXPORT NSNotificationName const UDBreakpointStoreDidChangeWatchExpressionsNotification;
/// The exception filters changed, or which of them are on. The object is the store.
UDCODEKIT_EXPORT NSNotificationName const UDBreakpointStoreDidChangeExceptionFiltersNotification;

/// The decorations' owners in an attached text model.
UDCODEKIT_EXPORT NSString * const UDBreakpointDecorationOwner;
UDCODEKIT_EXPORT NSString * const UDInstructionPointerDecorationOwner;

/// A breakpoint: a line of a file, enabled or not, and when it stops.
@interface UDBreakpoint : NSObject
/// The file, a standardized path.
@property (nonatomic, copy, readonly) NSString *path;
/// 1-based; follows the file's edits while it is open.
@property (nonatomic, readonly) NSInteger line;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
/// Whether the running session's adapter bound it; YES when no session ran
/// it (nothing says otherwise).
@property (nonatomic, readonly, getter=isVerified) BOOL verified;
/// The adapter's word on it (why it is not bound, say).
@property (nonatomic, copy, readonly, nullable) NSString *message;
/// An expression (the adapter's language): it stops only when it holds.
@property (nonatomic, copy, readonly, nullable) NSString *condition;
/// How many hits before it stops, in the adapter's terms ("5", ">= 5", ...).
@property (nonatomic, copy, readonly, nullable) NSString *hitCondition;
/// A logpoint's message: printed (with the adapter's "{expression}"s in it
/// evaluated) instead of stopping.
@property (nonatomic, copy, readonly, nullable) NSString *logMessage;
/// It has a condition or a hit count.
@property (nonatomic, readonly, getter=isConditional) BOOL conditional;
/// It has a log message.
@property (nonatomic, readonly, getter=isLogpoint) BOOL logpoint;
@end

@interface UDBreakpointStore : NSObject

/// Every file with breakpoints, sorted.
@property (nonatomic, readonly) NSArray<NSString *> *files;
/// Every breakpoint, by file, then by line.
@property (nonatomic, readonly) NSArray<UDBreakpoint *> *allBreakpoints;

/// A file's breakpoints, by line.
- (NSArray<UDBreakpoint *> *)breakpointsInFile:(NSString *)path;
- (nullable UDBreakpoint *)breakpointAtLine:(NSInteger)line inFile:(NSString *)path;

/// A new breakpoint, enabled; the one there when there is one.
- (UDBreakpoint *)addBreakpointAtLine:(NSInteger)line inFile:(NSString *)path;
- (void)removeBreakpoint:(UDBreakpoint *)breakpoint;
- (void)setBreakpoint:(UDBreakpoint *)breakpoint enabled:(BOOL)enabled;
/// When it stops: its condition, hit count and log message (empty: none).
- (void)setBreakpoint:(UDBreakpoint *)breakpoint condition:(nullable NSString *)condition
         hitCondition:(nullable NSString *)hitCondition logMessage:(nullable NSString *)logMessage;
/// Every breakpoint enabled, or disabled; every one removed.
- (void)setAllBreakpointsEnabled:(BOOL)enabled;
- (void)removeAllBreakpoints;

/// A click in the gutter, as Xcode's: no breakpoint there, one is added;
/// one there is disabled, or enabled again.
- (void)clickBreakpointAtLine:(NSInteger)line inFile:(NSString *)path;
/// Debug > Toggle Breakpoint (⌘\): added, or removed.
- (void)toggleBreakpointAtLine:(NSInteger)line inFile:(NSString *)path;

/// @a path's breakpoints follow @a textModel's edits from now on (the
/// model is not retained). Each file has one model; a second replaces it.
- (void)attachTextModel:(UDTextModel *)textModel toFile:(NSString *)path;
- (nullable UDTextModel *)textModelForFile:(NSString *)path;

/// The line the debugger stands at, the selected frame's (Xcode's green
/// line): set by the debug session, nil when it runs or has ended. Shown
/// in the file's text model as an UDInstructionPointerDecorationOwner
/// decoration while the file is open.
@property (nonatomic, readonly, copy, nullable) NSString *instructionPointerFile;
@property (nonatomic, readonly) NSInteger instructionPointerLine;
- (void)setInstructionPointerFile:(nullable NSString *)path line:(NSInteger)line;

/// The session running over these breakpoints, set by it while it runs:
/// the editors' hover and Run to Cursor ask it.
@property (nonatomic, weak, nullable) UDDebugSession *debugSession;

/// For a debug session: what its adapter made of a breakpoint (posted).
- (void)setBreakpoint:(UDBreakpoint *)breakpoint verified:(BOOL)verified message:(nullable NSString *)message;
/// Every breakpoint verified again (nothing says otherwise): the session ended.
- (void)resetVerification;

#pragma mark Watch expressions

/// The debug area's watch expressions, in order; each session evaluates
/// them (context "watch") whenever it stops or another frame is selected.
@property (nonatomic, readonly, copy) NSArray<NSString *> *watchExpressions;
- (void)addWatchExpression:(NSString *)expression;
/// @a expression in place of the one at @a index; an empty one removes it.
- (void)replaceWatchExpressionAtIndex:(NSUInteger)index withExpression:(NSString *)expression;
- (void)removeWatchExpressionAtIndex:(NSUInteger)index;
- (void)removeAllWatchExpressions;

#pragma mark Exception filters

/// The exception filters the last session's adapter offered (DAP's
/// ExceptionBreakpointsFilter: {filter, label, description?, default?}),
/// kept after it ends, as VS Code keeps them; set by the session.
@property (nonatomic, copy) NSArray<NSDictionary *> *exceptionFilters;
/// Whether the filter @a filterID is on: as chosen, or its default.
- (BOOL)isExceptionFilterEnabled:(NSString *)filterID;
- (void)setExceptionFilter:(NSString *)filterID enabled:(BOOL)enabled;

#pragma mark Keeping it

/// The breakpoints (files, lines, enabled, conditions), the watch
/// expressions and the exception filters with which are on.
- (NSDictionary *)propertyList;
/// What -propertyList gave, in place of what the store has.
- (void)restorePropertyList:(NSDictionary *)propertyList;
/// Kept in the user defaults under this key: restored from there when set,
/// and saved there whenever something changes. Nil: the host keeps it.
@property (nonatomic, copy, nullable) NSString *autosaveName;

@end

NS_ASSUME_NONNULL_END
