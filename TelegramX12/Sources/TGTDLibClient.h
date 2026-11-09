#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TGResponseBlock)(NSDictionary *response);
typedef void (^TGChatListBlock)(NSArray<NSNumber *> * _Nullable chatIds, NSDictionary * _Nullable error);
typedef void (^TGChatBlock)(NSDictionary * _Nullable chat, NSDictionary * _Nullable error);
typedef void (^TGHistoryBlock)(NSArray<NSDictionary *> * _Nullable messages, NSInteger totalCount, NSDictionary * _Nullable error);
typedef void (^TGMessageBlock)(NSDictionary * _Nullable message, NSDictionary * _Nullable error);
typedef void (^TGFileBlock)(NSString * _Nullable localPath, NSDictionary * _Nullable file);
typedef void (^TGStickerSectionsBlock)(NSArray<NSDictionary *> * _Nullable sections, NSDictionary * _Nullable error);

@class TGTDLibClient;

@protocol TGTDLibClientDelegate <NSObject>
@optional
- (void)tgClient:(TGTDLibClient *)client didChangeAuthorizationState:(NSDictionary *)state;
- (void)tgClient:(TGTDLibClient *)client didReceiveUpdate:(NSDictionary *)update;
- (void)tgClientDidBecomeReady:(TGTDLibClient *)client;
- (void)tgClient:(TGTDLibClient *)client didFailWithError:(NSDictionary *)error;
@end

@interface TGTDLibClient : NSObject

@property (nonatomic, weak, nullable) id<TGTDLibClientDelegate> delegate;
@property (nonatomic, readonly, nullable) NSDictionary *authorizationState;
@property (nonatomic, readonly) BOOL isReady;

- (void)start;
- (void)shutdown;

- (BOOL)hasCredentials;
- (void)applyCredentialsIfNeeded;

- (void)sendPhoneNumber:(NSString *)phoneNumber completion:(nullable TGResponseBlock)completion;
- (void)sendAuthenticationCode:(NSString *)code completion:(nullable TGResponseBlock)completion;
- (void)sendPassword:(NSString *)password completion:(nullable TGResponseBlock)completion;
- (void)registerFirstName:(NSString *)firstName lastName:(NSString *)lastName completion:(nullable TGResponseBlock)completion;
- (void)acceptTermsOfServiceWithId:(NSString *)termsOfServiceId completion:(nullable TGResponseBlock)completion;
- (void)logOut;

- (void)loadChatListWithCompletion:(nullable TGChatListBlock)completion;
- (void)loadMoreChatsWithCompletion:(nullable void (^)(NSDictionary * _Nullable error))completion;
- (void)loadChat:(int64_t)chatId completion:(nullable TGChatBlock)completion;
- (void)loadHistoryForChat:(int64_t)chatId
             fromMessageId:(int64_t)fromMessageId
                     limit:(NSInteger)limit
                completion:(nullable TGHistoryBlock)completion;
- (void)sendText:(NSString *)text toChat:(int64_t)chatId completion:(nullable TGMessageBlock)completion;
/// Sends text; when `replyToMessageId` is non-zero the message quotes it.
- (void)sendText:(NSString *)text
          toChat:(int64_t)chatId
replyToMessageId:(int64_t)replyToMessageId
      completion:(nullable TGMessageBlock)completion;
/// Edits a text message that belongs to the current user.
- (void)editMessageText:(NSString *)text
                 inChat:(int64_t)chatId
              messageId:(int64_t)messageId
             completion:(nullable TGMessageBlock)completion;
/// Deletes messages; `revoke` also removes them for other participants.
- (void)deleteMessages:(NSArray<NSNumber *> *)messageIds
                inChat:(int64_t)chatId
                revoke:(BOOL)revoke
            completion:(nullable void (^)(NSDictionary * _Nullable error))completion;
/// Forwards messages between chats (keeps the "Przekazano od" header).
- (void)forwardMessages:(NSArray<NSNumber *> *)messageIds
               fromChat:(int64_t)fromChatId
                 toChat:(int64_t)toChatId
             completion:(nullable void (^)(NSArray<NSDictionary *> * _Nullable messages, NSDictionary * _Nullable error))completion;
/// Human-readable name of a `MessageOrigin` (used by forwarded headers).
- (NSString *)displayNameForMessageOrigin:(nullable NSDictionary *)origin;
- (void)sendPhotoAtPath:(NSString *)path
                 toChat:(int64_t)chatId
                caption:(nullable NSString *)caption
             completion:(nullable TGMessageBlock)completion;
/// Loads sticker picker sections: "Ulubione", "Ostatnie" and installed packs.
/// Each section is a dictionary with "title" (NSString) and "stickers" (array
/// of TDLib `sticker` objects).
- (void)loadStickerSectionsWithCompletion:(nullable TGStickerSectionsBlock)completion;
- (void)sendSticker:(NSDictionary *)sticker
              toChat:(int64_t)chatId
          completion:(nullable TGMessageBlock)completion;
- (void)viewMessages:(NSArray<NSNumber *> *)messageIds inChat:(int64_t)chatId;
- (void)openChat:(int64_t)chatId;
- (void)closeChat:(int64_t)chatId;
/// Re-sends failed messages (TDLib replaces the old message id on success).
- (void)resendMessages:(NSArray<NSNumber *> *)messageIds inChat:(int64_t)chatId completion:(void(^)(NSDictionary *error))completion;
- (void)closeChat:(int64_t)chatId;

- (void)downloadFileWithId:(int32_t)fileId
                  priority:(int32_t)priority
                completion:(nullable TGFileBlock)completion;
- (nullable NSString *)localPathForFileId:(int32_t)fileId;
- (nullable NSDictionary *)fileWithId:(int32_t)fileId;

- (nullable NSDictionary *)chatWithId:(int64_t)chatId;
- (nullable NSDictionary *)userWithId:(int64_t)userId;
- (NSString *)displayNameForSender:(NSDictionary *)sender;
- (NSString *)displayNameForUserId:(int64_t)userId;
- (BOOL)chatIsGroup:(int64_t)chatId;

- (void)sendRequest:(NSDictionary *)request;
- (void)sendRequest:(NSDictionary *)request completion:(nullable TGResponseBlock)completion;

@end

NS_ASSUME_NONNULL_END
