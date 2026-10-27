//
//  LSPSystem.h
//  LSPKit
//
//  What LSPKit needs of the system it runs on: one implementation for each,
//  in a folder of its own (posix/, windows/), which the build picks. Nothing
//  outside them asks which system it is.
//

#import <Foundation/Foundation.h>

/// Writing to a pipe whose reader has gone (a language server that ended)
/// fails, as an error, instead of ending the app: POSIX's SIGPIPE ignored.
void LSPIgnoreBrokenPipes(void);
