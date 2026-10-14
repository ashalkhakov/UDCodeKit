/*---------------------------------------------------------------------------------------------
 *  TreeSitterXmlPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterXmlPlugin.h"
#import "UDXMLTagMirror.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_xml(void);

@implementation TreeSitterXmlPlugin {
    NSBundle *_bundle;
    XMLLSPInstaller *_installer;
}


- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    _installer = [[XMLLSPInstaller alloc] init];
    _installer.delegate = self;
    [_installer checkInstalled];   // no prompt here: only when an XML document wants a server
    NSLog(@"TreeSitterXmlPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterXmlPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
    _installer.delegate = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"xml"]) return tree_sitter_xml;
    return NULL;
}

- (nullable id<UDLanguageKeyHandler>)keyHandlerForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"xml"]) return [[UDXMLTagMirror alloc] init];
    return nil;
}

- (nullable NSArray<NSString *> *)languageServerCommandForIdentifier:(NSString *)identifier {
    if (![identifier isEqualToString:@"xml"]) return nil;
    
    // If already ready (e.g. second launch), return immediately.
    // If still downloading, return nil — we'll notify the host when done.
    if (_installer.state == XMLLSPInstallStateReady) {
        return @[
            _installer.javaURL.path,
             @"-Xmx128M",
             @"-XX:+UseG1GC",
             @"-XX:+UseStringDeduplication",
             @"-DwatchParentProcess=false",
             
             // use system proxy configuration
             @"-Djava.net.useSystemProxies=true",
             @"-DwatchParentProcess=false",
             @"-jar",
             _installer.jarURL.path
        ];
    }
    return nil;
}

- (void)languageServerWantedForIdentifier:(NSString *)identifier {
    if (![identifier isEqualToString:@"xml"]) return;
    [_installer beginIfNeeded];    // asks once; downloads with consent
}

#pragma mark - XMLLSPInstallerDelegate

- (void)installerNeedsConsent:(XMLLSPInstaller *)installer {
    // Ask the host to show a consent prompt. This is your UI hook.
    // Exactly how you do this depends on your host's UI API —
    // it could be a NSAlert, an info bar, a notification, etc.
    //
    // For now: show an NSAlert on the main thread (already guaranteed by installer).
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"XML Support Requires Additional Components";
    alert.informativeText =
    @"To enable XML language features (auto-complete, validation), "
    @"the XML extension needs to download a Java runtime (~120 MB) "
    @"and the LemMinX language server (~30 MB).\n\n"
    @"These will be stored in the app's private storage and are never shared.";
    [alert addButtonWithTitle:@"Download"];
    [alert addButtonWithTitle:@"Not Now"];

    NSModalResponse response = [alert runModal];
    [installer userGrantedConsent:(response == NSAlertFirstButtonReturn)];
}

- (void)installer:(XMLLSPInstaller *)installer
 downloadProgress:(double)progress
            label:(NSString *)label {
    // Forward to whatever progress UI your host exposes.
    // e.g. post a notification the host observes:
    [[NSNotificationCenter defaultCenter]
     postNotificationName:@"UDExtensionDownloadProgressNotification"
     object:self
     userInfo:@{@"label": label, @"progress": @(progress)}];
}

- (void)installerDidFinish:(XMLLSPInstaller *)installer
                   javaURL:(NSURL *)java
                    jarURL:(NSURL *)jar {
    // Tell the host to re-query languageServerCommandForIdentifier:
    [[NSNotificationCenter defaultCenter]
     postNotificationName:UDExtensionLanguageServerDidBecomeReadyNotification
     object:self
     userInfo:@{UDExtensionLanguageServerReadyIdentifierKey: @"xml"}];
}

- (void)installer:(XMLLSPInstaller *)installer didFailWithError:(NSError *)error {
    // Show a non-blocking error — don't crash or block the editor
    NSLog(@"[XMLExtension] LSP install failed: %@", error.localizedDescription);
    // Optionally post a notification for the host to show a subtle error banner
}

@end
