/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  NSMutableAttributedString-backed implementation of VS Code's AnnotatedString<T> concept.
 *  Original concept: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/tokens/annotations.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The NSAttributedString attribute key used to store annotation values.
/// The value can be any Objective-C object.
extern NSAttributedStringKey const UDAnnotationAttributeName;

// MARK: - UDAnnotatedString

/// An NSMutableAttributedString-backed string that associates arbitrary annotation
/// objects with character ranges.
///
/// This mirrors VS Code's @c AnnotatedString<T> system:
/// - Use @c setAnnotation:forRange: to attach a value to a range.
/// - Use @c applyEditDeleteRange:insertText: to splice the text; annotation ranges
///   are automatically adjusted by NSAttributedString's built-in bookkeeping.
/// - Use @c annotationsIntersectingRange: or @c allAnnotations to query.
///
/// Semantic note: @c applyEditDeleteRange:insertText: clears annotations from the
/// newly inserted characters (inserted text is unannotated by default), matching
/// VS Code's AnnotatedString semantics where insertions don't inherit annotations.
@interface UDAnnotatedString : NSObject

/// Creates an annotated string with the given plain text content and no annotations.
- (instancetype)initWithString:(NSString *)string;

/// The plain text content of the string.
@property (nonatomic, readonly) NSString *string;

/// Attaches @c annotation to every character in @c range.
/// Pass @c nil to remove any annotation from @c range.
- (void)setAnnotation:(nullable id)annotation forRange:(NSRange)range;

/// Removes any annotations from every character in @c range.
- (void)removeAnnotationsInRange:(NSRange)range;

/// Returns all (range, annotation) pairs whose range intersects @c range.
///
/// Each element of the returned array is an @c NSDictionary with:
/// - @c @"range":      @c NSValue wrapping an @c NSRange
/// - @c @"annotation": the annotation object
- (NSArray<NSDictionary *> *)annotationsIntersectingRange:(NSRange)range;

/// Returns all (range, annotation) pairs in the entire string.
///
/// Each element has the same dictionary keys as @c annotationsIntersectingRange:.
- (NSArray<NSDictionary *> *)allAnnotations;

/// Applies a text edit: replaces the characters in @c deleteRange with @c insertText.
///
/// NSAttributedString adjusts all annotation ranges accordingly.
/// Annotations are then removed from the newly inserted characters so that
/// inserted text starts unannotated.
- (void)applyEditDeleteRange:(NSRange)deleteRange insertText:(NSString *)insertText;

@end

NS_ASSUME_NONNULL_END
