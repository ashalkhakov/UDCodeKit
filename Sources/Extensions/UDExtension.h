#import <Foundation/Foundation.h>
#import <tree_sitter/api.h>

@protocol UDExtension <NSObject>

- (void)extensionDidLoad:(NSBundle *)bundle;
- (void)extensionWillUnload:(NSBundle *)bundle;

- (const void *)languageFunc;

@end
