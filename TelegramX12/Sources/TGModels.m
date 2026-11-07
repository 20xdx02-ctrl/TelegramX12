#import "TGModels.h"

int64_t TGInt64Value(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value longLongValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value longLongValue];
    }
    return 0;
}

int32_t TGInt32Value(id value) {
    return (int32_t)TGInt64Value(value);
}

BOOL TGBoolValue(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value boolValue];
    }
    return NO;
}

NSString *TGStringValue(id value) {
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
}

static NSString *TGCaptionFromContent(NSDictionary *content) {
    id caption = content[@"caption"];
    if ([caption isKindOfClass:[NSDictionary class]]) {
        return TGStringValue(caption[@"text"]);
    }
    return @"";
}

static NSString *TGPrimaryTextFromContent(NSDictionary *content) {
    id text = content[@"text"];
    if ([text isKindOfClass:[NSDictionary class]]) {
        return TGStringValue(((NSDictionary *)text)[@"text"]);
    }
    return @"";
}

NSString *TGMessageContentType(NSDictionary *content) {
    return TGStringValue(content[@"@type"]);
}

BOOL TGMessageContentIsService(NSDictionary *content) {
    static NSSet<NSString *> *serviceTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        serviceTypes = [NSSet setWithArray:@[
            @"messageBasicGroupChatCreate",
            @"messageChatAddMembers",
            @"messageChatChangePhoto",
            @"messageChatChangeTitle",
            @"messageChatDeleteMember",
            @"messageChatDeletePhoto",
            @"messageChatJoinByLink",
            @"messageChatJoinByRequest",
            @"messageChatSetTheme",
            @"messageChatSetTtl",
            @"messageChatUpgradeFrom",
            @"messageChatUpgradeTo",
            @"messageContactRegistered",
            @"messageCustomServiceAction",
            @"messageGameScore",
            @"messageGiftedPremium",
            @"messageGiftedStars",
            @"messageGiftedTon",
            @"messageGroupCall",
            @"messageGroupCallScheduled",
            @"messageInviteVideoChatParticipants",
            @"messagePassportDataReceived",
            @"messagePassportDataSent",
            @"messagePaymentSuccessful",
            @"messagePaymentSuccessfulBot",
            @"messagePinMessage",
            @"messageProximityAlertTriggered",
            @"messageScreenshotTaken",
            @"messageSupergroupChatCreate",
            @"messageUnsupported",
            @"messageVideoChatEnded",
            @"messageVideoChatScheduled",
            @"messageVideoChatStarted",
            @"messageWebsiteConnected",
            @"messageForumTopicCreated",
            @"messageForumTopicEdited",
            @"messageForumTopicIsClosedToggled",
            @"messageForumTopicIsHiddenToggled"
        ]];
    });
    return [serviceTypes containsObject:TGMessageContentType(content)];
}

NSString *TGMessagePreviewText(NSDictionary *content) {
    if (![content isKindOfClass:[NSDictionary class]]) {
        return @"";
    }
    NSString *type = TGMessageContentType(content);
    NSString *caption = TGCaptionFromContent(content);

    if ([type isEqualToString:@"messageText"]) {
        return TGPrimaryTextFromContent(content);
    }
    if ([type isEqualToString:@"messagePhoto"]) {
        return caption.length > 0 ? caption : @"📷 Zdjęcie";
    }
    if ([type isEqualToString:@"messageVideo"]) {
        return caption.length > 0 ? caption : @"🎬 Wideo";
    }
    if ([type isEqualToString:@"messageVideoNote"]) {
        return @"📹 Wiadomość wideo";
    }
    if ([type isEqualToString:@"messageVoiceNote"]) {
        return caption.length > 0 ? caption : @"🎤 Wiadomość głosowa";
    }
    if ([type isEqualToString:@"messageAudio"]) {
        if (caption.length > 0) {
            return caption;
        }
        NSDictionary *audio = content[@"audio"];
        NSString *title = TGStringValue(audio[@"title"]);
        NSString *performer = TGStringValue(audio[@"performer"]);
        if (title.length > 0) {
            return performer.length > 0 ? [NSString stringWithFormat:@"🎵 %@ — %@", performer, title] : [NSString stringWithFormat:@"🎵 %@", title];
        }
        return @"🎵 Audio";
    }
    if ([type isEqualToString:@"messageDocument"]) {
        if (caption.length > 0) {
            return caption;
        }
        NSDictionary *document = content[@"document"];
        NSString *fileName = TGStringValue(document[@"file_name"]);
        return fileName.length > 0 ? [NSString stringWithFormat:@"📎 %@", fileName] : @"📎 Dokument";
    }
    if ([type isEqualToString:@"messageSticker"]) {
        NSDictionary *sticker = content[@"sticker"];
        NSString *emoji = TGStringValue(sticker[@"emoji"]);
        return emoji.length > 0 ? [NSString stringWithFormat:@"%@ Sticker", emoji] : @"Sticker";
    }
    if ([type isEqualToString:@"messageAnimation"]) {
        return caption.length > 0 ? caption : @"🎞 GIF";
    }
    if ([type isEqualToString:@"messageContact"]) {
        return @"👤 Kontakt";
    }
    if ([type isEqualToString:@"messageLocation"]) {
        return @"📍 Lokalizacja";
    }
    if ([type isEqualToString:@"messageVenue"]) {
        return @"📍 Miejsce";
    }
    if ([type isEqualToString:@"messagePoll"]) {
        return @"📊 Ankieta";
    }
    if ([type isEqualToString:@"messageDice"]) {
        return @"🎲 Kość";
    }
    if ([type isEqualToString:@"messageGame"]) {
        return @"🎮 Gra";
    }
    if ([type isEqualToString:@"messageInvoice"]) {
        return @"🧾 Faktura";
    }
    if ([type isEqualToString:@"messageCall"]) {
        return @"📞 Połączenie";
    }
    if ([type isEqualToString:@"messageExpiredPhoto"]) {
        return @"Zdjęcie wygasło";
    }
    if ([type isEqualToString:@"messageExpiredVideo"]) {
        return @"Wideo wygasło";
    }
    if ([type isEqualToString:@"messageBasicGroupChatCreate"] ||
        [type isEqualToString:@"messageSupergroupChatCreate"] ||
        [type isEqualToString:@"messageChannelCreate"]) {
        return @"Utworzono czat";
    }
    if ([type isEqualToString:@"messageChatAddMembers"]) {
        return @"Dodano członków";
    }
    if ([type isEqualToString:@"messageChatJoinByLink"] || [type isEqualToString:@"messageChatJoinByRequest"]) {
        return @"Dołączono do czatu";
    }
    if ([type isEqualToString:@"messageChatDeleteMember"]) {
        return @"Usunięto członka";
    }
    if ([type isEqualToString:@"messageChatChangeTitle"]) {
        return @"Zmieniono nazwę czatu";
    }
    if ([type isEqualToString:@"messageChatChangePhoto"]) {
        return @"Zmieniono zdjęcie czatu";
    }
    if ([type isEqualToString:@"messageChatDeletePhoto"]) {
        return @"Usunięto zdjęcie czatu";
    }
    if ([type isEqualToString:@"messagePinMessage"]) {
        return @"Przypięto wiadomość";
    }
    if ([type isEqualToString:@"messageCall"]) {
        return @"Połączenie";
    }
    if ([type isEqualToString:@"messageScreenshotTaken"]) {
        return @"Zrzut ekranu";
    }
    if ([type isEqualToString:@"messageContactRegistered"]) {
        return @"Kontakt dołączył do Telegrama";
    }
    if ([type isEqualToString:@"messageCustomServiceAction"]) {
        return TGStringValue(content[@"text"]);
    }
    if ([type isEqualToString:@"messageUnsupported"]) {
        return @"Nieobsługiwana wiadomość";
    }

    if (caption.length > 0) {
        return caption;
    }
    if ([type hasPrefix:@"message"]) {
        return [type substringFromIndex:7];
    }
    return @"Wiadomość";
}

@implementation TGChat

+ (instancetype)chatWithDictionary:(NSDictionary *)dictionary {
    TGChat *chat = [[TGChat alloc] init];
    chat.title = @"";
    chat.lastMessageText = @"";
    [chat updateWithDictionary:dictionary];
    return chat;
}

- (void)updateWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return;
    }
    self.raw = dictionary;

    int64_t chatId = TGInt64Value(dictionary[@"id"]);
    if (chatId != 0) {
        self.chatId = chatId;
    }

    NSString *title = TGStringValue(dictionary[@"title"]);
    if (title.length > 0) {
        self.title = title;
    }

    if (dictionary[@"unread_count"] != nil) {
        self.unreadCount = (NSInteger)TGInt32Value(dictionary[@"unread_count"]);
    }

    NSDictionary *type = dictionary[@"type"];
    if ([type isKindOfClass:[NSDictionary class]]) {
        NSString *typeName = TGStringValue(type[@"@type"]);
        BOOL isPrivate = [typeName isEqualToString:@"chatTypePrivate"] ||
                         [typeName isEqualToString:@"chatTypeSecret"];
        self.isGroup = !isPrivate;
        self.isChannel = [typeName isEqualToString:@"chatTypeSupergroup"] &&
                         TGBoolValue(type[@"is_channel"]);
    }

    id positions = dictionary[@"positions"];
    if ([positions isKindOfClass:[NSArray class]]) {
        [self applyPositions:(NSArray *)positions];
    }

    id lastMessage = dictionary[@"last_message"];
    if ([lastMessage isKindOfClass:[NSDictionary class]]) {
        [self applyLastMessage:(NSDictionary *)lastMessage];
    }
}

- (void)applyPositions:(NSArray *)positions {
    BOOL foundMain = NO;
    for (NSDictionary *position in positions) {
        if (![position isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *list = position[@"list"];
        if ([list isKindOfClass:[NSDictionary class]] &&
            [TGStringValue(list[@"@type"]) isEqualToString:@"chatListMain"]) {
            [self applyPosition:position];
            foundMain = YES;
        }
    }
    if (!foundMain) {
        self.hasMainListPosition = NO;
        self.order = 0;
        self.pinned = NO;
    }
}

- (void)applyPosition:(NSDictionary *)position {
    NSDictionary *list = position[@"list"];
    if (![list isKindOfClass:[NSDictionary class]] ||
        ![TGStringValue(list[@"@type"]) isEqualToString:@"chatListMain"]) {
        return;
    }
    self.order = TGInt64Value(position[@"order"]);
    self.pinned = TGBoolValue(position[@"is_pinned"]);
    self.hasMainListPosition = self.order > 0;
}

- (void)applyLastMessage:(NSDictionary *)message {
    if (![message isKindOfClass:[NSDictionary class]]) {
        return;
    }
    self.lastMessageId = TGInt64Value(message[@"id"]);
    self.lastMessageDate = TGInt32Value(message[@"date"]);
    self.lastMessageIsOutgoing = TGBoolValue(message[@"is_outgoing"]);
    id content = message[@"content"];
    self.lastMessageText = [content isKindOfClass:[NSDictionary class]] ? TGMessagePreviewText(content) : @"";
}

@end

@implementation TGMessage

+ (instancetype)messageWithDictionary:(NSDictionary *)dictionary {
    TGMessage *message = [[TGMessage alloc] init];
    message.text = @"";
    message.contentType = @"";
    [message updateWithDictionary:dictionary];
    return message;
}

- (void)updateWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return;
    }
    self.raw = dictionary;

    int64_t messageId = TGInt64Value(dictionary[@"id"]);
    if (messageId != 0) {
        self.messageId = messageId;
    }
    self.chatId = TGInt64Value(dictionary[@"chat_id"]);
    self.date = TGInt32Value(dictionary[@"date"]);
    self.isOutgoing = TGBoolValue(dictionary[@"is_outgoing"]);

    id content = dictionary[@"content"];
    if ([content isKindOfClass:[NSDictionary class]]) {
        self.contentType = TGMessageContentType((NSDictionary *)content);
        self.text = TGMessagePreviewText((NSDictionary *)content);
        self.isService = TGMessageContentIsService((NSDictionary *)content);
    }

    NSDictionary *sendingState = dictionary[@"sending_state"];
    if ([sendingState isKindOfClass:[NSDictionary class]]) {
        NSString *sendingType = TGStringValue(sendingState[@"@type"]);
        self.isSending = ![sendingType isEqualToString:@"messageSendingStateFailed"];
        self.isFailed = [sendingType isEqualToString:@"messageSendingStateFailed"];
    } else {
        self.isSending = NO;
        self.isFailed = NO;
    }

    NSDictionary *sender = dictionary[@"sender_id"];
    if ([sender isKindOfClass:[NSDictionary class]]) {
        NSString *senderType = TGStringValue(sender[@"@type"]);
        if ([senderType isEqualToString:@"messageSenderUser"]) {
            self.senderIsUser = YES;
            self.senderId = TGInt64Value(sender[@"user_id"]);
        } else if ([senderType isEqualToString:@"messageSenderChat"]) {
            self.senderIsUser = NO;
            self.senderId = TGInt64Value(sender[@"chat_id"]);
        }
    }
}

@end
