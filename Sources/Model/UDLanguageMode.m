/*---------------------------------------------------------------------------------------------
 *  UDLanguageMode.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLanguageMode.h"

@implementation UDLanguageMode

- (instancetype)initWithIdentifier:(NSString *)identifier
                        displayName:(NSString *)displayName
                     fileExtensions:(NSArray<NSString *> *)fileExtensions
                       languageFunc:(nullable LanguageFunc)languageFunc
                    highlightsQuery:(nullable NSString *)highlightsQuery
                       indentsQuery:(nullable NSString *)indentsQuery
                      lspLanguageID:(nullable NSString *)lspLanguageID
             languageServerCommand:(nullable NSArray<NSString *> *)languageServerCommand
            defaultNewDocumentText:(NSString *)defaultNewDocumentText
                languageConfiguration:(UDLanguageConfiguration *)languageConfiguration {
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

    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %@ (%@)>",
            NSStringFromClass(self.class), _identifier, _displayName];
}

@end
