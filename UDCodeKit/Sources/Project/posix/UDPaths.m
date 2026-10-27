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
