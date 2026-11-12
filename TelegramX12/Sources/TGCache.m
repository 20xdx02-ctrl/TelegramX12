#import "TGCache.h"

static NSInteger const TGCacheMaxChats = 100;
static NSInteger const TGCacheMaxMessagesPerChat = 24;
static NSInteger const TGCacheMaxRecentChats = 12;
static NSInteger const TGCacheMaxAvatars = 400;

@interface TGCache ()

@property (nonatomic, copy) NSString *cacheDirectory;
@property (nonatomic, copy) NSString *messagesDirectory;
@property (nonatomic, copy) NSString *avatarsDirectory;
@property (nonatomic) dispatch_queue_t cacheQueue;

// All properties below are confined to `cacheQueue`.
@property (nonatomic, strong) NSData *pendingChatsData;
@property (nonatomic) BOOL chatWriteScheduled;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *recentChatIds;

@end

@implementation TGCache

+ (instancetype)sharedCache {
    static TGCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[TGCache alloc] init];
    });
    return cache;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        _cacheDirectory = [documents stringByAppendingPathComponent:@"TGCache"];
        _messagesDirectory = [_cacheDirectory stringByAppendingPathComponent:@"messages"];
        _avatarsDirectory = [_cacheDirectory stringByAppendingPathComponent:@"avatars"];
        [fileManager createDirectoryAtPath:_cacheDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        [fileManager createDirectoryAtPath:_messagesDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        [fileManager createDirectoryAtPath:_avatarsDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        _cacheQueue = dispatch_queue_create("com.telegramx12.cache", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_cacheQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
        _recentChatIds = [NSMutableArray array];
        [self loadRecentChatIds];
    }
    return self;
}

#pragma mark - Paths

- (NSString *)chatsPath {
    return [self.cacheDirectory stringByAppendingPathComponent:@"chats.json"];
}

- (NSString *)recentPath {
    return [self.cacheDirectory stringByAppendingPathComponent:@"recent.json"];
}

- (NSString *)messagesPathForChat:(int64_t)chatId {
    return [self.messagesDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"messages-%lld.json", chatId]];
}

- (NSString *)filePathForAvatarIdentifier:(int64_t)identifier {
    return [self.avatarsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"avatar-%lld.img", identifier]];
}

- (NSString *)fileIdPathForAvatarIdentifier:(int64_t)identifier {
    return [self.avatarsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"avatar-%lld.id", identifier]];
}

#pragma mark - Chat list

- (NSArray<NSDictionary *> *)cachedChats {
    __block NSArray<NSDictionary *> *chats = @[];
    dispatch_sync(self.cacheQueue, ^{
        NSData *data = [NSData dataWithContentsOfFile:[self chatsPath]];
        if (data.length == 0) {
            return;
        }
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([object isKindOfClass:[NSArray class]]) {
            chats = (NSArray<NSDictionary *> *)object;
        }
    });
    return chats;
}

- (void)storeChats:(NSArray<NSDictionary *> *)chats {
    if (chats.count == 0 || ![NSJSONSerialization isValidJSONObject:chats]) {
        return;
    }
    NSArray *limited = chats.count > TGCacheMaxChats
        ? [chats subarrayWithRange:NSMakeRange(0, (NSUInteger)TGCacheMaxChats)]
        : chats;
    NSData *data = [NSJSONSerialization dataWithJSONObject:limited options:0 error:NULL];
    if (data == nil) {
        return;
    }
    dispatch_async(self.cacheQueue, ^{
        self.pendingChatsData = data;
        if (self.chatWriteScheduled) {
            return;
        }
        // Coalesce bursts of updates into a single write.
        self.chatWriteScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), self.cacheQueue, ^{
            self.chatWriteScheduled = NO;
            NSData *pending = self.pendingChatsData;
            self.pendingChatsData = nil;
            if (pending != nil) {
                [pending writeToFile:[self chatsPath] atomically:YES];
            }
        });
    });
}

#pragma mark - Messages

- (NSArray<NSDictionary *> *)cachedMessagesForChat:(int64_t)chatId {
    if (chatId == 0) {
        return @[];
    }
    __block NSArray<NSDictionary *> *messages = @[];
    dispatch_sync(self.cacheQueue, ^{
        NSData *data = [NSData dataWithContentsOfFile:[self messagesPathForChat:chatId]];
        if (data.length == 0) {
            return;
        }
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([object isKindOfClass:[NSArray class]]) {
            messages = (NSArray<NSDictionary *> *)object;
        }
    });
    return messages;
}

- (void)storeMessages:(NSArray<NSDictionary *> *)messages forChat:(int64_t)chatId {
    if (chatId == 0) {
        return;
    }
    NSArray *limited = messages.count > TGCacheMaxMessagesPerChat
        ? [messages subarrayWithRange:NSMakeRange(messages.count - TGCacheMaxMessagesPerChat, (NSUInteger)TGCacheMaxMessagesPerChat)]
        : messages;
    if (limited.count > 0 && ![NSJSONSerialization isValidJSONObject:limited]) {
        return;
    }
    NSData *data = limited.count > 0 ? [NSJSONSerialization dataWithJSONObject:limited options:0 error:NULL] : nil;
    if (limited.count > 0 && data == nil) {
        return;
    }
    dispatch_async(self.cacheQueue, ^{
        [self markRecentChatLocked:chatId];
        NSString *path = [self messagesPathForChat:chatId];
        if (data != nil) {
            [data writeToFile:path atomically:YES];
        } else {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        }
        [self pruneMessageCachesLocked];
    });
}

- (void)markChatOpened:(int64_t)chatId {
    if (chatId == 0) {
        return;
    }
    dispatch_async(self.cacheQueue, ^{
        [self markRecentChatLocked:chatId];
    });
}

#pragma mark - Recent chats bookkeeping (cacheQueue only)

- (void)loadRecentChatIds {
    NSData *data = [NSData dataWithContentsOfFile:[self recentPath]];
    if (data.length > 0) {
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([object isKindOfClass:[NSArray class]]) {
            for (id value in (NSArray *)object) {
                if ([value isKindOfClass:[NSNumber class]]) {
                    [self.recentChatIds addObject:value];
                }
            }
        }
    }
}

- (void)markRecentChatLocked:(int64_t)chatId {
    NSNumber *key = @(chatId);
    [self.recentChatIds removeObject:key];
    [self.recentChatIds insertObject:key atIndex:0];
    while (self.recentChatIds.count > TGCacheMaxRecentChats) {
        [self.recentChatIds removeLastObject];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.recentChatIds options:0 error:NULL];
    if (data != nil) {
        [data writeToFile:[self recentPath] atomically:YES];
    }
}

/// Drops message files of chats that fell out of the recent list.
- (void)pruneMessageCachesLocked {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [fileManager contentsOfDirectoryAtPath:self.messagesDirectory error:NULL];
    NSMutableSet<NSString *> *allowed = [NSMutableSet set];
    for (NSNumber *chatId in self.recentChatIds) {
        [allowed addObject:[[self messagesPathForChat:chatId.longLongValue] lastPathComponent]];
    }
    for (NSString *file in files) {
        if (![file hasPrefix:@"messages-"] || [allowed containsObject:file]) {
            continue;
        }
        [fileManager removeItemAtPath:[self.messagesDirectory stringByAppendingPathComponent:file] error:NULL];
    }
}

#pragma mark - Avatars

- (NSString *)avatarPathForIdentifier:(int64_t)identifier fileId:(int32_t)fileId {
    if (identifier == 0 || fileId <= 0) {
        return nil;
    }
    __block NSString *result = nil;
    dispatch_sync(self.cacheQueue, ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *path = [self filePathForAvatarIdentifier:identifier];
        if (![fileManager fileExistsAtPath:path]) {
            return;
        }
        NSString *storedId = [NSString stringWithContentsOfFile:[self fileIdPathForAvatarIdentifier:identifier]
                                                       encoding:NSUTF8StringEncoding
                                                          error:NULL];
        if (storedId.integerValue != (NSInteger)fileId) {
            return;
        }
        result = path;
    });
    return result;
}

- (void)storeAvatarFromPath:(NSString *)path
                 identifier:(int64_t)identifier
                     fileId:(int32_t)fileId {
    if (path.length == 0 || identifier == 0 || fileId <= 0) {
        return;
    }
    dispatch_async(self.cacheQueue, ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:path]) {
            return;
        }
        NSString *destination = [self filePathForAvatarIdentifier:identifier];
        NSString *sidecar = [self fileIdPathForAvatarIdentifier:identifier];
        NSString *storedId = [NSString stringWithContentsOfFile:sidecar encoding:NSUTF8StringEncoding error:NULL];
        if (storedId.integerValue == (NSInteger)fileId && [fileManager fileExistsAtPath:destination]) {
            return;
        }
        [fileManager removeItemAtPath:destination error:NULL];
        if (![fileManager copyItemAtPath:path toPath:destination error:NULL]) {
            return;
        }
        [[NSString stringWithFormat:@"%d", fileId] writeToFile:sidecar atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [self pruneAvatarsLocked];
    });
}

/// Keeps the avatar directory bounded; drops the least recently written files.
- (void)pruneAvatarsLocked {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [fileManager contentsOfDirectoryAtPath:self.avatarsDirectory error:NULL];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (NSString *file in files) {
        if (![file hasSuffix:@".img"]) {
            continue;
        }
        NSString *path = [self.avatarsDirectory stringByAppendingPathComponent:file];
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:NULL];
        NSDate *date = attributes[NSFileModificationDate] ?: [NSDate distantPast];
        [entries addObject:@{ @"path": path, @"date": date }];
    }
    if ((NSInteger)entries.count <= TGCacheMaxAvatars) {
        return;
    }
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"date"] compare:b[@"date"]];
    }];
    NSInteger excess = (NSInteger)entries.count - TGCacheMaxAvatars;
    for (NSInteger index = 0; index < excess; index++) {
        NSString *path = entries[(NSUInteger)index][@"path"];
        [fileManager removeItemAtPath:path error:NULL];
        [fileManager removeItemAtPath:[path stringByReplacingOccurrencesOfString:@".img" withString:@".id"] error:NULL];
    }
}

#pragma mark - Reset

- (void)clear {
    dispatch_sync(self.cacheQueue, ^{
        [self.recentChatIds removeAllObjects];
        self.pendingChatsData = nil;
        [[NSFileManager defaultManager] removeItemAtPath:self.cacheDirectory error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:self.cacheDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:self.messagesDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:self.avatarsDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    });
}

@end
