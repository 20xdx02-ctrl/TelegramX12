#import "TGTDLibClient.h"
#import "TGConfig.h"
#import "TGModels.h"
#import "TGTheme.h"

#import <UIKit/UIKit.h>

#import "td_json_client.h"

static void TGXLogLine(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[TGX] %@", message);

    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (documents.length == 0) {
        return;
    }
    NSString *path = [documents stringByAppendingPathComponent:@"app.log"];
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    @synchronized (path) {
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (handle == nil) {
            [data writeToFile:path atomically:YES];
        } else {
            @try {
                [handle seekToEndOfFile];
                [handle writeData:data];
            } @catch (__unused NSException *exception) {
            }
            [handle closeFile];
        }
    }
}

@interface TGTDLibClient ()

@property (nonatomic, readwrite, nullable) NSDictionary *authorizationState;
@property (nonatomic, readwrite) BOOL isReady;
@property (nonatomic, strong) NSMutableDictionary<NSString *, TGResponseBlock> *completions;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *chatCache;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *userCache;
@property (nonatomic) int64_t selfUserId;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *fileCache;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *localPathByFileId;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray *> *fileCompletions;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *requestedUsers;
@property (nonatomic, strong) dispatch_queue_t receiveQueue;
@property (nonatomic) int clientId;
@property (nonatomic) BOOL started;
@property (atomic) BOOL running;
@property (nonatomic) BOOL tdlibParametersSent;

@end

@implementation TGTDLibClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _completions = [NSMutableDictionary dictionary];
        _chatCache = [NSMutableDictionary dictionary];
        _userCache = [NSMutableDictionary dictionary];
        _fileCache = [NSMutableDictionary dictionary];
        _localPathByFileId = [NSMutableDictionary dictionary];
        _fileCompletions = [NSMutableDictionary dictionary];
        _requestedUsers = [NSMutableSet set];
    }
    return self;
}

- (BOOL)hasCachedSession {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *databaseDirectory = [paths.firstObject stringByAppendingPathComponent:@"TelegramX12/tdlib-db"];
    NSArray<NSString *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:databaseDirectory error:NULL];
    return contents.count > 0;
}

- (void)start {
    if (self.started) {
        return;
    }
    self.started = YES;
    TGXLogLine(@"start: hasCredentials=%d", [TGConfig hasCredentials]);

    self.clientId = td_create_client_id();
    TGXLogLine(@"td_create_client_id -> %d", self.clientId);

    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *tdlog = [documents stringByAppendingPathComponent:@"tdlib.log"];
    NSString *setLogRequest = [NSString stringWithFormat:@"{\"@type\":\"setLogStream\",\"log_stream\":{\"@type\":\"logStreamFile\",\"path\":\"%@\",\"max_file_size\":20971520}}", tdlog];
    td_send(self.clientId, setLogRequest.UTF8String);
    td_send(self.clientId, "{\"@type\":\"setLogVerbosityLevel\",\"new_verbosity_level\":5}");

    self.receiveQueue = dispatch_queue_create("com.telegramx12.tdlib.receive", DISPATCH_QUEUE_SERIAL);
    self.running = YES;

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.receiveQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        while (strongSelf.running) {
            const char *raw = td_receive(0.5);
            if (raw == NULL) {
                continue;
            }
            NSString *string = [NSString stringWithUTF8String:raw];
            if (string.length == 0) {
                continue;
            }
            static NSInteger receiveLogCount = 0;
            receiveLogCount++;
            if (receiveLogCount <= 60) {
                NSString *preview = string.length > 800 ? [string substringToIndex:800] : string;
                TGXLogLine(@"recv #%ld: %@", (long)receiveLogCount, preview);
            }
            NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
            id object = nil;
            if (data != nil) {
                object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            }
            if (![object isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary *dictionary = (NSDictionary *)object;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf handleObject:dictionary];
            });
        }
    });
}

- (void)shutdown {
    if (!self.started) {
        return;
    }
    self.running = NO;
    [self sendRequest:@{@"@type": @"close"}];
}

- (BOOL)hasCredentials {
    return [TGConfig hasCredentials];
}

- (void)applyCredentialsIfNeeded {
    if (self.authorizationState == nil || self.tdlibParametersSent) {
        return;
    }
    if (![[TGStringValue(self.authorizationState[@"@type"]) lowercaseString] isEqualToString:@"authorizationstatewaittdlibparameters"]) {
        return;
    }
    if ([TGConfig hasCredentials]) {
        [self sendTdlibParameters];
    }
}

#pragma mark - Receive handling

- (void)handleObject:(NSDictionary *)dictionary {
    NSString *extra = dictionary[@"@extra"];
    if ([extra isKindOfClass:[NSString class]]) {
        TGResponseBlock completion = self.completions[extra];
        if (completion != nil) {
            [self.completions removeObjectForKey:extra];
            completion(dictionary);
            return;
        }
    }

    NSString *type = TGStringValue(dictionary[@"@type"]);

    if ([type isEqualToString:@"updateAuthorizationState"]) {
        NSDictionary *state = dictionary[@"authorization_state"];
        if ([state isKindOfClass:[NSDictionary class]]) {
            [self handleAuthorizationState:state];
        }
        return;
    }

    if ([type isEqualToString:@"updateNewChat"]) {
        NSDictionary *chat = dictionary[@"chat"];
        if ([chat isKindOfClass:[NSDictionary class]]) {
            int64_t chatId = TGInt64Value(chat[@"id"]);
            if (chatId != 0) {
                self.chatCache[@(chatId)] = chat;
            }
        }
        [self.delegate tgClient:self didReceiveUpdate:dictionary];
        return;
    }

    if ([type isEqualToString:@"updateUser"]) {
        NSDictionary *user = dictionary[@"user"];
        if ([user isKindOfClass:[NSDictionary class]]) {
            int64_t userId = TGInt64Value(user[@"id"]);
            if (userId != 0) {
                self.userCache[@(userId)] = user;
            }
        }
        [self.delegate tgClient:self didReceiveUpdate:dictionary];
        return;
    }

    if ([type isEqualToString:@"updateChatTitle"]) {
        int64_t chatId = TGInt64Value(dictionary[@"chat_id"]);
        NSDictionary *cached = self.chatCache[@(chatId)];
        NSString *title = TGStringValue(dictionary[@"title"]);
        if (cached != nil && title.length > 0) {
            NSMutableDictionary *updated = [cached mutableCopy];
            updated[@"title"] = title;
            self.chatCache[@(chatId)] = updated;
        }
        [self.delegate tgClient:self didReceiveUpdate:dictionary];
        return;
    }

    if ([type isEqualToString:@"updateChatReadInbox"]) {
        int64_t chatId = TGInt64Value(dictionary[@"chat_id"]);
        NSDictionary *cached = self.chatCache[@(chatId)];
        if (cached != nil) {
            NSMutableDictionary *updated = [cached mutableCopy];
            if (dictionary[@"last_read_inbox_message_id"] != nil) {
                updated[@"last_read_inbox_message_id"] = dictionary[@"last_read_inbox_message_id"];
            }
            if (dictionary[@"unread_count"] != nil) {
                updated[@"unread_count"] = dictionary[@"unread_count"];
            }
            self.chatCache[@(chatId)] = updated;
        }
        [self.delegate tgClient:self didReceiveUpdate:dictionary];
        return;
    }

    if ([type isEqualToString:@"updateFile"]) {
        NSDictionary *file = dictionary[@"file"];
        if ([file isKindOfClass:[NSDictionary class]]) {
            [self handleFileUpdate:file];
        }
        [self.delegate tgClient:self didReceiveUpdate:dictionary];
        return;
    }

    if ([type isEqualToString:@"error"]) {
        [self.delegate tgClient:self didFailWithError:dictionary];
        return;
    }

    if ([type hasPrefix:@"update"]) {
        [self.delegate tgClient:self didReceiveUpdate:dictionary];
    }
}

- (void)handleAuthorizationState:(NSDictionary *)state {
    self.authorizationState = state;
    NSString *type = TGStringValue(state[@"@type"]);
    TGXLogLine(@"authorization state: %@", type);
    self.isReady = [type isEqualToString:@"authorizationStateReady"];

    if ([type isEqualToString:@"authorizationStateWaitTdlibParameters"]) {
        if ([TGConfig hasCredentials]) {
            [self sendTdlibParameters];
        }
    }

    if ([self.delegate respondsToSelector:@selector(tgClient:didChangeAuthorizationState:)]) {
        [self.delegate tgClient:self didChangeAuthorizationState:state];
    }
    if (self.isReady && [self.delegate respondsToSelector:@selector(tgClientDidBecomeReady:)]) {
        [self.delegate tgClientDidBecomeReady:self];
    }
}

- (void)sendTdlibParameters {
    if (self.tdlibParametersSent) {
        return;
    }
    int apiId = [TGConfig apiId];
    NSString *apiHash = [TGConfig apiHash];
    if (apiId <= 0 || apiHash.length == 0) {
        return;
    }
    self.tdlibParametersSent = YES;
    TGXLogLine(@"sending TDLib parameters (api_id=%d)", apiId);

    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *baseDirectory = [paths.firstObject stringByAppendingPathComponent:@"TelegramX12"];
    NSString *databaseDirectory = [baseDirectory stringByAppendingPathComponent:@"tdlib-db"];
    NSString *filesDirectory = [baseDirectory stringByAppendingPathComponent:@"tdlib-files"];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:databaseDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    [fileManager createDirectoryAtPath:filesDirectory withIntermediateDirectories:YES attributes:nil error:NULL];

    NSString *language = [[NSLocale preferredLanguages] firstObject];
    if (language.length == 0) {
        language = @"en";
    }
    language = [[language componentsSeparatedByString:@"-"] firstObject];

    NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if (appVersion.length == 0) {
        appVersion = @"1.0";
    }

    NSDictionary *request = @{
        @"@type": @"setTdlibParameters",
        @"use_test_dc": @NO,
        @"database_directory": databaseDirectory,
        @"files_directory": filesDirectory,
        @"database_encryption_key": @"",
        @"use_file_database": @YES,
        @"use_chat_info_database": @YES,
        @"use_message_database": @YES,
        @"use_secret_chats": @NO,
        @"api_id": @(apiId),
        @"api_hash": apiHash,
        @"system_language_code": language,
        @"device_model": [[UIDevice currentDevice] model],
        @"system_version": [[UIDevice currentDevice] systemVersion],
        @"application_version": appVersion
    };

    __weak typeof(self) weakSelf = self;
    [self sendRequest:request completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"error"]) {
            if ([weakSelf.delegate respondsToSelector:@selector(tgClient:didFailWithError:)]) {
                [weakSelf.delegate tgClient:weakSelf didFailWithError:response];
            }
        }
    }];
}

#pragma mark - Requests

- (void)sendRequest:(NSDictionary *)request {
    [self sendRequest:request completion:nil];
}

- (void)sendRequest:(NSDictionary *)request completion:(TGResponseBlock)completion {
    NSMutableDictionary *payload = [request mutableCopy];
    NSString *extra = nil;
    if (completion != nil) {
        extra = [[NSUUID UUID] UUIDString];
        payload[@"@extra"] = extra;
        self.completions[extra] = [completion copy];
    }

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (data == nil) {
        if (completion != nil) {
            [self.completions removeObjectForKey:extra];
            completion(@{
                @"@type": @"error",
                @"code": @400,
                @"message": error.localizedDescription ?: @"Nie udało się zakodować żądania."
            });
        }
        return;
    }

    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if ([TGStringValue(request[@"@type"]) isEqualToString:@"setTdlibParameters"]) {
        NSMutableDictionary *redacted = [payload mutableCopy];
        redacted[@"api_hash"] = @"***";
        NSData *redactedData = [NSJSONSerialization dataWithJSONObject:redacted options:0 error:NULL];
        TGXLogLine(@"send: %@", [[NSString alloc] initWithData:redactedData encoding:NSUTF8StringEncoding]);
    }
    if (json.length == 0) {
        if (completion != nil) {
            [self.completions removeObjectForKey:extra];
            completion(@{@"@type": @"error", @"code": @400, @"message": @"Puste żądanie."});
        }
        return;
    }

    td_send(self.clientId, json.UTF8String);
}

#pragma mark - Authorization

- (void)sendPhoneNumber:(NSString *)phoneNumber completion:(TGResponseBlock)completion {
    NSDictionary *settings = @{
        @"@type": @"phoneNumberAuthenticationSettings",
        @"allow_flash_call": @NO,
        @"allow_sms_retriever_api": @NO,
        @"is_current_phone_number": @NO,
        @"authentication_tokens": @[]
    };
    NSDictionary *request = @{
        @"@type": @"setAuthenticationPhoneNumber",
        @"phone_number": phoneNumber,
        @"settings": settings
    };
    [self sendRequest:request completion:completion];
}

- (void)sendAuthenticationCode:(NSString *)code completion:(TGResponseBlock)completion {
    [self sendRequest:@{@"@type": @"checkAuthenticationCode", @"code": code} completion:completion];
}

- (void)sendPassword:(NSString *)password completion:(TGResponseBlock)completion {
    [self sendRequest:@{@"@type": @"checkAuthenticationPassword", @"password": password} completion:completion];
}

- (void)registerFirstName:(NSString *)firstName lastName:(NSString *)lastName completion:(TGResponseBlock)completion {
    NSDictionary *request = @{
        @"@type": @"registerUser",
        @"first_name": firstName ?: @"",
        @"last_name": lastName ?: @"",
        @"disable_notification": @NO
    };
    [self sendRequest:request completion:completion];
}

- (void)acceptTermsOfServiceWithId:(NSString *)termsOfServiceId completion:(TGResponseBlock)completion {
    NSDictionary *request = @{
        @"@type": @"acceptTermsOfService",
        @"terms_of_service_id": termsOfServiceId ?: @""
    };
    [self sendRequest:request completion:completion];
}

- (void)logOut {
    [self sendRequest:@{@"@type": @"logOut"}];
}

#pragma mark - Chats and messages

- (void)loadChatListWithCompletion:(TGChatListBlock)completion {
    NSDictionary *request = @{
        @"@type": @"getChats",
        @"chat_list": @{@"@type": @"chatListMain"},
        @"limit": @100
    };
    __weak typeof(self) weakSelf = self;
    [self sendRequest:request completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"error"]) {
            if (completion != nil) {
                completion(nil, response);
            }
            return;
        }
        NSArray *rawIds = response[@"chat_ids"];
        NSMutableArray<NSNumber *> *chatIds = [NSMutableArray array];
        if ([rawIds isKindOfClass:[NSArray class]]) {
            for (id rawId in rawIds) {
                int64_t chatId = TGInt64Value(rawId);
                if (chatId != 0) {
                    [chatIds addObject:@(chatId)];
                }
            }
        }
        if (completion != nil) {
            completion(chatIds, nil);
        }
        [weakSelf loadMoreChatsWithCompletion:nil];
    }];
}

- (void)loadMoreChatsWithCompletion:(void (^)(NSDictionary * _Nullable))completion {
    NSDictionary *request = @{
        @"@type": @"loadChats",
        @"chat_list": @{@"@type": @"chatListMain"},
        @"limit": @100
    };
    [self sendRequest:request completion:^(NSDictionary *response) {
        NSString *type = TGStringValue(response[@"@type"]);
        if ([type isEqualToString:@"error"]) {
            NSInteger code = [response[@"code"] integerValue];
            if (completion != nil) {
                completion(code == 404 ? nil : response);
            }
            return;
        }
        if (completion != nil) {
            completion(nil);
        }
    }];
}

- (void)loadChat:(int64_t)chatId completion:(TGChatBlock)completion {
    NSDictionary *request = @{@"@type": @"getChat", @"chat_id": @(chatId)};
    __weak typeof(self) weakSelf = self;
    [self sendRequest:request completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"error"]) {
            if (completion != nil) {
                completion(nil, response);
            }
            return;
        }
        int64_t identifier = TGInt64Value(response[@"id"]);
        if (identifier != 0) {
            weakSelf.chatCache[@(identifier)] = response;
        }
        if (completion != nil) {
            completion(response, nil);
        }
    }];
}

- (void)loadHistoryForChat:(int64_t)chatId
             fromMessageId:(int64_t)fromMessageId
                     limit:(NSInteger)limit
                completion:(TGHistoryBlock)completion {
    NSDictionary *request = @{
        @"@type": @"getChatHistory",
        @"chat_id": @(chatId),
        @"from_message_id": @(fromMessageId),
        @"limit": @(limit),
        @"offset": @0,
        @"only_local": @NO
    };
    [self sendRequest:request completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"error"]) {
            if (completion != nil) {
                completion(nil, 0, response);
            }
            return;
        }
        NSArray *messages = response[@"messages"];
        NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
        if ([messages isKindOfClass:[NSArray class]]) {
            for (id message in messages) {
                if ([message isKindOfClass:[NSDictionary class]]) {
                    [result addObject:(NSDictionary *)message];
                }
            }
        }
        NSInteger totalCount = (NSInteger)TGInt32Value(response[@"total_count"]);
        if (completion != nil) {
            completion(result, totalCount, nil);
        }
    }];
}

- (void)sendText:(NSString *)text toChat:(int64_t)chatId completion:(TGMessageBlock)completion {
    [self sendText:text toChat:chatId replyToMessageId:0 completion:completion];
}

- (void)sendText:(NSString *)text
          toChat:(int64_t)chatId
replyToMessageId:(int64_t)replyToMessageId
      completion:(TGMessageBlock)completion {
    NSDictionary *content = @{
        @"@type": @"inputMessageText",
        @"text": @{
            @"@type": @"formattedText",
            @"text": text,
            @"entities": @[]
        },
        @"clear_draft": @YES
    };
    NSMutableDictionary *request = [@{
        @"@type": @"sendMessage",
        @"chat_id": @(chatId),
        @"input_message_content": content
    } mutableCopy];
    if (replyToMessageId != 0) {
        request[@"reply_to"] = @{
            @"@type": @"inputMessageReplyToMessage",
            @"message_id": @(replyToMessageId)
        };
    }
    [self sendRequest:request completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"message"]) {
            if (completion != nil) {
                completion(response, nil);
            }
            return;
        }
        if (completion != nil) {
            completion(nil, response);
        }
    }];
}

- (void)editMessageText:(NSString *)text
                 inChat:(int64_t)chatId
              messageId:(int64_t)messageId
             completion:(TGMessageBlock)completion {
    NSDictionary *content = @{
        @"@type": @"inputMessageText",
        @"text": @{
            @"@type": @"formattedText",
            @"text": text ?: @"",
            @"entities": @[]
        },
        @"clear_draft": @NO
    };
    NSDictionary *request = @{
        @"@type": @"editMessageText",
        @"chat_id": @(chatId),
        @"message_id": @(messageId),
        @"input_message_content": content
    };
    [self sendRequest:request completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"message"]) {
            if (completion != nil) {
                completion(response, nil);
            }
            return;
        }
        if (completion != nil) {
            completion(nil, response);
        }
    }];
}

- (void)deleteMessages:(NSArray<NSNumber *> *)messageIds
                inChat:(int64_t)chatId
                revoke:(BOOL)revoke
            completion:(void (^)(NSDictionary *))completion {
    if (messageIds.count == 0) {
        if (completion != nil) {
            completion(nil);
        }
        return;
    }
    NSDictionary *request = @{
        @"@type": @"deleteMessages",
        @"chat_id": @(chatId),
        @"message_ids": messageIds,
        @"revoke": @(revoke)
    };
    [self sendRequest:request completion:^(NSDictionary *response) {
        if (completion == nil) {
            return;
        }
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"ok"]) {
            completion(nil);
        } else {
            completion(response);
        }
    }];
}

- (void)forwardMessages:(NSArray<NSNumber *> *)messageIds
               fromChat:(int64_t)fromChatId
                 toChat:(int64_t)toChatId
             completion:(void (^)(NSArray<NSDictionary *> *, NSDictionary *))completion {
    if (messageIds.count == 0) {
        if (completion != nil) {
            completion(nil, @{@"@type": @"error", @"message": @"Brak wiadomości do przekazania."});
        }
        return;
    }
    NSDictionary *request = @{
        @"@type": @"forwardMessages",
        @"chat_id": @(toChatId),
        @"from_chat_id": @(fromChatId),
        @"message_ids": messageIds,
        @"send_copy": @NO,
        @"remove_caption": @NO
    };
    [self sendRequest:request completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"messages"]) {
            NSArray *rawMessages = response[@"messages"];
            NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
            if ([rawMessages isKindOfClass:[NSArray class]]) {
                for (id message in rawMessages) {
                    if ([message isKindOfClass:[NSDictionary class]]) {
                        [result addObject:(NSDictionary *)message];
                    }
                }
            }
            if (completion != nil) {
                completion(result, nil);
            }
            return;
        }
        if (completion != nil) {
            completion(nil, response);
        }
    }];
}

- (void)sendPhotoAtPath:(NSString *)path
                 toChat:(int64_t)chatId
                caption:(nullable NSString *)caption
             completion:(nullable TGMessageBlock)completion {
    if (path.length == 0) {
        if (completion != nil) {
            completion(nil, @{@"@type": @"error", @"message": @"Brak ścieżki pliku"});
        }
        return;
    }
    NSDictionary *content = @{
        @"@type": @"inputMessagePhoto",
        // TDLib 1.8 wraps the file in an inputPhoto struct: a bare
        // inputFileLocal is ignored ("InputFile is not specified").
        @"photo": @{
            @"@type": @"inputPhoto",
            @"photo": @{
                @"@type": @"inputFileLocal",
                @"path": path
            },
            @"added_sticker_file_ids": @[]
        },
        @"caption": @{
            @"@type": @"formattedText",
            @"text": caption ?: @"",
            @"entities": @[]
        }
    };
    NSDictionary *request = @{
        @"@type": @"sendMessage",
        @"chat_id": @(chatId),
        @"input_message_content": content
    };
    [self sendRequest:request completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"message"]) {
            if (completion != nil) {
                completion(response, nil);
            }
            return;
        }
        if (completion != nil) {
            completion(nil, response);
        }
    }];
}

static NSArray<NSDictionary *> *TGStickerObjects(id value) {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    if ([value isKindOfClass:[NSArray class]]) {
        for (id object in value) {
            if ([object isKindOfClass:[NSDictionary class]]) {
                [result addObject:object];
            }
        }
    }
    return result;
}

static int32_t TGStickerFileId(NSDictionary *sticker) {
    return TGInt32Value(sticker[@"sticker"][@"id"]);
}

- (void)loadStickerSectionsWithCompletion:(TGStickerSectionsBlock)completion {
    __weak typeof(self) weakSelf = self;
    [self sendRequest:@{@"@type": @"getFavoriteStickers"} completion:^(NSDictionary *favoriteResponse) {
        NSMutableArray<NSDictionary *> *sections = [NSMutableArray array];
        NSArray<NSDictionary *> *favorites = TGStickerObjects(favoriteResponse[@"stickers"]);
        if (favorites.count > 0) {
            [sections addObject:@{@"title": @"Ulubione", @"stickers": favorites}];
        }

        [weakSelf sendRequest:@{@"@type": @"getRecentStickers", @"is_attached": @NO} completion:^(NSDictionary *recentResponse) {
            NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
            for (NSDictionary *sticker in favorites) {
                int32_t fileId = TGStickerFileId(sticker);
                if (fileId > 0) {
                    [seen addObject:@(fileId)];
                }
            }
            NSMutableArray<NSDictionary *> *recent = [NSMutableArray array];
            for (NSDictionary *sticker in TGStickerObjects(recentResponse[@"stickers"])) {
                int32_t fileId = TGStickerFileId(sticker);
                if (fileId > 0 && [seen containsObject:@(fileId)]) {
                    continue;
                }
                if (fileId > 0) {
                    [seen addObject:@(fileId)];
                }
                [recent addObject:sticker];
            }
            if (recent.count > 0) {
                [sections addObject:@{@"title": @"Ostatnie", @"stickers": recent}];
            }

            [weakSelf sendRequest:@{@"@type": @"getInstalledStickerSets", @"is_masks": @NO} completion:^(NSDictionary *setsResponse) {
                NSArray *setIds = setsResponse[@"sticker_set_ids"];
                if (![setIds isKindOfClass:[NSArray class]] || setIds.count == 0) {
                    if (completion != nil) {
                        completion(sections, nil);
                    }
                    return;
                }

                // Bound the number of packs so opening the picker never fans
                // out into dozens of getStickerSet requests.
                NSUInteger limit = MIN(setIds.count, (NSUInteger)12);
                NSArray *packIds = [setIds subarrayWithRange:NSMakeRange(0, limit)];

                dispatch_group_t group = dispatch_group_create();
                NSMutableDictionary<NSNumber *, NSDictionary *> *packs = [NSMutableDictionary dictionary];
                for (NSUInteger index = 0; index < packIds.count; index++) {
                    NSNumber *packIndex = @(index);
                    dispatch_group_enter(group);
                    [weakSelf sendRequest:@{@"@type": @"getStickerSet", @"set_id": packIds[index]} completion:^(NSDictionary *setResponse) {
                        NSArray<NSDictionary *> *stickers = TGStickerObjects(setResponse[@"stickers"]);
                        if (stickers.count > 0) {
                            NSString *title = TGStringValue(setResponse[@"title"]);
                            packs[packIndex] = @{
                                @"title": title.length > 0 ? title : @"Stickery",
                                @"stickers": stickers
                            };
                        }
                        dispatch_group_leave(group);
                    }];
                }

                dispatch_group_notify(group, dispatch_get_main_queue(), ^{
                    for (NSUInteger index = 0; index < packIds.count; index++) {
                        NSDictionary *section = packs[@(index)];
                        if (section != nil) {
                            [sections addObject:section];
                        }
                    }
                    if (completion != nil) {
                        completion(sections, nil);
                    }
                });
            }];
        }];
    }];
}

- (void)sendSticker:(NSDictionary *)sticker
              toChat:(int64_t)chatId
          completion:(TGMessageBlock)completion {
    NSDictionary *file = sticker[@"sticker"];
    int32_t fileId = TGInt32Value(file[@"id"]);
    if (fileId <= 0 || chatId == 0) {
        if (completion != nil) {
            completion(nil, @{@"@type": @"error", @"message": @"Nieprawidłowy sticker."});
        }
        return;
    }

    NSDictionary *content = @{
        @"@type": @"inputMessageSticker",
        // TDLib 1.8 wraps the file in an inputSticker struct with width/height;
        // a bare inputFileId is ignored ("InputFile is not specified").
        @"sticker": @{
            @"@type": @"inputSticker",
            @"sticker": @{@"@type": @"inputFileId", @"id": @(fileId)},
            @"width": @(MAX(1, TGInt32Value(sticker[@"width"]))),
            @"height": @(MAX(1, TGInt32Value(sticker[@"height"])))
        },
        @"emoji": TGStringValue(sticker[@"emoji"]) ?: @""
    };
    [self sendRequest:@{@"@type": @"sendMessage", @"chat_id": @(chatId), @"input_message_content": content} completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"message"]) {
            if (completion != nil) {
                completion(response, nil);
            }
        } else if (completion != nil) {
            completion(nil, response);
        }
    }];
}

- (void)viewMessages:(NSArray<NSNumber *> *)messageIds inChat:(int64_t)chatId {
    if (messageIds.count == 0) {
        return;
    }
    NSDictionary *request = @{
        @"@type": @"viewMessages",
        @"chat_id": @(chatId),
        @"message_ids": messageIds,
        @"force_read": @YES
    };
    [self sendRequest:request];
}

- (void)openChat:(int64_t)chatId {
    [self sendRequest:@{@"@type": @"openChat", @"chat_id": @(chatId)}];
}

- (void)closeChat:(int64_t)chatId {
    [self sendRequest:@{@"@type": @"closeChat", @"chat_id": @(chatId)}];
}

- (void)updateChatCache:(NSNumber *)chatId key:(NSString *)key value:(id)value {
    NSDictionary *cached = self.chatCache[chatId];
    if (cached == nil || key.length == 0) {
        return;
    }
    NSMutableDictionary *updated = [cached mutableCopy];
    updated[key] = value ?: @{};
    self.chatCache[chatId] = updated;
}

- (void)searchChatMessages:(int64_t)chatId
                     query:(NSString *)query
                completion:(void (^)(NSArray<NSDictionary *> *, NSDictionary *))completion {
    if (query.length == 0) {
        if (completion != nil) {
            completion(@[], nil);
        }
        return;
    }
    NSDictionary *request = @{
        @"@type": @"searchChatMessages",
        @"chat_id": @(chatId),
        @"query": query,
        @"limit": @25
    };
    [self sendRequest:request completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"error"]) {
            if (completion != nil) {
                completion(nil, response);
            }
            return;
        }
        NSArray *messages = response[@"messages"];
        if (completion != nil) {
            completion([messages isKindOfClass:[NSArray class]] ? messages : @[], nil);
        }
    }];
}

- (void)setChatMuted:(int64_t)chatId muted:(BOOL)muted completion:(void (^)(NSDictionary *))completion {
    // Mute for a year; unmute falls back to the account defaults.
    NSDictionary *settings = muted
        ? @{@"@type": @"chatNotificationSettings",
            @"use_default_mute_for": @NO,
            @"mute_for": @31536000,
            @"use_default_disable_sound": @YES,
            @"use_default_show_preview": @YES,
            @"use_default_mute_stories": @YES,
            @"use_default_disable_sound_stories": @YES,
            @"use_default_hide_sender_name_stories": @YES,
            @"use_default_story_reaction_notifications": @YES}
        : @{@"@type": @"chatNotificationSettings",
            @"use_default_mute_for": @YES};
    NSDictionary *request = @{
        @"@type": @"setChatNotificationSettings",
        @"chat_id": @(chatId),
        @"notification_settings": settings
    };
    __weak typeof(self) weakSelf = self;
    [self sendRequest:request completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"error"]) {
            if (completion != nil) {
                completion(response);
            }
            return;
        }
        [weakSelf updateChatCache:@(chatId) key:@"notification_settings" value:settings];
        if (completion != nil) {
            completion(nil);
        }
    }];
}

- (void)resendMessages:(NSArray<NSNumber *> *)messageIds
                inChat:(int64_t)chatId
            completion:(void (^)(NSDictionary *))completion {
    NSDictionary *request = @{
        @"@type": @"resendMessages",
        @"chat_id": @(chatId),
        @"message_ids": messageIds ?: @[]
    };
    [self sendRequest:request completion:^(NSDictionary *response) {
        NSString *type = TGStringValue(response[@"@type"]);
        if (completion == nil) {
            return;
        }
        if ([type isEqualToString:@"messages"] || [type isEqualToString:@"ok"]) {
            completion(nil);
        } else {
            completion(response);
        }
    }];
}

#pragma mark - Caches

- (NSDictionary *)chatWithId:(int64_t)chatId {
    return self.chatCache[@(chatId)];
}

- (NSDictionary *)userWithId:(int64_t)userId {
    return self.userCache[@(userId)];
}

- (void)createPrivateChatWithUserId:(int64_t)userId completion:(void (^)(NSDictionary *, NSDictionary *))completion {
    NSDictionary *request = @{@"@type": @"createPrivateChat", @"user_id": @(userId), @"force": @NO};
    __weak typeof(self) weakSelf = self;
    [self sendRequest:request completion:^(NSDictionary *response) {
        NSString *type = TGStringValue(response[@"@type"]);
        if ([type isEqualToString:@"chat"]) {
            int64_t identifier = TGInt64Value(response[@"id"]);
            if (identifier != 0) {
                weakSelf.chatCache[@(identifier)] = response;
            }
            if (completion != nil) {
                completion(response, nil);
            }
            return;
        }
        if (completion != nil) {
            completion(nil, [type isEqualToString:@"error"] ? response : @{ @"@type": @"error", @"message": @"Nie udało się otworzyć czatu" });
        }
    }];
}

// Saved Messages is the private chat with our own account; TDLib exposes
// getMe — cache the result so the chat list can pin the special row.
- (int64_t)myUserId {
    if (self.selfUserId == 0) {
        __weak typeof(self) weakSelf = self;
        [self sendRequest:@{@"@type": @"getMe"} completion:^(NSDictionary *response) {
            if ([TGStringValue(response[@"@type"]) isEqualToString:@"user"]) {
                weakSelf.selfUserId = TGInt64Value(response[@"id"]);
            }
        }];
    }
    return self.selfUserId;
}

- (NSArray<NSDictionary *> *)cachedArchiveChatDictionaries {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDictionary *chat in self.chatCache.allValues) {
        if (![chat isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        for (NSDictionary *position in chat[@"positions"] ?: @[]) {
            NSString *type = TGStringValue(position[@"list"][@"@type"]);
            if ([type isEqualToString:@"chatListArchive"]) {
                [result addObject:chat];
                break;
            }
        }
    }
    return result;
}

- (void)loadArchiveChatListWithCompletion:(void (^)(NSArray<NSDictionary *> *, NSDictionary *))completion {
    NSDictionary *request = @{
        @"@type": @"getChats",
        @"chat_list": @{@"@type": @"chatListArchive"},
        @"limit": @100
    };
    __weak typeof(self) weakSelf = self;
    [self sendRequest:request completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"error"]) {
            if (completion != nil) {
                completion(nil, response);
            }
            return;
        }
        NSMutableArray<NSDictionary *> *chats = [NSMutableArray array];
        NSMutableArray<NSString *> *pendingIds = [NSMutableArray array];
        for (id rawId in response[@"chat_ids"] ?: @[]) {
            int64_t chatId = TGInt64Value(rawId);
            if (chatId != 0) {
                [pendingIds addObject:@(chatId).stringValue];
            }
        }
        if (pendingIds.count == 0) {
            if (completion != nil) {
                completion(chats, nil);
            }
            return;
        }
        __block NSInteger remaining = pendingIds.count;
        for (NSString *idString in pendingIds) {
            int64_t chatId = idString.longLongValue;
            [weakSelf loadChat:chatId completion:^(NSDictionary *chat, NSDictionary *chatError) {
                if (chat != nil) {
                    [chats addObject:chat];
                }
                remaining -= 1;
                if (remaining <= 0 && completion != nil) {
                    completion(chats, nil);
                }
            }];
        }
    }];
}

- (BOOL)chatIsGroup:(int64_t)chatId {
    NSDictionary *chat = self.chatCache[@(chatId)];
    NSDictionary *type = chat[@"type"];
    if (![type isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    NSString *typeName = TGStringValue(type[@"@type"]);
    return !([typeName isEqualToString:@"chatTypePrivate"] || [typeName isEqualToString:@"chatTypeSecret"]);
}

- (NSString *)displayNameForSender:(NSDictionary *)sender {
    if (![sender isKindOfClass:[NSDictionary class]]) {
        return @"Nieznany";
    }
    NSString *type = TGStringValue(sender[@"@type"]);
    if ([type isEqualToString:@"messageSenderUser"]) {
        return [self displayNameForUserId:TGInt64Value(sender[@"user_id"])];
    }
    if ([type isEqualToString:@"messageSenderChat"]) {
        int64_t chatId = TGInt64Value(sender[@"chat_id"]);
        NSDictionary *chat = self.chatCache[@(chatId)];
        NSString *title = TGStringValue(chat[@"title"]);
        return title.length > 0 ? title : @"Czat";
    }
    return @"Nieznany";
}

/// Resolves a `MessageOrigin` (forward header) to a display name.
- (NSString *)displayNameForMessageOrigin:(NSDictionary *)origin {
    if (![origin isKindOfClass:[NSDictionary class]]) {
        return @"";
    }
    NSString *type = TGStringValue(origin[@"@type"]);
    if ([type isEqualToString:@"messageOriginUser"]) {
        return [self displayNameForUserId:TGInt64Value(origin[@"sender_user_id"])];
    }
    if ([type isEqualToString:@"messageOriginHiddenUser"] ||
        [type isEqualToString:@"messageOriginMessageImport"]) {
        return TGStringValue(origin[@"sender_name"]);
    }
    if ([type isEqualToString:@"messageOriginChat"]) {
        int64_t chatId = TGInt64Value(origin[@"sender_chat_id"]);
        NSDictionary *chat = self.chatCache[@(chatId)];
        NSString *title = TGStringValue(chat[@"title"]);
        if (title.length == 0) {
            [self loadChat:chatId completion:nil];
        }
        return title.length > 0 ? title : @"czat";
    }
    if ([type isEqualToString:@"messageOriginChannel"]) {
        int64_t chatId = TGInt64Value(origin[@"chat_id"]);
        NSDictionary *chat = self.chatCache[@(chatId)];
        NSString *title = TGStringValue(chat[@"title"]);
        if (title.length == 0) {
            [self loadChat:chatId completion:nil];
        }
        return title.length > 0 ? title : @"kanał";
    }
    return @"";
}

- (NSString *)displayNameForUserId:(int64_t)userId {
    NSDictionary *user = self.userCache[@(userId)];
    if (user == nil) {
        [self requestUserIfNeeded:userId];
        return @"…";
    }
    NSString *firstName = TGStringValue(user[@"first_name"]);
    NSString *lastName = TGStringValue(user[@"last_name"]);
    if (firstName.length == 0 && lastName.length == 0) {
        NSString *username = TGStringValue(user[@"username"]);
        return username.length > 0 ? [@"@" stringByAppendingString:username] : @"Użytkownik";
    }
    if (firstName.length == 0) {
        return lastName;
    }
    if (lastName.length == 0) {
        return firstName;
    }
    return [NSString stringWithFormat:@"%@ %@", firstName, lastName];
}

- (void)requestUserIfNeeded:(int64_t)userId {
    if (userId == 0) {
        return;
    }
    NSNumber *key = @(userId);
    if ([self.requestedUsers containsObject:key]) {
        return;
    }
    [self.requestedUsers addObject:key];

    __weak typeof(self) weakSelf = self;
    [self sendRequest:@{@"@type": @"getUser", @"user_id": key} completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"error"]) {
            return;
        }
        int64_t identifier = TGInt64Value(response[@"id"]);
        if (identifier != 0) {
            weakSelf.userCache[@(identifier)] = response;
        }
        [weakSelf.requestedUsers removeObject:key];
    }];
}

#pragma mark - File Management

- (void)handleFileUpdate:(NSDictionary *)file {
    if (![file isKindOfClass:[NSDictionary class]]) {
        return;
    }
    int32_t fileId = TGInt32Value(file[@"id"]);
    if (fileId <= 0) {
        return;
    }
    self.fileCache[@(fileId)] = file;

    NSDictionary *local = file[@"local"];
    if (![local isKindOfClass:[NSDictionary class]]) {
        return;
    }

    BOOL completed = TGBoolValue(local[@"is_downloading_completed"]);
    NSString *path = TGStringValue(local[@"path"]);
    if (completed && path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        self.localPathByFileId[@(fileId)] = path;
        [self notifyFileCompletionsForId:fileId path:path file:file];
        return;
    }

    BOOL canDownload = TGBoolValue(local[@"can_be_downloaded"]);
    BOOL active = TGBoolValue(local[@"is_downloading_active"]);
    if (!completed && !canDownload && !active) {
        // Download failed or was canceled
        [self notifyFileCompletionsForId:fileId path:nil file:file];
    }
}

- (void)notifyFileCompletionsForId:(int32_t)fileId path:(nullable NSString *)path file:(nullable NSDictionary *)file {
    NSArray<TGFileBlock> *callbacks = nil;
    @synchronized (self.fileCompletions) {
        callbacks = [self.fileCompletions[@(fileId)] copy];
        [self.fileCompletions removeObjectForKey:@(fileId)];
    }
    if (callbacks.count == 0) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        for (TGFileBlock block in callbacks) {
            block(path, file);
        }
    });
}

- (void)downloadFileWithId:(int32_t)fileId
                  priority:(int32_t)priority
                completion:(nullable TGFileBlock)completion {
    if (fileId <= 0) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil);
            });
        }
        return;
    }

    NSString *cachedPath = self.localPathByFileId[@(fileId)];
    if (cachedPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:cachedPath]) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cachedPath, self.fileCache[@(fileId)]);
            });
        }
        return;
    }

    BOOL shouldStart = NO;
    @synchronized (self.fileCompletions) {
        NSMutableArray *list = self.fileCompletions[@(fileId)];
        if (list == nil) {
            list = [NSMutableArray array];
            self.fileCompletions[@(fileId)] = list;
            shouldStart = YES;
        }
        if (completion) {
            [list addObject:[completion copy]];
        }
    }

    if (!shouldStart) {
        return;
    }

    NSDictionary *request = @{
        @"@type": @"downloadFile",
        @"file_id": @(fileId),
        @"priority": @(priority > 0 ? priority : 16),
        @"offset": @0,
        @"limit": @0,
        @"synchronous": @NO
    };

    __weak typeof(self) weakSelf = self;
    [self sendRequest:request completion:^(NSDictionary *response) {
        if ([TGStringValue(response[@"@type"]) isEqualToString:@"file"]) {
            [weakSelf handleFileUpdate:response];
        } else if ([TGStringValue(response[@"@type"]) isEqualToString:@"error"]) {
            [weakSelf notifyFileCompletionsForId:fileId path:nil file:response];
        }
    }];
}

- (nullable NSString *)localPathForFileId:(int32_t)fileId {
    if (fileId <= 0) {
        return nil;
    }
    NSString *path = self.localPathByFileId[@(fileId)];
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return path;
    }
    NSDictionary *file = self.fileCache[@(fileId)];
    NSDictionary *local = file[@"local"];
    if ([local isKindOfClass:[NSDictionary class]] && TGBoolValue(local[@"is_downloading_completed"])) {
        NSString *localPath = TGStringValue(local[@"path"]);
        if (localPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
            self.localPathByFileId[@(fileId)] = localPath;
            return localPath;
        }
    }
    return nil;
}

- (nullable NSDictionary *)fileWithId:(int32_t)fileId {
    return fileId > 0 ? self.fileCache[@(fileId)] : nil;
}

- (void)toggleReaction:(NSString *)emoji
             onMessage:(int64_t)messageId
                inChat:(int64_t)chatId
            completion:(nullable TGResponseBlock)completion {
    NSDictionary *reactionType = @{@"@type": @"reactionTypeEmoji", @"emoji": emoji};
    // TDLib addMessageReaction; if the reaction is already set TDLib auto-removes it.
    [self sendRequest:@{
        @"@type": @"addMessageReaction",
        @"chat_id": @(chatId),
        @"message_id": @(messageId),
        @"reaction_type": reactionType,
        @"is_big": @NO,
        @"update_recent_reactions": @YES
    } completion:^(NSDictionary *response) {
        // On error try removeMessageReaction (toggle)
        NSString *respType = response[@"@type"];
        if (respType != nil && [respType isEqualToString:@"error"]) {
            [self sendRequest:@{
                @"@type": @"removeMessageReaction",
                @"chat_id": @(chatId),
                @"message_id": @(messageId),
                @"reaction_type": reactionType
            } completion:completion];
        } else if (completion != nil) {
            completion(response);
        }
    }];
}

@end