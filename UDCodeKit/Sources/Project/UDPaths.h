/*---------------------------------------------------------------------------------------------
 *  UDPaths.h
 *
 *  Paths as the system has them: a file's real path, as a compiler records
 *  it and a debugger matches breakpoints against, its links followed
 *  (macOS's /var is /private/var; a project may be opened through a link or
 *  a junction); what separates the folders of a path list ($PATH's ':',
 *  Windows' ';'); and the file a program is (Windows' ends in .exe, which
 *  a build adds and a command leaves out). One implementation for each system, in a folder of its
 *  own (posix/, windows/).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

/// @a path's real path; @a path itself when it has none (it is not there).
UDCODEKIT_EXPORT NSString *UDRealPath(NSString *path);

/// What separates the folders of a list of them (UD_PLUGINS_PATH, PATH).
UDCODEKIT_EXPORT NSString *UDPathListSeparator(void);

/// The program at @a path: the file there, or on Windows @a path.exe first;
/// nil when there is none to run.
UDCODEKIT_EXPORT NSString *UDExecutableAtPath(NSString *path);
