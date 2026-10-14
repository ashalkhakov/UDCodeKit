//
//  UDDiagnosticStore.h
//  TestApp
//
//  Created by artyom on 3/8/26.
//


#import <Foundation/Foundation.h>
#import "UDDiagnosticItem.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue whenever any source's diagnostics change.
/// object = the UDDiagnosticStore that changed.
extern NSNotificationName const UDDiagnosticsDidChangeNotification;

/// Aggregates diagnostics from multiple independent sources (tree-sitter
/// parser, LSP, linters, …) into a single ordered list.
///
/// Each source owns its own partition; replacing one source's items never
/// disturbs another's.  The merged list is sorted by (line, column).
///
/// All mutation methods are thread-safe and always post
/// UDDiagnosticsDidChangeNotification on the main queue after a change.
@interface UDDiagnosticStore : NSObject

/// Maximum number of items kept per source.  Defaults to 100.
/// Excess items are silently dropped (first N are kept).
@property (nonatomic, assign) NSUInteger maxItemsPerSource;

/// Merged, sorted snapshot of all sources.  KVO-observable.
@property (nonatomic, readonly, copy) NSArray<UDDiagnosticItem *> *allDiagnostics;

/// Replace all diagnostics for source with items (capped to maxItemsPerSource).
/// Passing an empty array clears that source.
- (void)setDiagnostics:(NSArray<UDDiagnosticItem *> *)items
             forSource:(UDDiagnosticSource)source;

/// Append items to an existing source's list (still capped).
/// Useful for incremental updates from the LSP (textDocument/publishDiagnostics
/// often sends deltas rather than full replacements).
- (void)addDiagnostics:(NSArray<UDDiagnosticItem *> *)items
             forSource:(UDDiagnosticSource)source;

/// Remove all diagnostics for source.
- (void)clearSource:(UDDiagnosticSource)source;

/// Remove all diagnostics from every source.
- (void)clearAll;

@end

NS_ASSUME_NONNULL_END
