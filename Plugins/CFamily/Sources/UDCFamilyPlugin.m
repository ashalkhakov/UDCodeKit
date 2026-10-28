/*---------------------------------------------------------------------------------------------
 *  UDCFamilyPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCFamilyPlugin.h"
#import "UDGNUstepMakeBuildSystem.h"
#import "UDMakeBuildSystem.h"
#import "UDXcodeBuildSystem.h"
#import "UDCMakeBuildSystem.h"
#import "UDGoogleTestRunner.h"
#import "UDXCTestSourcesRunner.h"
#import "UDCFamilyDebuggers.h"

@implementation UDCFamilyPlugin

- (void)extensionDidLoad:(NSBundle *)bundle {
}

- (void)extensionWillUnload:(NSBundle *)bundle {
}

- (const void *)languageFuncForIdentifier:(NSString *)identifier {
    return NULL;
}

- (NSArray<Class> *)buildSystemClasses {
#ifdef GNUSTEP
    return @[ [UDGNUstepMakeBuildSystem class], [UDMakeBuildSystem class], [UDCMakeBuildSystem class] ];
#else
    return @[ [UDAppleMakeBuildSystem class], [UDXcodeBuildSystem class], [UDMakeBuildSystem class], [UDCMakeBuildSystem class] ];
#endif
}

- (NSArray<Class> *)debuggerClasses {
#if defined(__APPLE__) || defined(_WIN32)
    // Xcode's lldb-dap; on Windows MSYS2's, which reads an Objective-C
    // object's ivars where its runtime put them (gdb takes each to be at
    // offset 0, as clang's debug information says of a non-fragile ivar)
    return @[ [UDLLDBDebugger class], [UDGDBDebugger class] ];
#else
    // gdb, which a distribution has, and which goes on where address
    // randomization can't be turned off (a container): lldb doesn't launch there
    return @[ [UDGDBDebugger class], [UDLLDBDebugger class] ];
#endif
}

/// The sources' XCTest cases and test executables (TestMate's way), where no
/// build system of ours has its say on them (ours name their own runners).
- (NSArray<UDTestRunner *> *)testRunnersForProject:(UDProject *)project {
    for (Class mine in [self buildSystemClasses]) {
        if ([project.buildSystem isKindOfClass:mine]) return @[];
    }
    return @[ [[UDXCTestSourcesRunner alloc] initWithProject:project], [[UDGoogleTestRunner alloc] initWithProject:project] ];
}

- (NSDictionary<NSString *, NSString *> *)environmentForProject:(UDProject *)project {
#ifdef GNUSTEP
    // GNUstep's, as GNUstep.sh sets it (a desktop doesn't run it): make finds
    // its makefiles, and what is built its libraries
    return [UDGNUstepMakeBuildSystem environmentForShell:project.shell];
#else
    return nil;
#endif
}

- (NSDictionary *)initializationOptionsForLanguageServer:(NSArray<NSString *> *)command project:(UDProject *)project {
    if (![[command.firstObject lastPathComponent] hasPrefix:@"clangd"]) return nil;
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[@"fallbackFlags"] = [UDCFamilyPlugin fallbackCompileFlagsForProject:project];
#ifdef GNUSTEP
    // each file's own, as make compiles it (-fobjc-arc, its -I's)
    if ([project.buildSystem isKindOfClass:[UDGNUstepMakeBuildSystem class]]) {
        NSDictionary *commands = ((UDGNUstepMakeBuildSystem *)project.buildSystem).compileCommands;
        if (commands.count) options[@"compilationDatabaseChanges"] = commands;
    }
#endif
    return options;
}

+ (NSArray<NSString *> *)fallbackCompileFlagsForProject:(UDProject *)project {
    NSMutableArray<NSString *> *flags = [NSMutableArray array];
#ifdef GNUSTEP
    [flags addObjectsFromArray:[UDGNUstepMakeBuildSystem compileFlagsForShell:project.shell]];
#else
    NSString *sdk = [UDToolLocator outputOf:@"/usr/bin/xcrun" arguments:@[ @"--show-sdk-path" ]];
    if (sdk.length) [flags addObjectsFromArray:@[ @"-isysroot", sdk ]];
#endif
    [flags addObject:[@"-I" stringByAppendingString:project.folderURL.path]];
    return flags;
}

@end
