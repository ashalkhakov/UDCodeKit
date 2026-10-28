/*---------------------------------------------------------------------------------------------
 *  UDPaths.m (POSIX)
 *--------------------------------------------------------------------------------------------*/

#import "../UDPaths.h"
#include <limits.h>
#include <stdlib.h>

/* realpath(3): Foundation's resolving takes macOS's /private off again. */
NSString *UDRealPath(NSString *path) {
    char resolved[PATH_MAX];
    return realpath(path.fileSystemRepresentation, resolved)
        ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:resolved length:strlen(resolved)] : path;
}

NSString *UDPathListSeparator(void) {
    return @":";
}

static BOOL UDIsProgram(NSString *path) {
    BOOL directory = NO;
    return path.length && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && !directory
        && [[NSFileManager defaultManager] isExecutableFileAtPath:path];
}

NSString *UDExecutableAtPath(NSString *path) {
    return UDIsProgram(path) ? path : nil;
}
