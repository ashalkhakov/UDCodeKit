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
#ifdef __APPLE__
    // Xcode's lldb-dap
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
    return [UDGNUstepMakeBuildSystem environment];
#else
    return nil;
#endif
}

- (NSDictionary *)initializationOptionsForLanguageServer:(NSArray<NSString *> *)command project:(UDProject *)project {
    if (![[command.firstObject lastPathComponent] hasPrefix:@"clangd"]) return nil;
    return @{ @"fallbackFlags": [UDCFamilyPlugin fallbackCompileFlagsForProject:project] };
}

+ (NSArray<NSString *> *)fallbackCompileFlagsForProject:(UDProject *)project {
    NSMutableArray<NSString *> *flags = [NSMutableArray array];
#ifdef GNUSTEP
    NSString *config = nil;
    for (NSString *tools in NSSearchPathForDirectoriesInDomains(GSToolsDirectory, NSAllDomainsMask, YES)) {
        NSString *candidate = [tools stringByAppendingPathComponent:@"gnustep-config"];
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) { config = candidate; break; }
    }
    NSString *objcFlags = config ? [UDToolLocator outputOf:config arguments:@[ @"--objc-flags" ]] : nil;
    for (NSString *flag in [UDProject argumentsOfCommandLine:objcFlags ?: @""]) {
        // what makes dependency files is make's business, not an index's
        if ([flag hasPrefix:@"-M"]) continue;
        [flags addObject:flag];
    }
#else
    NSString *sdk = [UDToolLocator outputOf:@"/usr/bin/xcrun" arguments:@[ @"--show-sdk-path" ]];
    if (sdk.length) [flags addObjectsFromArray:@[ @"-isysroot", sdk ]];
#endif
    [flags addObject:[@"-I" stringByAppendingString:project.folderURL.path]];
    return flags;
}

@end
