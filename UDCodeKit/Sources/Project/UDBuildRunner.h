/*---------------------------------------------------------------------------------------------
 *  UDBuildRunner.h
 *
 *  A project's build: its own command (make, cmake, xcodebuild, whatever the
 *  folder says; UDProject), run by the shell in the folder with the build's
 *  environment, its output as it comes, and what the compiler said about the
 *  sources picked out of it as diagnostics:
 *
 *    main.c:4:12: error: use of undeclared identifier 'x'
 *    Sources/Model.m:9: warning: ...
 *    make[1]: Entering directory '/home/me/project/Sources'
 *
 *  A file is named relative to the folder make was in when it compiled it
 *  (make says so when it changes folder), so each is resolved there. Each
 *  file's diagnostics are in a store of its own (UDDiagnosticSourceBuild),
 *  for an Issues navigator to list and an editor to take.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDDiagnosticStore.h"

NS_ASSUME_NONNULL_BEGIN

@class UDProject, UDBuildRunner;

/// A build's diagnostics' source.
extern UDDiagnosticSource const UDDiagnosticSourceBuild;

@protocol UDBuildRunnerDelegate <NSObject>
@optional
/// Output came: @a text, as the command printed it (both its outputs).
- (void)buildRunner:(UDBuildRunner *)runner didOutput:(NSString *)text;
/// The command ended (or was stopped): succeeded says how.
- (void)buildRunnerDidFinish:(UDBuildRunner *)runner;
@end

@interface UDBuildRunner : NSObject

- (instancetype)initWithProject:(UDProject *)project;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) UDProject *project;
@property (nonatomic, weak, nullable) id<UDBuildRunnerDelegate> delegate;

/// Runs @a command (a shell command line) in the project's folder; NO when
/// one runs already, or the shell can't start. What the last one found goes.
- (BOOL)runCommand:(NSString *)command;
/// Stops it (its process group: make's children too).
- (void)stop;

@property (nonatomic, readonly, getter=isRunning) BOOL running;
/// Ended with status 0 (and not stopped).
@property (nonatomic, readonly) BOOL succeeded;
@property (nonatomic, readonly) int terminationStatus;
/// The command that runs or ran.
@property (nonatomic, readonly, copy, nullable) NSString *command;

/// Everything it printed.
@property (nonatomic, readonly, copy) NSString *output;
/// The diagnostics, a store per file (by its absolute path), as they come.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, UDDiagnosticStore *> *diagnostics;
@property (nonatomic, readonly) NSUInteger errorCount;
@property (nonatomic, readonly) NSUInteger warningCount;

/// One line of compiler output read as a diagnostic, its file resolved in
/// @a folder; nil for a line that isn't one. (@a path set to its file.)
+ (nullable UDDiagnosticItem *)diagnosticOfLine:(NSString *)line inFolder:(NSString *)folder
                                            path:(NSString * _Nullable * _Nonnull)path;

@end

NS_ASSUME_NONNULL_END
