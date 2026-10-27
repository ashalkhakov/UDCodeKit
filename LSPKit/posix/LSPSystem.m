//
//  LSPSystem.m (POSIX)
//  LSPKit
//

#import "../LSPSystem.h"
#include <signal.h>

void LSPIgnoreBrokenPipes(void) {
    signal(SIGPIPE, SIG_IGN);
}
