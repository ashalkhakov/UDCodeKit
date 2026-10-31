/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  UDLinkComputer.h
 *
 *  VS Code's LinkComputer (editor/common/languages/linkComputer.ts): the
 *  http://, https:// and file:// addresses written in any text, a comment's
 *  or a string's, the links every language mode has besides its own.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDLinkComputer : NSObject

/// The addresses in @a text, in its order: each a dictionary of
/// UDLinkRangeKey (NSValue, of the text's UTF-16) and UDLinkURLKey.
+ (NSArray<NSDictionary<NSString *, id> *> *)linksInText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
