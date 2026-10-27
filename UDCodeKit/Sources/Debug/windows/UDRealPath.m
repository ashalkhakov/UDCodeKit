/*---------------------------------------------------------------------------------------------
 *  UDRealPath.m (Windows)
 *--------------------------------------------------------------------------------------------*/

#import "../UDRealPath.h"
#include <windows.h>

/* The path Windows opens the file by, its links and junctions followed
   (GetFinalPathNameByHandleW), without the \\?\ it starts with. */
NSString *UDRealPath(NSString *path) {
    NSUInteger length = path.length;
    unichar *wide = calloc(length + 1, sizeof(unichar));
    [path getCharacters:wide range:NSMakeRange(0, length)];
    HANDLE file = CreateFileW((LPCWSTR)wide, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                              OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    free(wide);
    if (file == INVALID_HANDLE_VALUE) return path;
    WCHAR resolved[32768];
    DWORD got = GetFinalPathNameByHandleW(file, resolved, sizeof resolved / sizeof resolved[0], FILE_NAME_NORMALIZED);
    CloseHandle(file);
    if (got == 0 || got >= sizeof resolved / sizeof resolved[0]) return path;
    NSString *real = [NSString stringWithCharacters:(const unichar *)resolved length:got];
    if ([real hasPrefix:@"\\\\?\\UNC\\"]) return [@"\\\\" stringByAppendingString:[real substringFromIndex:8]];
    if ([real hasPrefix:@"\\\\?\\"]) return [real substringFromIndex:4];
    return real;
}
