/*---------------------------------------------------------------------------------------------
 *  UDLanguageMode.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLanguageMode.h"
#import "UDExtension.h"
#import "UDLanguageModeRegistry.h"

@implementation UDLanguageMode {
    BOOL _inheritanceResolved, _resolvingInheritance;
}

@synthesize languageServerCommand = _languageServerCommand;
@synthesize highlightsQuery = _highlightsQuery;

- (instancetype)initWithIdentifier:(NSString *)identifier
                        displayName:(NSString *)displayName
                     fileExtensions:(NSArray<NSString *> *)fileExtensions
                       languageFunc:(nullable LanguageFunc)languageFunc
                    highlightsQuery:(nullable NSString *)highlightsQuery
                       indentsQuery:(nullable NSString *)indentsQuery
                      lspLanguageID:(nullable NSString *)lspLanguageID
             languageServerCommand:(nullable NSArray<NSString *> *)languageServerCommand
            defaultNewDocumentText:(NSString *)defaultNewDocumentText
                languageConfiguration:(UDLanguageConfiguration *)languageConfiguration
                         keyHandler:(nullable id<UDLanguageKeyHandler>)keyHandler
                          extension:(nullable id<UDExtension>)extension {
    self = [super init];
    if (!self) return nil;

    _identifier             = [identifier copy];
    _displayName            = [displayName copy];
    _fileExtensions         = [fileExtensions copy];
    _languageFunc           = languageFunc;
    _highlightsQuery        = [highlightsQuery copy];
    _indentsQuery           = [indentsQuery copy];
    _lspLanguageID          = [lspLanguageID copy];
    _languageServerCommand  = [languageServerCommand copy];
    _defaultNewDocumentText = [defaultNewDocumentText copy];
    _languageConfiguration  = languageConfiguration ?: [UDLanguageConfiguration emptyConfiguration];
    _keyHandler             = keyHandler;
    _extension              = extension;

    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %@ (%@)>",
            NSStringFromClass(self.class), _identifier, _displayName];
}

/// The query, with those of the languages its first line says it inherits
/// ("; inherits: c", as Neovim's and tree-sitter's grammars write it; or
/// "; inherits: c,cpp") before it: Objective-C's adds to C's. Resolved the
/// first time it is asked for, when every mode has been registered.
- (NSString *)highlightsQuery {
    if (_highlightsQuery == nil || _resolvingInheritance) return _highlightsQuery;
    NSString *firstLine = [[_highlightsQuery componentsSeparatedByString:@"\n"] firstObject];
    NSString *prefix = @"; inherits:";
    if (![firstLine hasPrefix:prefix] || _inheritanceResolved) return _highlightsQuery;

    _resolvingInheritance = YES;                         // a cycle stops here
    NSMutableString *query = [NSMutableString string];
    for (NSString *name in [[firstLine substringFromIndex:prefix.length] componentsSeparatedByString:@","]) {
        NSString *parent = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        UDLanguageMode *mode = parent.length ? [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:parent] : nil;
        NSString *inherited = mode.highlightsQuery;
        if (inherited.length) [query appendFormat:@"%@\n", inherited];
    }
    [query appendString:_highlightsQuery];
    _resolvingInheritance = NO;
    _inheritanceResolved = YES;
    _highlightsQuery = [query copy];
    return _highlightsQuery;
}

- (NSArray<NSString *> *)languageServerCommand {
    if ([_extension respondsToSelector:@selector(languageServerCommandForIdentifier:)]) {
        return [_extension languageServerCommandForIdentifier:_identifier];
    }
    return _languageServerCommand;
}

- (NSArray<NSString *> *)debugAdapterCommand {
    if ([_extension respondsToSelector:@selector(debugAdapterCommandForIdentifier:)]) {
        return [_extension debugAdapterCommandForIdentifier:_identifier];
    }
    return nil;
}

- (NSDictionary *)debugLaunchArgumentsForFileURL:(NSURL *)fileURL {
    if ([_extension respondsToSelector:@selector(debugLaunchArgumentsForIdentifier:fileURL:)]) {
        NSDictionary *arguments = [_extension debugLaunchArgumentsForIdentifier:_identifier fileURL:fileURL];
        if (arguments) return arguments;
    }
    return fileURL.path ? @{ @"program": fileURL.path } : @{};
}

- (BOOL)hasPreview {
    return [self previewOfText:@"" baseURL:nil] != nil;
}

- (NSAttributedString *)previewOfText:(NSString *)text baseURL:(NSURL *)baseURL {
    if (![_extension respondsToSelector:@selector(previewOfText:forIdentifier:baseURL:)]) return nil;
    return [_extension previewOfText:text forIdentifier:_identifier baseURL:baseURL];
}

- (NSArray<NSDictionary<NSString *, id> *> *)linksInText:(NSString *)text baseURL:(NSURL *)baseURL {
    if (![_extension respondsToSelector:@selector(linksInText:forIdentifier:baseURL:)]) return @[];
    return [_extension linksInText:text forIdentifier:_identifier baseURL:baseURL] ?: @[];
}

@end
