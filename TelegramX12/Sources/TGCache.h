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

- (void)clear;

@end

NS_ASSUME_NONNULL_END
