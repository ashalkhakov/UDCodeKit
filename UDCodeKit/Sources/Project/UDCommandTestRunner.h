/*---------------------------------------------------------------------------------------------
 *  UDCommandTestRunner.h
 *
 *  The project's own way of running its tests, all at once, when no runner
 *  runs them one by one: tasks.json's test task, else UDProject -testCommand
 *  (the settings' "test", else the build system's: make check, ctest, ...).
 *  What its run prints marks the tests it names; none can run alone.
 *--------------------------------------------------------------------------------------------*/

#import "UDTestRunner.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDCommandTestRunner : UDTestRunner
@end

NS_ASSUME_NONNULL_END
