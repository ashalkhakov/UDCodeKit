/*---------------------------------------------------------------------------------------------
 *  UDBuildSystem.h
 *
 *  What a project's build system knows of it, as VS Code's extensions
 *  contribute task providers: whether it builds the folder; the commands that
 *  build and clean it; what the build makes that runs; how its tests are found
 *  and run (its UDTestRunners). UDProject asks the first that builds its
 *  folder and knows none of them: a bundle names its subclasses (UDExtension
 *  -buildSystemClasses: UDCode's CFamily, GNUstep make, Makefile.apple,
 *  Xcode, make, CMake), or an application registers them. Each runs the tool
 *  it is about, never reimplements it.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDProject.h"

NS_ASSUME_NONNULL_BEGIN

@class UDTestRunner;

@interface UDBuildSystem : NSObject

/// The build systems, in the order they are asked: those registered, then
/// the extensions'.
+ (NSArray<Class> *)classes;
/// Adds @a buildSystemClass (a subclass) before the extensions'.
+ (void)registerClass:(Class)buildSystemClass;
/// The class of the first of them that builds @a project; Nil: none does.
+ (nullable Class)classBuilding:(UDProject *)project;

// Each says (subclasses):

/// Whether it builds @a project's folder.
+ (BOOL)buildsProject:(UDProject *)project;
/// Its name, as the user knows it ("CMake", "GNUstep make").
+ (NSString *)name;

- (instancetype)initWithProject:(UDProject *)project;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, weak) UDProject *project;
/// The class's name.
@property (nonatomic, readonly, copy) NSString *name;

/// Its build and clean commands, and what runs ("run": {"program"}), as
/// the settings would say them: what the folder doesn't say otherwise.
- (NSDictionary *)inferredSettings;
/// What it builds that runs (relative to the folder), the schemes of the
/// toolbar; empty: it doesn't say.
@property (nonatomic, readonly, copy) NSArray<NSString *> *programs;
/// What runs when the settings don't say: inferredSettings' program, else
/// what the build asks its tool for (an Xcode project's); nil: nothing.
@property (nonatomic, readonly, copy, nullable) NSString *product;
/// What runs all its tests in one (make check, ctest, xcodebuild test).
@property (nonatomic, readonly, copy, nullable) NSString *testCommand;
/// What finds and runs its tests, made anew each time: none, unless it
/// knows better.
- (NSArray<UDTestRunner *> *)testRunners;

@end

NS_ASSUME_NONNULL_END
