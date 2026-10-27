/*---------------------------------------------------------------------------------------------
 *  UDRealPath.h
 *
 *  A file's real path, as a compiler records it and a debugger matches
 *  breakpoints against: its links followed (macOS's /var is /private/var; a
 *  project may be opened through a link or a junction). One implementation
 *  for each system, in a folder of its own (posix/, windows/).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

/// @a path's real path; @a path itself when it has none (it is not there).
NSString *UDRealPath(NSString *path);
