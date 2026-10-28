//
//  LSPSystem.m (POSIX)
//  LSPKit
//

#import "../LSPSystem.h"
#include <signal.h>
#include <sys/wait.h>

void LSPIgnoreBrokenPipes(void) {
    signal(SIGPIPE, SIG_IGN);
}

void LSPWaitForProcess(int processIdentifier) {
    waitpid(processIdentifier, NULL, 0);
}
