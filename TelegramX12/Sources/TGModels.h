#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TGMessageType) {
    TGMessageTypeText = 0,
    TGMessageTypePhoto,
    TGMessageTypeSticker,
    TGMessageTypeAnimation,
    TGMessageTypeVideo,
    TGMessageTypeVoiceNote,
    TGMessageTypeAudio,
    TGMessageTypeDocument,
    TGMessageTypeContact,
    TGMessageTypeLocation,
    TGMessageTypePoll,
    TGMessageTypeService,
    TGMessageTypeUnsupported
};

/// TDLib encodes int64 values as strings in JSON and int53 values as numbers.
/// These helpers accept both forms.
FOUNDATION_EXPORT int64_t TGInt64Value(id _Nullable value);
FOUNDATION_EXPORT int32_t TGInt32Value(id _Nullable value);
FOUNDATION_EXPORT BOOL TGBoolValue(id _Nullable value);
FOUNDATION_EXPORT NSString *TGStringValue(id _Nullable value);

FOUNDATION_EXPORT NSString *TGMessagePreviewText(NSDictionary *content);
FOUNDATION_EXPORT NSString *TGMessageContentType(NSDictionary *content);
FOUNDATION_EXPORT BOOL TGMessageContentIsService(NSDictionary *content);

/// Formats byte sizes in Telegram style (GB / MB / KB / B)
FOUNDATION_EXPORT NSString *TGDataSizeString(int64_t size);
/// Formats durations as mm:ss or hh:mm:ss
FOUNDATION_EXPORT NSString *TGDurationString(int32_t seconds);

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
@property (nonatomic) int64_t lastReadInboxMessageId;
@property (nonatomic) int64_t lastReadOutboxMessageId;
@property (nonatomic) BOOL isMuted;
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
@property (nonatomic) BOOL isRead;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic) TGMessageType messageType;
@property (nonatomic) BOOL isService;
@property (nonatomic) BOOL isSending;
@property (nonatomic) BOOL isFailed;
/// Synthetic in-memory row marking the first unread message (no TDLib id).
@property (nonatomic) BOOL isUnreadDivider;
/// Synthetic in-memory row drawing the day heading ("Dziś", "Wczoraj", …).
/// Rendered as a service row; the id is always 0.
@property (nonatomic) BOOL isDateDivider;
@property (nonatomic) int64_t senderId;
@property (nonatomic) BOOL senderIsUser;
@property (nonatomic, strong) NSDictionary *raw;

// Reply / forward / edit metadata (M3)
/// Id of the message this one replies to (0 when not a reply).
@property (nonatomic) int64_t replyToMessageId;
/// One-line preview of the quoted message, filled from `reply_to.content`.
@property (nonatomic, copy, nullable) NSString *replyToText;
/// Sender of the quoted message, resolved lazily by the chat controller.
@property (nonatomic, copy, nullable) NSString *replyToSenderName;
/// Raw `reply_to.origin` (MessageOrigin) for the quoted message, when known.
@property (nonatomic, strong, nullable) NSDictionary *replyToOrigin;
/// Raw `forward_info` for forwarded messages; nil otherwise.
@property (nonatomic, strong, nullable) NSDictionary *forwardInfo;
/// Unix timestamp of the last edit; 0 when the message was never edited.
@property (nonatomic) int32_t editDate;

// Albums (photo/video collages). A synthetic row merges consecutive messages
// that share the same TDLib `media_album_id`.
@property (nonatomic) int64_t mediaAlbumId;
@property (nonatomic) BOOL isAlbum;
@property (nonatomic, strong, nullable) NSArray<TGMessage *> *albumMessages;

// Media attributes
/// Full-resolution file id for photos (the largest available size).
/// Used by the photo viewer; the bubble thumbnail uses mediaFileId.
@property (nonatomic) int32_t fullResFileId;
@property (nonatomic) int32_t mediaFileId;
@property (nonatomic) int32_t thumbnailFileId;
@property (nonatomic, copy, nullable) NSString *mediaLocalPath;
@property (nonatomic) CGFloat mediaWidth;
@property (nonatomic) CGFloat mediaHeight;
@property (nonatomic) int32_t mediaDuration;
@property (nonatomic, copy, nullable) NSString *mediaCaption;
@property (nonatomic, copy, nullable) NSString *mediaFileName;
@property (nonatomic) int64_t mediaFileSize;
@property (nonatomic, copy, nullable) NSString *stickerEmoji;
@property (nonatomic, strong, nullable) NSData *minithumbnailData;
@property (nonatomic, copy, nullable) NSString *mimeType;
@property (nonatomic, copy, nullable) NSString *mediaTitle;
@property (nonatomic, copy, nullable) NSString *mediaPerformer;
@property (nonatomic) double latitude;
@property (nonatomic) double longitude;
@property (nonatomic, copy, nullable) NSString *contactName;
@property (nonatomic, copy, nullable) NSString *contactPhone;
@property (nonatomic, copy, nullable) NSString *pollQuestion;
@property (nonatomic, strong, nullable) NSArray<NSString *> *pollOptions;

+ (instancetype)messageWithDictionary:(NSDictionary *)dictionary;
- (void)updateWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
