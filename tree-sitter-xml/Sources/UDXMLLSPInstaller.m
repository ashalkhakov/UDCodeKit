//
//  XMLLSPInstaller.m
//  TreeSitterXml
//
//  Created by artyom on 3/21/26.
//
//  One step at a time, on the main thread: the session calls back on the
//  main queue, tar's end comes as NSTaskDidTerminateNotification. The steps
//  are the Java runtime (Adoptium's JRE for this system: a macOS bundle's
//  Contents/Home, or Linux's plain tree) and LemMinX's jar, each only when
//  missing.
//

#ifdef __APPLE__
#include <sys/xattr.h>
#endif
#import "UDXMLLSPInstaller.h"

typedef NS_ENUM(NSInteger, XMLLSPInstallStep) {
    XMLLSPInstallStepNone,
    XMLLSPInstallStepJRE,
    XMLLSPInstallStepJAR,
};

@interface XMLLSPInstaller () <NSURLSessionDownloadDelegate>
@end

@implementation XMLLSPInstaller {
    NSURLSession *_downloadSession;
    XMLLSPInstallStep _step;        // what is downloading or unpacking
    NSTask *_tar;
    NSURL *_tarball;
    NSUInteger _redirects;          // followed by hand this step
    NSURLSessionTask *_task;        // the download the step waits for
}

- (void)checkInstalled {
    if ([self isJREInstalled] && [self isJARInstalled]) {
        _state = XMLLSPInstallStateReady;
        _javaURL = [self installedJavaURL];
        _jarURL  = [self installedJarURL];
    }
}

- (void)beginIfNeeded {
    // Asked already (and answered, or downloading): not again.
    if (_state == XMLLSPInstallStateNeedsConsent || _state == XMLLSPInstallStateDownloading ||
        _state == XMLLSPInstallStateFailed) return;
    if ([self isJREInstalled] && [self isJARInstalled]) {
        _state = XMLLSPInstallStateReady;
        _javaURL = [self installedJavaURL];
        _jarURL  = [self installedJarURL];
        return;  // nothing to do, host can query synchronously
    }

    _state = XMLLSPInstallStateNeedsConsent;
    [(NSObject *)self.delegate performSelector:@selector(installerNeedsConsent:) withObject:self afterDelay:0];
}

- (void)userGrantedConsent:(BOOL)granted {
    if (!granted) {
        _state = XMLLSPInstallStateFailed;
        return;
    }

    _state = XMLLSPInstallStateDownloading;
    [self nextStep];
}

#pragma mark - Steps

/// The next missing piece, or the end.
- (void)nextStep {
    _redirects = 0;
    if (![self isJREInstalled]) {
        _step = XMLLSPInstallStepJRE;
        [self downloadURL:[self JREURL]];
    } else if (![self isJARInstalled]) {
        _step = XMLLSPInstallStepJAR;
        [self downloadURL:[NSURL URLWithString:
            @"https://download.eclipse.org/lemminx/releases/0.31.0/org.eclipse.lemminx-uber.jar"]];
    } else {
        _step = XMLLSPInstallStepNone;
        [self finishInstallation];
    }
}

- (NSString *)stepLabel {
    return _step == XMLLSPInstallStepJRE ? @"Downloading Java runtime…" : @"Downloading XML language server…";
}

/// Adoptium's latest Java 21 runtime for this system and architecture.
- (NSURL *)JREURL {
#if defined(__aarch64__) || defined(__arm64__)
    NSString *arch = @"aarch64";
#else
    NSString *arch = @"x64";
#endif
#ifdef __APPLE__
    NSString *os = @"mac";
#else
    NSString *os = @"linux";
#endif
    return [NSURL URLWithString:[NSString stringWithFormat:
        @"https://api.adoptium.net/v3/binary/latest/21/ga/%@/%@/jre/hotspot/normal/eclipse", os, arch]];
}

- (void)finishInstallation {
    NSURL *java = [self installedJavaURL];
    NSURL *jar  = [self installedJarURL];

    if (!java || ![self isJARInstalled]) {
        [self failWithError:[NSError errorWithDomain:@"XMLLSPInstaller"
                                               code:-1
                                           userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"Installation incomplete: java=%@ jar=%@", java, jar]
        }]];
        return;
    }

    [_downloadSession finishTasksAndInvalidate];
    _downloadSession = nil;
    _state   = XMLLSPInstallStateReady;
    _javaURL = java;
    _jarURL  = jar;
    [self.delegate installerDidFinish:self javaURL:java jarURL:jar];
}

- (void)failWithError:(NSError *)error {
    if (_state == XMLLSPInstallStateFailed) return;  // report once
    [_downloadSession invalidateAndCancel];
    _downloadSession = nil;
    _step = XMLLSPInstallStepNone;
    _state = XMLLSPInstallStateFailed;
    [self.delegate installer:self didFailWithError:error];
}

static NSError *UDInstallError(NSString *description) {
    return [NSError errorWithDomain:@"XMLLSPInstaller" code:-1
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
}

#pragma mark - Paths

- (NSURL *)appSupportURL {
    NSURL *base = [[[NSFileManager defaultManager]
                    URLsForDirectory:NSApplicationSupportDirectory
                    inDomains:NSUserDomainMask] firstObject];
    return [base URLByAppendingPathComponent:@"UDCode/LSP/XML"];
}

/// Where java is in an unpacked runtime: inside the bundle on macOS.
static NSString *const UDJavaInRuntime =
#ifdef __APPLE__
    @"Contents/Home/bin/java";
#else
    @"bin/java";
#endif

- (nullable NSURL *)installedJavaURL {
    NSArray<NSURL *> *contents = [[NSFileManager defaultManager]
                                  contentsOfDirectoryAtURL:self.appSupportURL
                                  includingPropertiesForKeys:nil
                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                  error:NULL];
    for (NSURL *item in contents) {
        if ([item.lastPathComponent hasPrefix:@"jdk-"]) {
            NSURL *java = [item URLByAppendingPathComponent:UDJavaInRuntime];
            if ([[NSFileManager defaultManager] isExecutableFileAtPath:java.path]) {
                return java;
            }
        }
    }
    return nil;
}

- (NSURL *)installedJarURL {
    return [self.appSupportURL URLByAppendingPathComponent:@"lemminx.jar"];
}

- (BOOL)isJREInstalled {
    return [self installedJavaURL] != nil;
}

- (BOOL)isJARInstalled {
    return [[NSFileManager defaultManager] fileExistsAtPath:self.installedJarURL.path];
}

#pragma mark - Downloading

- (void)downloadURL:(NSURL *)url {
    if (_downloadSession == nil) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest  = 30.0;
        config.timeoutIntervalForResource = 600.0;
        // The delegate is called on the main queue: one step at a time,
        // nothing to hand over between threads.
        _downloadSession = [NSURLSession sessionWithConfiguration:config
                                                         delegate:self
                                                    delegateQueue:[NSOperationQueue mainQueue]];
    }
    _task = [_downloadSession downloadTaskWithURL:url];
    [_task resume];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (task != _task || totalBytesExpectedToWrite <= 0) return;
    [self.delegate installer:self
            downloadProgress:(double)totalBytesWritten / (double)totalBytesExpectedToWrite
                       label:[self stepLabel]];
}

// The file is the session's only until this returns: it is moved now.
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
didFinishDownloadingToURL:(NSURL *)location {
    if (task != _task) return;
    NSHTTPURLResponse *response = [task.response isKindOfClass:[NSHTTPURLResponse class]]
        ? (NSHTTPURLResponse *)task.response : nil;
    NSInteger status = response ? response.statusCode : 200;
    if (status >= 300 && status < 400) {
        [self followRedirect:response ofTask:task];
        return;
    }
    if (status >= 400) {
        [self failWithError:UDInstallError([NSString stringWithFormat:@"%@ answered %ld",
                                            task.originalRequest.URL.host, (long)status])];
        return;
    }

    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:self.appSupportURL
                                  withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self failWithError:error];
        return;
    }

    if (_step == XMLLSPInstallStepJRE) {
        _tarball = [self.appSupportURL URLByAppendingPathComponent:@"jre.tar.gz"];
        [[NSFileManager defaultManager] removeItemAtURL:_tarball error:NULL];
        if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:_tarball error:&error]) {
            [self failWithError:error];
            return;
        }
        [self extractTarball];
    } else if (_step == XMLLSPInstallStepJAR) {
        [[NSFileManager defaultManager] removeItemAtURL:self.installedJarURL error:NULL];
        if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:self.installedJarURL error:&error]) {
            [self failWithError:error];
            return;
        }
        [self removeQuarantineFromPath:self.installedJarURL.path];
        [self nextStep];
    }
}

/// GNUstep's NSURLSession misses a redirect whose Location header is
/// lowercase, as HTTP/2 sends it (gnustep-patches#24): the 3xx is handed
/// over as the download. It is followed here instead, a few times at most.
- (void)followRedirect:(NSHTTPURLResponse *)response ofTask:(NSURLSessionTask *)task {
    NSString *location = nil;
    for (NSString *name in response.allHeaderFields) {
        if ([name caseInsensitiveCompare:@"Location"] == NSOrderedSame) location = response.allHeaderFields[name];
    }
    NSURL *url = location ? [NSURL URLWithString:location relativeToURL:task.originalRequest.URL].absoluteURL : nil;
    if (url == nil || ++_redirects > 5) {
        [self failWithError:UDInstallError([NSString stringWithFormat:@"%@ redirects nowhere",
                                            task.originalRequest.URL.host])];
        return;
    }
    [self downloadURL:url];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    // Success went through didFinishDownloadingToURL; a redirect's own task
    // may end with an error after the download it led to has started.
    if (task == _task && error != nil) [self failWithError:error];
}

#pragma mark - Unpacking

- (void)extractTarball {
    _tar = [[NSTask alloc] init];
    _tar.launchPath = @"/usr/bin/env";
    _tar.arguments  = @[ @"tar", @"-xzf", _tarball.path, @"-C", self.appSupportURL.path ];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_tarDidTerminate:)
                                                 name:NSTaskDidTerminateNotification object:_tar];
    @try {
        [_tar launch];
    } @catch (NSException *exception) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSTaskDidTerminateNotification object:_tar];
        _tar = nil;
        [self failWithError:UDInstallError([NSString stringWithFormat:@"tar does not start: %@", exception.reason])];
    }
}

- (void)_tarDidTerminate:(NSNotification *)notification {
    int status = _tar.terminationStatus;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSTaskDidTerminateNotification object:_tar];
    _tar = nil;
    [[NSFileManager defaultManager] removeItemAtURL:_tarball error:NULL];
    _tarball = nil;

    if (status != 0) {
        [self failWithError:UDInstallError([NSString stringWithFormat:@"JRE extraction failed with status %d", status])];
        return;
    }
    NSURL *java = [self installedJavaURL];
    if (java == nil) {
        [self failWithError:UDInstallError(@"java binary not found after extraction")];
        return;
    }
    [self removeQuarantineFromPath:[self runtimeRootOfJava:java].path];
    NSError *error = [self fixPermissionsInDirectory:java.URLByDeletingLastPathComponent];
    if (error != nil) {
        [self failWithError:error];
        return;
    }
    [self nextStep];
}

/// jdk-x.y.z/, from its java.
- (NSURL *)runtimeRootOfJava:(NSURL *)java {
    NSURL *root = java;
    for (NSUInteger i = 0; i < UDJavaInRuntime.pathComponents.count; i++) {
        root = root.URLByDeletingLastPathComponent;
    }
    return root;
}

/// What came from the internet loses its quarantine on macOS, which would
/// otherwise stop java and the jar from running; nothing elsewhere.
- (void)removeQuarantineFromPath:(NSString *)path {
#ifdef __APPLE__
    removexattr(path.fileSystemRepresentation, "com.apple.quarantine", XATTR_NOFOLLOW);
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:path];
    NSString *relativePath;
    while ((relativePath = [enumerator nextObject])) {
        NSString *fullPath = [path stringByAppendingPathComponent:relativePath];
        removexattr(fullPath.fileSystemRepresentation, "com.apple.quarantine", XATTR_NOFOLLOW);
    }
#endif
}

/// The runtime's bin/: executable.
- (NSError *)fixPermissionsInDirectory:(NSURL *)binDir {
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:binDir.path error:NULL]) {
        NSString *path = [binDir.path stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) continue;
        NSError *error = nil;
        if (![[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @(0755) }
                                              ofItemAtPath:path error:&error]) {
            return error;
        }
    }
    return nil;
}

@end
