//
//  LSPSystem.m (Windows)
//  LSPKit
//

#import "../LSPSystem.h"
#include <windows.h>

/// Windows has no SIGPIPE: a write to a pipe whose reader has gone fails
/// as it is.
void LSPIgnoreBrokenPipes(void) {
}

void LSPWaitForProcess(int processIdentifier) {
    HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, (DWORD)processIdentifier);
    if (!process) return;
    WaitForSingleObject(process, INFINITE);
    CloseHandle(process);
}
