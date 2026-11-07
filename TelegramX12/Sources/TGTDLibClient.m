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
        _requestedUsers = [NSMutableSet set];
    }
    return self;
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
    NSDictionary *content = @{
        @"@type": @"inputMessageText",
        @"text": @{
            @"@type": @"formattedText",
            @"text": text,
            @"entities": @[]
        },
        @"clear_draft": @YES
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

#pragma mark - Caches

- (NSDictionary *)chatWithId:(int64_t)chatId {
    return self.chatCache[@(chatId)];
}

- (NSDictionary *)userWithId:(int64_t)userId {
    return self.userCache[@(userId)];
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

@end
