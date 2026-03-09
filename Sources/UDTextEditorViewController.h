/*---------------------------------------------------------------------------------------------
 *  UDTextEditorViewController.h
 *
 *  NSViewController subclass that owns the text-editor pane:
 *    – scroll view + UDDiagnosticTextView
 *    – line-number gutter (left)
 *    – find-results / error-marks gutter (right)
 *    – find search field (top)
 *    – folding, bracket-match, structured-navigation, auto-indentation
 *
 *  Loaded from UDTextEditorViewController.xib.
 *  Initialise with -initWithTextStorage: before accessing .view so that the
 *  layout manager is wired before any parse is triggered.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDTextModelTextStorage.h"
#import "UDFindResultsGutterView.h"
#import "UDDiagnosticTextView.h"
#import "UDAutoIndenter.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDTextEditorViewController : NSViewController

/// The editor text view (UDDiagnosticTextView). Available after the view is loaded.
@property (nonatomic, weak, readonly) UDDiagnosticTextView    *textView;

/// The find-results / error-marks gutter on the right edge.
/// Set errorFractions on this whenever the diagnostic list changes.
@property (nonatomic, weak, readonly) UDFindResultsGutterView *gutterView;

/// Auto-indenter.  Call -configureWithLanguageFunc:indentsQuery: on it once
/// the language and indents query are known (e.g. in -windowDidLoad of the
/// owning NSWindowController).
@property (nonatomic, strong, readonly) UDAutoIndenter *autoIndenter;

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
    NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
