//
//  TreeSitterTheme.h
//  TestApp
//
//  Created by artyom on 12/17/25.
//

#import <Foundation/Foundation.h>

@interface TreeSitterTheme : NSObject

- (instancetype)initWithMode:(BOOL)darkMode;
- (void)setTheme:(BOOL)darkMode;
- (NSDictionary *)styleAttributesForName:(NSString *)name;

@end
