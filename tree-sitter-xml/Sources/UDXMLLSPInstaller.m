//
//  XMLLSPInstaller.m
//  TreeSitterXml
//
//  Created by artyom on 3/21/26.
//

#include <sys/xattr.h>
#import "UDXMLLSPInstaller.h"

@interface XMLLSPInstaller () <NSURLSessionDownloadDelegate>

@end

@implementation XMLLSPInstaller {
    NSUInteger _completedDownloads;  // tracks JRE + JAR concurrently
    NSURL *_javaURL;
    NSURL *_jarURL;
    NSURLSession              *_downloadSession;
    NSMutableDictionary       *_taskInfo;   // keyed by NSNumber (taskIdentifier)
}

- (instancetype)init {
    if (self = [super init]) {
        _taskInfo = [NSMutableDictionary dictionary];
    }
    return self;
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
    [self downloadJREIfNeededThenJAR];
}

- (void)downloadJREIfNeededThenJAR {
    if (![self isJREInstalled]) {
        [self downloadJREWithProgress:^(double p) {
            [self.delegate installer:self downloadProgress:p label:@"Downloading Java runtime…"];
        } completion:^(NSError *err) {
            if (err) { [self failWithError:err]; return; }
            [self downloadJARIfNeededThenFinish];
        }];
    } else {
        [self downloadJARIfNeededThenFinish];
    }
}

- (void)downloadJARIfNeededThenFinish {
    if (![self isJARInstalled]) {
        [self downloadJARWithProgress:^(double p) {
            [self.delegate installer:self downloadProgress:p label:@"Downloading XML language server…"];
        } completion:^(NSError *err) {
            if (err) { [self failWithError:err]; return; }
            [self removeQuarantineFromURL:self.installedJarURL completion:^(NSError *qErr) {
                if (qErr) { [self failWithError:qErr]; return; }
                [self finishInstallation];
            }];
        }];
    } else {
        [self finishInstallation];
    }
}

- (void)finishInstallation {
    NSURL *java = [self installedJavaURL];
    NSURL *jar  = [self installedJarURL];

    if (!java || !jar) {
        [self failWithError:[NSError errorWithDomain:@"XMLLSPInstaller"
                                               code:-1
                                           userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"Installation incomplete: java=%@ jar=%@", java, jar]
        }]];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        _state   = XMLLSPInstallStateReady;
        _javaURL = java;
        _jarURL  = jar;
        [self.delegate installerDidFinish:self javaURL:java jarURL:jar];
    });
}

- (void)failWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_state == XMLLSPInstallStateFailed) return;  // report once
        _state = XMLLSPInstallStateFailed;
        [self.delegate installer:self didFailWithError:error];
    });
}

#pragma mark - Paths

- (NSURL *)appSupportURL {
    NSURL *base = [[[NSFileManager defaultManager]
                    URLsForDirectory:NSApplicationSupportDirectory
                    inDomains:NSUserDomainMask] firstObject];
    return [base URLByAppendingPathComponent:@"UDCode/LSP/XML"];
}

- (nullable NSURL *)installedJavaURL {
    NSError *error;
    NSArray<NSURL *> *contents = [[NSFileManager defaultManager]
                                  contentsOfDirectoryAtURL:self.appSupportURL
                                  includingPropertiesForKeys:nil
                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                  error:&error];
    
    if (error) return nil;
    
    for (NSURL *item in contents) {
        if ([item.lastPathComponent hasPrefix:@"jdk-"]) {
            NSURL *java = [item URLByAppendingPathComponent:@"Contents/Home/bin/java"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:java.path]) {
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

#pragma mark - Shared Download Primitive (GNUstep-compatible)

- (void)downloadFileAtURL:(NSURL *)url
               completion:(void (^)(NSURL *tmpLocation, NSError *err))completion
                 progress:(void (^)(double))progress {

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest  = 30.0;
    config.timeoutIntervalForResource = 600.0;

    // Must use a delegate-based session to get progress callbacks
    // but use downloadTask so the file is written by the system (no quarantine)
    _downloadSession = [NSURLSession sessionWithConfiguration:config
                                                     delegate:self
                                                delegateQueue:nil];

    NSURLSessionDownloadTask *task = [_downloadSession downloadTaskWithURL:url];

    @synchronized(_taskInfo) {
        _taskInfo[@(task.taskIdentifier)] = @{
            @"completion" : [completion copy],
            @"progress"   : [progress copy],
            @"url"        : url,
        };
    }

    [task resume];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {

    if (totalBytesExpectedToWrite <= 0) return;

    double fraction = (double)totalBytesWritten / (double)totalBytesExpectedToWrite;
    void (^progress)(double) = nil;

    @synchronized(_taskInfo) {
        progress = _taskInfo[@(task.taskIdentifier)][@"progress"];
    }

    if (progress) progress(fraction);
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
didFinishDownloadingToURL:(NSURL *)location {

    void (^completion)(NSURL *, NSError *) = nil;

    @synchronized(_taskInfo) {
        completion = _taskInfo[@(task.taskIdentifier)][@"completion"];
        [_taskInfo removeObjectForKey:@(task.taskIdentifier)];
    }

    if (completion) completion(location, nil);
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {

    if (!error) return; // success handled in didFinishDownloadingToURL

    void (^completion)(NSURL *, NSError *) = nil;

    @synchronized(_taskInfo) {
        completion = _taskInfo[@(task.taskIdentifier)][@"completion"];
        [_taskInfo removeObjectForKey:@(task.taskIdentifier)];
    }

    if (completion) completion(nil, error);
}

#pragma mark - JRE Download

- (void)downloadJREWithProgress:(void (^)(double))progress
                     completion:(void (^)(NSError *))completion {
    NSString *arch;
#if defined(__aarch64__)
    arch = @"aarch64";
#else
    arch = @"x64";
#endif
    
    NSString *urlStr = [NSString stringWithFormat:
                        @"https://api.adoptium.net/v3/binary/latest/21/ga/mac/%@/jre/hotspot/normal/eclipse", arch];
    
    [self downloadFileAtURL:[NSURL URLWithString:urlStr]
                 completion:^(NSURL *tmpLocation, NSError *err) {
        if (err) { completion(err); return; }
        
        // Ensure destination directory exists before moving
        NSError *dirErr;
        [[NSFileManager defaultManager]
            createDirectoryAtURL:self.appSupportURL
         withIntermediateDirectories:YES
                          attributes:nil
                               error:&dirErr];
        if (dirErr) { completion(dirErr); return; }

        NSURL *tarball = [self.appSupportURL URLByAppendingPathComponent:@"jre.tar.gz"];
        NSError *moveErr;
        [[NSFileManager defaultManager] moveItemAtURL:tmpLocation
                                                toURL:tarball
                                                error:&moveErr];
        if (moveErr) { completion(moveErr); return; }

        [self extractTarball:tarball completion:^(NSError *extractErr) {
            [[NSFileManager defaultManager] removeItemAtURL:tarball error:nil];
            completion(extractErr);
        }];
    } progress:progress];
}

#pragma mark - JAR Download

- (void)downloadJARWithProgress:(void (^)(double))progress
                     completion:(void (^)(NSError *))completion {
    NSURL *url = [NSURL URLWithString:
                  @"https://download.eclipse.org/lemminx/releases/0.31.0/org.eclipse.lemminx-uber.jar"];
    
    [self downloadFileAtURL:url
                 completion:^(NSURL *tmpLocation, NSError *err) {
        if (err) { completion(err); return; }

        // Ensure destination directory exists before moving
        NSError *dirErr;
        [[NSFileManager defaultManager]
            createDirectoryAtURL:self.appSupportURL
         withIntermediateDirectories:YES
                          attributes:nil
                               error:&dirErr];
        if (dirErr) { completion(dirErr); return; }

        NSError *moveErr;
        [[NSFileManager defaultManager] moveItemAtURL:tmpLocation
                                                toURL:self.installedJarURL
                                                error:&moveErr];
        completion(moveErr);
    } progress:progress];
}

#pragma mark - Extraction (GNUstep-compatible)

- (NSError *)removeQuarantineFromPath:(NSString *)path {
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager]
        enumeratorAtPath:path];

    // Handle the root path itself first
    removexattr(path.fileSystemRepresentation, "com.apple.quarantine", XATTR_NOFOLLOW);

    NSString *relativePath;
    while ((relativePath = [enumerator nextObject])) {
        NSString *fullPath = [path stringByAppendingPathComponent:relativePath];
        removexattr(fullPath.fileSystemRepresentation, "com.apple.quarantine", XATTR_NOFOLLOW);
    }

    return nil; // removexattr returns -1 on failure but quarantine removal failing is non-fatal
}

- (void)removeQuarantineFromURL:(NSURL *)url completion:(void (^)(NSError *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *err = [self removeQuarantineFromPath:url.path];
        completion(err);
    });
}

- (void)extractTarball:(NSURL *)tarball completion:(void (^)(NSError *))completion {
    NSTask *tar = [[NSTask alloc] init];
    tar.launchPath = @"/usr/bin/tar";
    tar.arguments  = @[@"-xzf", tarball.path, @"-C", self.appSupportURL.path];

    tar.terminationHandler = ^(NSTask *t) {
        if (t.terminationStatus != 0) {
            completion([NSError errorWithDomain:@"XMLLSPInstaller"
                                           code:t.terminationStatus
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                           @"JRE extraction failed with status %d", t.terminationStatus]}]);
            return;
        }

        NSURL *java = [self installedJavaURL];
        if (!java) {
            completion([NSError errorWithDomain:@"XMLLSPInstaller"
                                           code:-1
                                       userInfo:@{NSLocalizedDescriptionKey:
                                           @"java binary not found after extraction"}]);
            return;
        }

        NSURL *jdkRoot = java.URLByDeletingLastPathComponent  // bin/
                             .URLByDeletingLastPathComponent  // Home/
                             .URLByDeletingLastPathComponent  // Contents/
                             .URLByDeletingLastPathComponent; // jdk-x.x.x/

        NSError *permErr = [self fixPermissionsInJREDirectory:jdkRoot];
        completion(permErr);
    };

    NSError *err;
    [tar launchAndReturnError:&err];
    if (err) completion(err);
}

- (NSError *)fixPermissionsInJREDirectory:(NSURL *)jdkRoot {
    NSURL *binDir = [[[jdkRoot URLByAppendingPathComponent:@"Contents"]
                               URLByAppendingPathComponent:@"Home"]
                               URLByAppendingPathComponent:@"bin"];

    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager]
        enumeratorAtURL:binDir
     includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                        options:0
                   errorHandler:nil];

    for (NSURL *fileURL in enumerator) {
        NSNumber *isRegular;
        [fileURL getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil];
        if (!isRegular.boolValue) continue;

        NSError *err;
        [[NSFileManager defaultManager] setAttributes:@{
            NSFilePosixPermissions: @(0755)
        } ofItemAtPath:fileURL.path error:&err];

        if (err) return err;
    }

    return nil;
}

@end
