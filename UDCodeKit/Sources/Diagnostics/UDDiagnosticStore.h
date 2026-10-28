//
//  UDDiagnosticStore.h
//  UDCodeKit
//
//  Created by artyom on 3/8/26.
//


#import <Foundation/Foundation.h>
#import "UDDiagnosticItem.h"

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue whenever any source's diagnostics change.
/// object = the UDDiagnosticStore that changed.
UDCODEKIT_EXPORT NSNotificationName const UDDiagnosticsDidChangeNotification;

/// Aggregates diagnostics from multiple independent sources (tree-sitter
/// parser, LSP, linters, …) into a single ordered list.
///
/// Each source owns its own partition; replacing one source's items never
/// disturbs another's.  The merged list is sorted by (line, column).
///
/// The store lives on the main thread: a change made there applies at once
/// (allDiagnostics reflects it on return) and posts
/// UDDiagnosticsDidChangeNotification; a change made on another thread is
/// applied on the main thread, later. Read it on the main thread.
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
