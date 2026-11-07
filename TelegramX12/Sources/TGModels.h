#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// TDLib encodes int64 values as strings in JSON and int53 values as numbers.
/// These helpers accept both forms.
FOUNDATION_EXPORT int64_t TGInt64Value(id _Nullable value);
FOUNDATION_EXPORT int32_t TGInt32Value(id _Nullable value);
FOUNDATION_EXPORT BOOL TGBoolValue(id _Nullable value);
FOUNDATION_EXPORT NSString *TGStringValue(id _Nullable value);

FOUNDATION_EXPORT NSString *TGMessagePreviewText(NSDictionary *content);
FOUNDATION_EXPORT NSString *TGMessageContentType(NSDictionary *content);
FOUNDATION_EXPORT BOOL TGMessageContentIsService(NSDictionary *content);

@interface TGChat : NSObject

@property (nonatomic) int64_t chatId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *lastMessageText;
@property (nonatomic) int32_t lastMessageDate;
@property (nonatomic) int64_t lastMessageId;
@property (nonatomic) BOOL lastMessageIsOutgoing;
@property (nonatomic) NSInteger unreadCount;
@property (nonatomic) long long order;
@property (nonatomic) BOOL pinned;
@property (nonatomic) BOOL hasMainListPosition;
@property (nonatomic) BOOL isGroup;
@property (nonatomic) BOOL isChannel;
@property (nonatomic, strong) NSDictionary *raw;

+ (instancetype)chatWithDictionary:(NSDictionary *)dictionary;
- (void)updateWithDictionary:(NSDictionary *)dictionary;
- (void)applyPosition:(NSDictionary *)position;
- (void)applyPositions:(NSArray *)positions;
- (void)applyLastMessage:(NSDictionary *)message;

@end

@interface TGMessage : NSObject

@property (nonatomic) int64_t messageId;
@property (nonatomic) int64_t chatId;
@property (nonatomic) int32_t date;
@property (nonatomic) BOOL isOutgoing;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic) BOOL isService;
@property (nonatomic) BOOL isSending;
@property (nonatomic) BOOL isFailed;
@property (nonatomic) int64_t senderId;
@property (nonatomic) BOOL senderIsUser;
@property (nonatomic, strong) NSDictionary *raw;

+ (instancetype)messageWithDictionary:(NSDictionary *)dictionary;
- (void)updateWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
