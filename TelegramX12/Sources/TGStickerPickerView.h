#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGTDLibClient;

typedef void (^TGStickerPickerSelectBlock)(NSDictionary *sticker);

/// Grid panel with sticker sections (Ulubione, Ostatnie, zainstalowane paczki),
/// shown above the input bar in the style of Telegram X's sticker pane.
@interface TGStickerPickerView : UIView

- (instancetype)initWithClient:(TGTDLibClient *)client;

/// Called when the user taps a sticker; the chat controller sends it.
@property (nonatomic, copy, nullable) TGStickerPickerSelectBlock onSelectSticker;

/// Called when the user taps the close button on the panel header.
@property (nonatomic, copy, nullable) void (^onClose)(void);

/// Fetches sticker sections from TDLib and reloads the grid.
- (void)reloadFromServer;

@end

NS_ASSUME_NONNULL_END
