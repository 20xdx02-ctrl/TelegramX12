#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Small on-disk cache that lets the app render the chat list and the most
/// recent messages of recently opened chats on the very first frame, before
/// TDLib finishes loading its own database.
///
/// Everything is stored as plain JSON in `Documents/TGCache`:
///   chats.json                    – last known chat list snapshot
///   messages/messages-<id>.json   – last few messages of a chat
///   recent.json                   – ordered list of chats with message cache
///
/// Disk writes happen on a serial utility queue and are coalesced, so callers
/// may invoke the store methods as often as state changes.
@interface TGCache : NSObject

+ (instancetype)sharedCache;

#pragma mark - Chat list

/// Chat dictionaries in the same shape TDLib returns, ready to be fed into
/// `TGChat chatWithDictionary:`.
- (NSArray<NSDictionary *> *)cachedChats;
- (void)storeChats:(NSArray<NSDictionary *> *)chats;

#pragma mark - Messages

/// Raw TDLib message dictionaries (oldest first), empty when nothing cached.
- (NSArray<NSDictionary *> *)cachedMessagesForChat:(int64_t)chatId;
- (void)storeMessages:(NSArray<NSDictionary *> *)messages forChat:(int64_t)chatId;

/// Marks a chat as recently opened so its message cache is kept around.
- (void)markChatOpened:(int64_t)chatId;

#pragma mark - Avatars

/// Local copy of an entity's avatar (chat id / user id), or nil when the cache
/// is empty or was stored for a different photo. TDLib file ids are only valid
/// within one run, so the on-disk key is the entity id and the file id is kept
/// in a sidecar for validation.
- (nullable NSString *)avatarPathForIdentifier:(int64_t)identifier fileId:(int32_t)fileId;
/// Copies a TDLib-downloaded photo into the cache for instant cold starts.
- (void)storeAvatarFromPath:(NSString *)path
                 identifier:(int64_t)identifier
                     fileId:(int32_t)fileId;

- (void)clear;

@end

NS_ASSUME_NONNULL_END
