//
//  LSPSystem.m (Windows)
//  LSPKit
//

#import "../LSPSystem.h"

/// Windows has no SIGPIPE: a write to a pipe whose reader has gone fails
/// as it is.
void LSPIgnoreBrokenPipes(void) {
}
