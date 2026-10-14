/*---------------------------------------------------------------------------------------------
 *  UDFindModel.h
 *
 *  Find and replace over a UDTextModel, as VS Code's find model: the query
 *  and its options, the matches kept as decorations (UDFindDecorationOwner)
 *  that move with edits, navigation, and replacing. No AppKit: the find bar
 *  (UDFindBarViewController) is a view of it.
 *
 *  Costs. Changing the query or an option searches the whole text, once, up
 *  to UDFindModelMatchLimit matches. An edit searches only the lines it
 *  touched again (matches never span lines). Navigation searches the text
 *  from the cursor. Counting and ranking matches costs the matches, at most
 *  the limit.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDPieceTable.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted when the matches change — the query, an option, or an edit.
extern NSNotificationName const UDFindModelDidChangeNotification;

/// The most matches kept, as VS Code's MATCHES_LIMIT.
extern const NSUInteger UDFindModelMatchLimit;

@interface UDFindModel : NSObject

- (instancetype)initWithTextModel:(UDTextModel *)textModel NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, weak, readonly) UDTextModel *textModel;

/// The query and its options; setting any of them searches again.
@property (nonatomic, copy) NSString *searchString;
@property (nonatomic) BOOL isRegex;
@property (nonatomic) BOOL matchCase;
@property (nonatomic) BOOL wholeWord;

/// What Replace puts in: plain text, or with regex on, VS Code's pattern
/// ($1…$99 and $& for groups, $$ for $, \n and \t).
@property (nonatomic, copy) NSString *replaceString;

/// Whether the query can search: not empty, and a regex that compiles.
@property (nonatomic, readonly) BOOL isValid;

/// How many matches there are — at most UDFindModelMatchLimit after a
/// search, which -limitReached tells.
@property (nonatomic, readonly) NSUInteger matchCount;
@property (nonatomic, readonly) BOOL limitReached;

/// The matches, as their decorations, sorted by start.
- (NSArray<UDIntervalNode *> *)matchNodes;

/// The first match starting at or after @a offset, wrapping to the top.
- (nullable UDFindMatch *)matchFrom:(NSInteger)offset;
/// The last match ending at or before @a offset, wrapping to the bottom.
- (nullable UDFindMatch *)matchBefore:(NSInteger)offset;

/// 1-based: the rank among the matches of the one at [start, end), or 0
/// when that is not a match.
- (NSUInteger)indexOfMatchFrom:(NSInteger)start to:(NSInteger)end;

/// If [start, end) is a match, replaces it and returns where the
/// replacement ends; otherwise NSNotFound.
- (NSInteger)replaceMatchFrom:(NSInteger)start to:(NSInteger)end;

/// Replaces every match (not only the kept ones) in one edit call — one
/// undo step. Returns how many.
- (NSUInteger)replaceAll;

/// Forgets the matches (the find bar closed).
- (void)clear;

@end

NS_ASSUME_NONNULL_END
