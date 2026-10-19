//
//  LSPTransport.h
//  LSPKit
//
//  JSON messages over a pair of streams, each one a header ending in a
//  blank line and Content-Length bytes of JSON: the base protocol the
//  Language Server Protocol and the Debug Adapter Protocol share. Over a
//  process it starts (its standard input and output; what it writes to
//  standard error goes to the delegate), or over any two file handles (a
//  pipe to an adapter in the same process, say).
//
//  Read with readInBackgroundAndNotify and, for a process, its end seen with
//  NSTaskDidTerminateNotification: everything reaches the delegate on the
//  main run loop, on macOS and on GNUstep.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class LSPTransport;

@protocol LSPTransportDelegate <NSObject>
/// A whole message, its JSON an object.
- (void)transport:(LSPTransport *)transport didReceiveMessage:(NSDictionary *)message;
@optional
/// The other end is gone: the process ended (or never started), or, over
/// file handles, what is read ended. Nothing more is read or written.
- (void)transportDidClose:(LSPTransport *)transport;
/// What the process wrote to its standard error. Without this, logged.
- (void)transport:(LSPTransport *)transport didReceiveErrorOutput:(NSString *)text;
@end

@interface LSPTransport : NSObject

/// Starts the program at @a path with @a arguments (in @a directory, when
/// given) and reads its output. When it cannot start, -launchError says why
/// and the delegate hears -transportDidClose: on the next turn of the run loop.
- (instancetype)initWithLaunchPath:(NSString *)path
                         arguments:(NSArray<NSString *> *)arguments
              currentDirectoryPath:(nullable NSString *)directory;

/// The environment a program started from here gets: this process's, with
/// what an AppImage's launcher changed to run the app put back as the
/// machine had it (its PATH and LD_LIBRARY_PATH, which it keeps as
/// APPIMAGE_HOST_PATH and APPIMAGE_HOST_LD_LIBRARY_PATH, and none of the
/// GNUstep and fontconfig settings it points into the image). Otherwise a
/// build, a shell, a debugger or a language server would run on the image's
/// libraries and see its GNUstep instead of the machine's.
+ (NSDictionary<NSString *, NSString *> *)hostEnvironment;
/// The same, of @a environment.
+ (NSDictionary<NSString *, NSString *> *)hostEnvironmentOf:(NSDictionary<NSString *, NSString *> *)environment;

/// Messages read from @a readHandle and written to @a writeHandle.
- (instancetype)initWithReadHandle:(NSFileHandle *)readHandle
                       writeHandle:(NSFileHandle *)writeHandle;

@property (nonatomic, weak, nullable) id<LSPTransportDelegate> delegate;

/// The process, when the transport started one.
@property (nonatomic, readonly, nullable) NSTask *task;
/// Why the process did not start.
@property (nonatomic, readonly, nullable) NSError *launchError;
/// Whether the other end is still there.
@property (nonatomic, readonly, getter=isOpen) BOOL open;

/// Writes @a message, framed. Does nothing once closed.
- (void)sendMessage:(NSDictionary *)message;

/// Stops reading and closes the streams; the process, if any, is asked to
/// end (SIGTERM). The delegate hears no more.
- (void)close;

/// The process is asked to end; the delegate hears -transportDidClose: when
/// it has.
- (void)terminate;

/// @a message as it goes over the wire: the header and the JSON.
+ (nullable NSData *)frameForMessage:(NSDictionary *)message;

@end

NS_ASSUME_NONNULL_END
