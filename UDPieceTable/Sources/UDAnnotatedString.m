/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/

#import "UDAnnotatedString.h"

NSAttributedStringKey const UDAnnotationAttributeName = @"UDAnnotation";

@interface UDAnnotatedString ()
@property (nonatomic, strong) NSMutableAttributedString *attrStr;
@end

@implementation UDAnnotatedString

- (instancetype)initWithString:(NSString *)string {
    self = [super init];
    if (self) {
        _attrStr = [[NSMutableAttributedString alloc] initWithString:string];
    }
    return self;
}

- (NSString *)string {
    return [_attrStr string];
}

// MARK: - Setting / removing annotations

- (void)setAnnotation:(nullable id)annotation forRange:(NSRange)range {
    if (range.location + range.length > _attrStr.length) { return; }
    if (annotation) {
        [_attrStr addAttribute:UDAnnotationAttributeName value:annotation range:range];
    } else {
        [_attrStr removeAttribute:UDAnnotationAttributeName range:range];
    }
}

- (void)removeAnnotationsInRange:(NSRange)range {
    if (range.location + range.length > _attrStr.length) { return; }
    [_attrStr removeAttribute:UDAnnotationAttributeName range:range];
}

// MARK: - Querying annotations

- (NSArray<NSDictionary *> *)annotationsIntersectingRange:(NSRange)range {
    if (range.location >= _attrStr.length) { return @[]; }
    NSRange clampedRange = NSIntersectionRange(range, NSMakeRange(0, _attrStr.length));
    if (clampedRange.length == 0) { return @[]; }

    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    [_attrStr enumerateAttribute:UDAnnotationAttributeName
                         inRange:clampedRange
                         options:0
                      usingBlock:^(id _Nullable value, NSRange r, BOOL *stop) {
        if (!value) { return; }
        [result addObject:@{
            @"range":      [NSValue valueWithRange:r],
            @"annotation": value
        }];
    }];
    return [result copy];
}

- (NSArray<NSDictionary *> *)allAnnotations {
    if (_attrStr.length == 0) { return @[]; }
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    [_attrStr enumerateAttribute:UDAnnotationAttributeName
                         inRange:NSMakeRange(0, _attrStr.length)
                         options:0
                      usingBlock:^(id _Nullable value, NSRange r, BOOL *stop) {
        if (!value) { return; }
        [result addObject:@{
            @"range":      [NSValue valueWithRange:r],
            @"annotation": value
        }];
    }];
    return [result copy];
}

// MARK: - Applying edits

- (void)applyEditDeleteRange:(NSRange)deleteRange insertText:(NSString *)insertText {
    // NSMutableAttributedString adjusts all attribute ranges automatically.
    [_attrStr replaceCharactersInRange:deleteRange withString:insertText];

    // Inserted text must not inherit annotations from adjacent characters.
    // Clear the UDAnnotation attribute from the just-inserted range.
    if (insertText.length > 0) {
        NSRange insertedRange = NSMakeRange(deleteRange.location, insertText.length);
        [_attrStr removeAttribute:UDAnnotationAttributeName range:insertedRange];
    }
}

@end
