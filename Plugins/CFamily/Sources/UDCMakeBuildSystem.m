/*---------------------------------------------------------------------------------------------
 *  UDCMakeBuildSystem.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCMakeBuildSystem.h"
#import "UDCTestRunner.h"
#import "UDGoogleTestRunner.h"
#import "UDXCTestSourcesRunner.h"

@implementation UDCMakeBuildSystem

+ (BOOL)buildsProject:(UDProject *)project {
    return [project hasFile:@"CMakeLists.txt"];
}

+ (NSString *)name {
    return @"CMake";
}

- (NSString *)buildDirectory {
    // CMake Tools' cmake.buildDirectory, where the project says
    NSString *folder = self.project.folderURL.path;
    UDTasks *vscode = [[UDTasks alloc] initWithFolderURL:self.project.folderURL currentFileURL:nil];
    NSString *directory = [vscode.settings[@"cmake.buildDirectory"] isKindOfClass:[NSString class]]
                        ? [vscode substitute:vscode.settings[@"cmake.buildDirectory"]] : nil;
    if (!directory.length) return [folder stringByAppendingPathComponent:@"build"];
    return directory.isAbsolutePath ? directory : [folder stringByAppendingPathComponent:directory];
}

- (NSDictionary *)inferredSettings {
    NSString *directory = self.buildDirectory;
    NSString *build = [UDProject quotedArgument:[self.project relativePath:directory]];
    NSString *configure = [NSString stringWithFormat:@"cmake -S . -B %@ -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON", build];
    BOOL configured = [[NSFileManager defaultManager] fileExistsAtPath:[directory stringByAppendingPathComponent:@"CMakeCache.txt"]];
    if (!configured && ![self.project hasTool:@"make"] && [self.project hasTool:@"ninja"]) {
        configure = [configure stringByAppendingString:@" -G Ninja"];
    }
    return @{ @"build": [configure stringByAppendingFormat:@" && cmake --build %@", build],
              @"clean": [NSString stringWithFormat:@"cmake --build %@ --target clean", build] };
}

- (NSString *)testCommand {
    return [NSString stringWithFormat:@"ctest --test-dir %@ --output-on-failure",
            [UDProject quotedArgument:[self.project relativePath:self.buildDirectory]]];
}

- (NSArray<UDTestRunner *> *)testRunners {
    // CTest's (GoogleTest's discovered ones among them), else the test
    // executables TestMate's glob finds
    UDCTestRunner *ctest = [[UDCTestRunner alloc] initWithProject:self.project directory:self.buildDirectory];
    UDTestRunner *sources = [[UDXCTestSourcesRunner alloc] initWithProject:self.project];
    return ctest.listedTests.count ? @[ ctest, sources ] : @[ sources, [[UDGoogleTestRunner alloc] initWithProject:self.project] ];
}

@end
