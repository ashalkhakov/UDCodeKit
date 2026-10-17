/*---------------------------------------------------------------------------------------------
 *  UDBreakpointStore.h
 *
 *  The breakpoints of a workspace's files, and where the debugger stands in
 *  them: one store per window (or per workspace), shared by its editors,
 *  which show and set the breakpoints in their gutters, and by the debug
 *  session, which sends them to the adapter and puts the instruction
 *  pointer there.
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

NS_ASSUME_NONNULL_BEGIN

/// The breakpoints of a file changed: added, removed, enabled or disabled,
/// moved by an edit, or verified by the adapter. The object is the store;
/// UDBreakpointStoreFileKey names the file.
extern NSNotificationName const UDBreakpointStoreDidChangeNotification;
/// The instruction pointer moved, or went: the object is the store;
/// UDBreakpointStoreFileKey names the file it was in and the one it is in
/// now (an array of one or two paths).
extern NSNotificationName const UDBreakpointStoreDidMoveInstructionPointerNotification;
extern NSString * const UDBreakpointStoreFileKey;

/// The decorations' owners in an attached text model.
extern NSString * const UDBreakpointDecorationOwner;
extern NSString * const UDInstructionPointerDecorationOwner;

/// A breakpoint: a line of a file, enabled or not.
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
@end

@interface UDBreakpointStore : NSObject

/// Every file with breakpoints, sorted.
@property (nonatomic, readonly) NSArray<NSString *> *files;

/// A file's breakpoints, by line.
- (NSArray<UDBreakpoint *> *)breakpointsInFile:(NSString *)path;
- (nullable UDBreakpoint *)breakpointAtLine:(NSInteger)line inFile:(NSString *)path;

/// A new breakpoint, enabled; the one there when there is one.
- (UDBreakpoint *)addBreakpointAtLine:(NSInteger)line inFile:(NSString *)path;
- (void)removeBreakpoint:(UDBreakpoint *)breakpoint;
- (void)setBreakpoint:(UDBreakpoint *)breakpoint enabled:(BOOL)enabled;

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

/// For a debug session: what its adapter made of a breakpoint (posted).
- (void)setBreakpoint:(UDBreakpoint *)breakpoint verified:(BOOL)verified message:(nullable NSString *)message;
/// Every breakpoint verified again (nothing says otherwise): the session ended.
- (void)resetVerification;

@end

NS_ASSUME_NONNULL_END
