/*---------------------------------------------------------------------------------------------
 *  UDSourceControl.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSourceControl.h"

NSNotificationName const UDSourceControlDidChangeNotification = @"UDSourceControlDidChangeNotification";

static NSDictionary<NSString *, NSString *> *UDCredentialEnvironment;

NSDictionary<NSString *, NSString *> *UDSourceControlCredentialEnvironment(void) {
    return UDCredentialEnvironment ?: @{};
}

void UDSourceControlSetCredentialEnvironment(NSDictionary<NSString *, NSString *> *environment) {
    UDCredentialEnvironment = [environment copy];
}

@implementation UDSourceControlResource

- (instancetype)initWithPath:(NSString *)path originalPath:(NSString *)originalPath
                      letter:(NSString *)letter statusDescription:(NSString *)statusDescription
                     deleted:(BOOL)deleted object:(id)object {
    self = [super init];
    if (self) {
        _path = [path copy];
        _originalPath = [originalPath copy];
        _letter = [letter copy];
        _statusDescription = [statusDescription copy];
        _deleted = deleted;
        _object = object;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ %@", _letter, _path.lastPathComponent];
}

@end

@implementation UDSourceControlResourceGroup

- (instancetype)initWithIdentifier:(NSString *)identifier label:(NSString *)label
                         resources:(NSArray<UDSourceControlResource *> *)resources {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _label = [label copy];
        _resources = [resources copy];
    }
    return self;
}

@end

@implementation UDSourceControlCommit

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = _authorName = _authorEmail = _subject = _message = @"";
        _authorDate = [NSDate dateWithTimeIntervalSince1970:0];
        _parents = _refNames = @[];
    }
    return self;
}

- (NSString *)shortIdentifier {
    return _identifier.length > 7 ? [_identifier substringToIndex:7] : _identifier;
}

@end

@implementation UDSourceControlBlameRange
@end

@implementation UDSourceControlCommitFile
@end

@implementation UDSourceControlResult

- (instancetype)initSucceeded:(BOOL)succeeded message:(NSString *)message value:(id)value context:(id)context {
    self = [super init];
    if (self) {
        _succeeded = succeeded;
        _message = [message copy];
        _value = value;
        _context = context;
    }
    return self;
}

@end
