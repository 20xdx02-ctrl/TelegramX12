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

NSString *TGDataSizeString(int64_t size) {
    if (size >= 1024LL * 1024LL * 1024LL) {
        double rem = (double)(size % (1024LL * 1024LL * 1024LL)) / (1024.0 * 1024.0 * 102.4);
        int64_t rounded = (int64_t)floor(rem);
        if (rounded != 0) {
            return [NSString stringWithFormat:@"%lld.%lld GB", size / (1024LL * 1024LL * 1024LL), (long long)rounded];
        } else {
            return [NSString stringWithFormat:@"%lld GB", size / (1024LL * 1024LL * 1024LL)];
        }
    } else if (size >= 1024LL * 1024LL) {
        double rem = (double)(size % (1024LL * 1024LL)) / (1024.0 * 102.4);
        int64_t rounded = (int64_t)floor(rem);
        if (rounded != 0) {
            return [NSString stringWithFormat:@"%lld.%lld MB", size / (1024LL * 1024LL), (long long)rounded];
        } else {
            return [NSString stringWithFormat:@"%lld MB", size / (1024LL * 1024LL)];
        }
    } else if (size >= 1024LL) {
        int64_t rem = (size % 1024LL) / 102LL;
        if (rem != 0) {
            return [NSString stringWithFormat:@"%lld.%lld KB", size / 1024LL, (long long)rem];
        } else {
            return [NSString stringWithFormat:@"%lld KB", size / 1024LL];
        }
    } else {
        return [NSString stringWithFormat:@"%lld B", (long long)size];
    }
}

NSString *TGDurationString(int32_t seconds) {
    if (seconds <= 0) return @"0:00";
    int32_t m = seconds / 60;
    int32_t s = seconds % 60;
    if (m >= 60) {
        int32_t h = m / 60;
        m = m % 60;
        return [NSString stringWithFormat:@"%d:%02d:%02d", h, m, s];
    }
    return [NSString stringWithFormat:@"%d:%02d", m, s];
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

static NSString *TGLocalPathFromFile(NSDictionary *file) {
    if (![file isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *local = file[@"local"];
    if (![local isKindOfClass:[NSDictionary class]]) return nil;
    if (TGBoolValue(local[@"is_downloading_completed"])) {
        NSString *path = TGStringValue(local[@"path"]);
        if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return path;
        }
    }
    return nil;
}

NSString *TGMessageContentType(NSDictionary *content) {
    NSString *type = TGStringValue(content[@"@type"]);
    // While a message is still being sent TDLib carries the input content
    // (inputMessagePhoto…). Normalize it to the delivered form so pending
    // messages render identically to confirmed ones.
    if ([type hasPrefix:@"inputMessage"] && type.length > [@"inputMessage" length]) {
        type = [NSString stringWithFormat:@"message%@", [type substringFromIndex:[@"inputMessage" length]]];
    }
    return type;
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

    if (dictionary[@"last_read_inbox_message_id"] != nil) {
        self.lastReadInboxMessageId = TGInt64Value(dictionary[@"last_read_inbox_message_id"]);
    }
    if (dictionary[@"last_read_outbox_message_id"] != nil) {
        self.lastReadOutboxMessageId = TGInt64Value(dictionary[@"last_read_outbox_message_id"]);
    }

    NSDictionary *notif = dictionary[@"notification_settings"];
    if ([notif isKindOfClass:[NSDictionary class]]) {
        self.isMuted = !TGBoolValue(notif[@"use_default_mute_for"]) && (TGInt32Value(notif[@"mute_for"]) > 0);
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
        NSDictionary *contentDict = (NSDictionary *)content;
        self.contentType = TGMessageContentType(contentDict);
        self.text = TGMessagePreviewText(contentDict);
        self.isService = TGMessageContentIsService(contentDict);

        if (self.isService) {
            self.messageType = TGMessageTypeService;
        } else if ([self.contentType isEqualToString:@"messageText"]) {
            self.messageType = TGMessageTypeText;
        } else if ([self.contentType isEqualToString:@"messagePhoto"]) {
            self.messageType = TGMessageTypePhoto;
            self.mediaCaption = TGCaptionFromContent(contentDict);
            NSDictionary *photo = contentDict[@"photo"];
            if ([photo isKindOfClass:[NSDictionary class]]) {
                NSArray *sizes = photo[@"sizes"];
                if ([sizes isKindOfClass:[NSArray class]] && sizes.count > 0) {
                    NSDictionary *bestSize = sizes.lastObject;
                    for (NSDictionary *size in sizes) {
                        if ([TGStringValue(size[@"type"]) isEqualToString:@"x"] || [TGStringValue(size[@"type"]) isEqualToString:@"y"]) {
                            bestSize = size;
                            break;
                        }
                    }
                    self.mediaFileId = TGInt32Value(bestSize[@"photo"][@"id"]);
                    self.mediaWidth = TGInt32Value(bestSize[@"width"]);
                    self.mediaHeight = TGInt32Value(bestSize[@"height"]);

                    NSDictionary *thumbSize = sizes.firstObject;
                    self.thumbnailFileId = TGInt32Value(thumbSize[@"photo"][@"id"]);
                    self.mediaLocalPath = TGLocalPathFromFile(bestSize[@"photo"]);
                    if (self.mediaLocalPath.length == 0) {
                        self.mediaLocalPath = TGLocalPathFromFile(thumbSize[@"photo"]);
                    }
                }
                NSDictionary *minithumb = photo[@"minithumbnail"];
                if ([minithumb isKindOfClass:[NSDictionary class]]) {
                    NSString *dataStr = TGStringValue(minithumb[@"data"]);
                    if (dataStr.length > 0) {
                        self.minithumbnailData = [[NSData alloc] initWithBase64EncodedString:dataStr options:NSDataBase64DecodingIgnoreUnknownCharacters];
                    }
                }

                // Pending sends carry inputMessagePhoto.photo.photo as a bare
                // inputFileLocal; use its path for an instant local preview.
                if (self.mediaLocalPath.length == 0) {
                    NSString *pendingPath = TGStringValue(photo[@"photo"][@"path"]);
                    if (pendingPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:pendingPath]) {
                        self.mediaLocalPath = pendingPath;
                    }
                }
            }
        } else if ([self.contentType isEqualToString:@"messageSticker"]) {
            self.messageType = TGMessageTypeSticker;
            NSDictionary *sticker = contentDict[@"sticker"];
            if ([sticker isKindOfClass:[NSDictionary class]]) {
                self.stickerEmoji = TGStringValue(sticker[@"emoji"]);
                self.mediaWidth = TGInt32Value(sticker[@"width"]);
                self.mediaHeight = TGInt32Value(sticker[@"height"]);
                NSDictionary *thumb = sticker[@"thumbnail"];
                if ([thumb isKindOfClass:[NSDictionary class]]) {
                    self.thumbnailFileId = TGInt32Value(thumb[@"file"][@"id"]);
                }

                NSDictionary *format = sticker[@"format"];
                NSString *formatType = TGStringValue(format[@"@type"]);
                BOOL isVectorOrVideo = [formatType isEqualToString:@"stickerFormatTgs"] ||
                                       [formatType isEqualToString:@"stickerFormatWebm"] ||
                                       TGBoolValue(sticker[@"is_animated"]) ||
                                       TGBoolValue(sticker[@"is_video"]);

                if (isVectorOrVideo && self.thumbnailFileId > 0) {
                    self.mediaFileId = self.thumbnailFileId;
                    self.mediaLocalPath = TGLocalPathFromFile(thumb[@"file"]);
                } else {
                    self.mediaFileId = TGInt32Value(sticker[@"sticker"][@"id"]);
                    self.mediaLocalPath = TGLocalPathFromFile(sticker[@"sticker"]);
                    if (self.mediaLocalPath.length == 0 && [thumb isKindOfClass:[NSDictionary class]]) {
                        self.mediaLocalPath = TGLocalPathFromFile(thumb[@"file"]);
                    }
                }
            }
        } else if ([self.contentType isEqualToString:@"messageAnimation"]) {
            self.messageType = TGMessageTypeAnimation;
            self.mediaCaption = TGCaptionFromContent(contentDict);
            NSDictionary *anim = contentDict[@"animation"];
            if ([anim isKindOfClass:[NSDictionary class]]) {
                self.mediaFileId = TGInt32Value(anim[@"animation"][@"id"]);
                self.mediaWidth = TGInt32Value(anim[@"width"]);
                self.mediaHeight = TGInt32Value(anim[@"height"]);
                self.mediaDuration = TGInt32Value(anim[@"duration"]);
                self.mediaFileName = TGStringValue(anim[@"file_name"]);
                self.mimeType = TGStringValue(anim[@"mime_type"]);
                NSDictionary *thumb = anim[@"thumbnail"];
                if ([thumb isKindOfClass:[NSDictionary class]]) {
                    self.thumbnailFileId = TGInt32Value(thumb[@"file"][@"id"]);
                }
                NSDictionary *minithumb = anim[@"minithumbnail"];
                if ([minithumb isKindOfClass:[NSDictionary class]]) {
                    NSString *dataStr = TGStringValue(minithumb[@"data"]);
                    if (dataStr.length > 0) {
                        self.minithumbnailData = [[NSData alloc] initWithBase64EncodedString:dataStr options:NSDataBase64DecodingIgnoreUnknownCharacters];
                    }
                }
            }
        } else if ([self.contentType isEqualToString:@"messageVideo"]) {
            self.messageType = TGMessageTypeVideo;
            self.mediaCaption = TGCaptionFromContent(contentDict);
            NSDictionary *video = contentDict[@"video"];
            if ([video isKindOfClass:[NSDictionary class]]) {
                self.mediaFileId = TGInt32Value(video[@"video"][@"id"]);
                self.mediaWidth = TGInt32Value(video[@"width"]);
                self.mediaHeight = TGInt32Value(video[@"height"]);
                self.mediaDuration = TGInt32Value(video[@"duration"]);
                self.mediaFileName = TGStringValue(video[@"file_name"]);
                NSDictionary *thumb = video[@"thumbnail"];
                if ([thumb isKindOfClass:[NSDictionary class]]) {
                    self.thumbnailFileId = TGInt32Value(thumb[@"file"][@"id"]);
                }
                NSDictionary *minithumb = video[@"minithumbnail"];
                if ([minithumb isKindOfClass:[NSDictionary class]]) {
                    NSString *dataStr = TGStringValue(minithumb[@"data"]);
                    if (dataStr.length > 0) {
                        self.minithumbnailData = [[NSData alloc] initWithBase64EncodedString:dataStr options:NSDataBase64DecodingIgnoreUnknownCharacters];
                    }
                }
            }
        } else if ([self.contentType isEqualToString:@"messageVoiceNote"]) {
            self.messageType = TGMessageTypeVoiceNote;
            self.mediaCaption = TGCaptionFromContent(contentDict);
            NSDictionary *vn = contentDict[@"voice_note"];
            if ([vn isKindOfClass:[NSDictionary class]]) {
                self.mediaFileId = TGInt32Value(vn[@"voice"][@"id"]);
                self.mediaDuration = TGInt32Value(vn[@"duration"]);
            }
        } else if ([self.contentType isEqualToString:@"messageAudio"]) {
            self.messageType = TGMessageTypeAudio;
            self.mediaCaption = TGCaptionFromContent(contentDict);
            NSDictionary *audio = contentDict[@"audio"];
            if ([audio isKindOfClass:[NSDictionary class]]) {
                self.mediaFileId = TGInt32Value(audio[@"audio"][@"id"]);
                self.mediaDuration = TGInt32Value(audio[@"duration"]);
                self.mediaTitle = TGStringValue(audio[@"title"]);
                self.mediaPerformer = TGStringValue(audio[@"performer"]);
                self.mediaFileName = TGStringValue(audio[@"file_name"]);
                self.mediaFileSize = TGInt64Value(audio[@"audio"][@"size"]);
            }
        } else if ([self.contentType isEqualToString:@"messageDocument"]) {
            self.messageType = TGMessageTypeDocument;
            self.mediaCaption = TGCaptionFromContent(contentDict);
            NSDictionary *doc = contentDict[@"document"];
            if ([doc isKindOfClass:[NSDictionary class]]) {
                self.mediaFileId = TGInt32Value(doc[@"document"][@"id"]);
                self.mediaFileName = TGStringValue(doc[@"file_name"]);
                self.mediaFileSize = TGInt64Value(doc[@"document"][@"size"]);
                NSDictionary *thumb = doc[@"thumbnail"];
                if ([thumb isKindOfClass:[NSDictionary class]]) {
                    self.thumbnailFileId = TGInt32Value(thumb[@"file"][@"id"]);
                }
            }
        } else if ([self.contentType isEqualToString:@"messageContact"]) {
            self.messageType = TGMessageTypeContact;
            NSDictionary *contact = contentDict[@"contact"];
            if ([contact isKindOfClass:[NSDictionary class]]) {
                NSString *fn = TGStringValue(contact[@"first_name"]);
                NSString *ln = TGStringValue(contact[@"last_name"]);
                NSString *full = [NSString stringWithFormat:@"%@ %@", fn, ln];
                self.contactName = [full stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                self.contactPhone = TGStringValue(contact[@"phone_number"]);
            }
        } else if ([self.contentType isEqualToString:@"messageLocation"]) {
            self.messageType = TGMessageTypeLocation;
            NSDictionary *loc = contentDict[@"location"];
            if ([loc isKindOfClass:[NSDictionary class]]) {
                self.latitude = [loc[@"latitude"] doubleValue];
                self.longitude = [loc[@"longitude"] doubleValue];
            }
        } else if ([self.contentType isEqualToString:@"messagePoll"]) {
            self.messageType = TGMessageTypePoll;
            NSDictionary *poll = contentDict[@"poll"];
            if ([poll isKindOfClass:[NSDictionary class]]) {
                self.pollQuestion = TGStringValue(poll[@"question"]);
                NSArray *opts = poll[@"options"];
                if ([opts isKindOfClass:[NSArray class]]) {
                    NSMutableArray *titles = [NSMutableArray array];
                    for (NSDictionary *opt in opts) {
                        if ([opt isKindOfClass:[NSDictionary class]]) {
                            NSString *t = TGStringValue(opt[@"text"]);
                            if (t.length > 0) [titles addObject:t];
                        }
                    }
                    self.pollOptions = titles;
                }
            }
        } else {
            self.messageType = TGMessageTypeUnsupported;
        }
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

    if (dictionary[@"is_read"] != nil) {
        self.isRead = TGBoolValue(dictionary[@"is_read"]);
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
