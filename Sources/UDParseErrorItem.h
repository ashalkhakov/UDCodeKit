/*---------------------------------------------------------------------------------------------
 *  UDParseErrorItem.h
 *
 *  Lightweight model object representing a single TreeSitter parse error —
 *  either an ERROR node (unexpected token) or a MISSING node (a required
 *  token that was absent from the source).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDParseErrorItem : NSObject

/// 1-based line number of the error in the document.
@property (nonatomic) NSInteger line;

/// 0-based character column of the error in the document.
@property (nonatomic) NSInteger column;

/// Human-readable description, e.g. "Unexpected token" or "Missing <string>".
@property (nonatomic, copy) NSString *message;

- (instancetype)initWithLine:(NSInteger)line
                      column:(NSInteger)column
                     message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
