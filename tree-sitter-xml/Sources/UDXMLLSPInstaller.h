//
//  XMLLSPInstaller.h
//  TreeSitterXml
//
//  Created by artyom on 3/21/26.
//

#import <Foundation/Foundation.h>

@class XMLLSPInstaller;

typedef NS_ENUM(NSInteger, XMLLSPInstallState) {
    XMLLSPInstallStateUnknown,       // haven't checked yet
    XMLLSPInstallStateNeedsConsent,  // need to ask user
    XMLLSPInstallStateDownloading,   // in progress
    XMLLSPInstallStateReady,         // java + jar both present
    XMLLSPInstallStateFailed,        // unrecoverable error
};

@protocol XMLLSPInstallerDelegate <NSObject>
/// Installer needs to ask the user for consent. Present your UI here,
/// then call -userGrantedConsent: with YES or NO.
- (void)installerNeedsConsent:(XMLLSPInstaller *)installer;

/// Progress update during download (0.0 – 1.0). Every callback is on the main thread.
- (void)installer:(XMLLSPInstaller *)installer downloadProgress:(double)progress label:(NSString *)label;

/// Installation completed successfully.
- (void)installerDidFinish:(XMLLSPInstaller *)installer javaURL:(NSURL *)java jarURL:(NSURL *)jar;

/// Installation failed.
- (void)installer:(XMLLSPInstaller *)installer didFailWithError:(NSError *)error;
@end

@interface XMLLSPInstaller : NSObject
@property (nonatomic, readonly) XMLLSPInstallState state;
@property (nonatomic, weak) id<XMLLSPInstallerDelegate> delegate;
@property (nonatomic, strong) NSURL *javaURL;
@property (nonatomic, strong) NSURL *jarURL;

- (void)checkInstalled;          // at load: whether the server is there, no prompt
- (void)beginIfNeeded;           // when an XML document wants the server: asks once
- (void)userGrantedConsent:(BOOL)granted;
@end
