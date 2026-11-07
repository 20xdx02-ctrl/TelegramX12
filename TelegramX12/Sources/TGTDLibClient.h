#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TGResponseBlock)(NSDictionary *response);
typedef void (^TGChatListBlock)(NSArray<NSNumber *> * _Nullable chatIds, NSDictionary * _Nullable error);
typedef void (^TGChatBlock)(NSDictionary * _Nullable chat, NSDictionary * _Nullable error);
typedef void (^TGHistoryBlock)(NSArray<NSDictionary *> * _Nullable messages, NSInteger totalCount, NSDictionary * _Nullable error);
typedef void (^TGMessageBlock)(NSDictionary * _Nullable message, NSDictionary * _Nullable error);

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
- (void)viewMessages:(NSArray<NSNumber *> *)messageIds inChat:(int64_t)chatId;
- (void)openChat:(int64_t)chatId;
- (void)closeChat:(int64_t)chatId;

- (nullable NSDictionary *)chatWithId:(int64_t)chatId;
- (nullable NSDictionary *)userWithId:(int64_t)userId;
- (NSString *)displayNameForSender:(NSDictionary *)sender;
- (NSString *)displayNameForUserId:(int64_t)userId;
- (BOOL)chatIsGroup:(int64_t)chatId;

- (void)sendRequest:(NSDictionary *)request;
- (void)sendRequest:(NSDictionary *)request completion:(nullable TGResponseBlock)completion;

@end

NS_ASSUME_NONNULL_END
