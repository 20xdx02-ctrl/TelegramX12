# Roadmapa Telegram X 12

Stan wyjściowy (po buildzie `7fb6a3e`): login (telefon / kod / SMS / 2FA / rejestracja), lista czatów (przypinanie, licznik nieprzeczytanych, wyszukiwanie lokalne), historia z „od pierwszej nieprzeczytej”, wysyłanie tekstu / zdjęć / stickerów, wybierak stickerów, przeczytywanie (inbox+outbox), iPad two-pane, ustawienia API + wylogowanie.

Priorytety: **P1** = bez tego codzienne używanie boli, **P2** = ważne, **P3** = polish.

---

## 0. Drobiazgi spójności (P1, szybkie)

- [ ] **Grupowanie wiadomości według dnia** — service rows „Dziś / Wczoraj / data” jak `ChatHistoryHeaderItem` w Telegramie X.
- [ ] **Status „online / pisze…”** w nagłówku czatu — obsługa `updateChatUserAction` (typing) i `updateUserStatus`.
- [ ] **Checkmarki „przeczytane”** przy własnych wiadomościach — obsługa `updateChatReadOutbox` (model `isOutgoing` już jest, brakuje renderu).
- [ ] **Czasy w liście czatów** — względne (HH:MM, „Wczoraj”) zamiast bezwzględnego timestampu.
- [ ] **Avatary** — `chat.photo` / `user.profile_photo` → `downloadFile` + cache na dysku; `TGAvatarView` już istnieje, trzeba dokarmić plikami.
- [ ] **Launch screen na iOS 12** — statyczny obraz w Resources.

## 1. Pełne multimedium (P1)

- [ ] **Podgląd zdjęć w bańce** (thumbnail z `messagePhoto`) + **photo viewer** na tapnięcie: powiększenie, swipe-down do zamknięcia (szkielet `TGPhotoViewerController` już jest — dokończyć).
- [ ] **Wysyłanie z galerii** — `UIImagePickerController` (na iOS 12 `PHPickerController` nie istnieje).
- [ ] **Dokumenty** — render `messageDocument` (ikona, nazwa, rozmiar), `downloadFile` + otwieranie przez `QLPreviewController`.
- [ ] **GIF-y (`messageAnimation`)** — render animacji; docelowo reużyć `TGWebPConverter` lub `CAKeyframeAnimation`.
- [ ] **Wiadomości głosowe** — `messageVoiceNote`: pasek z długością + odtwarzanie (`AVAudioPlayer`); rozwiązać dekodowanie opus/ogg.
- [ ] **Postęp wysyłki** — `updateFile` (upload progress): spinner/wprost procent w miejscu wysyłanej wiadomości.
- [ ] **Ponawianie nieudanych wysyłek** — tap na bańce z błędem → resend.
- [x] **Kolaże / albumy zdjęć** — grupowanie po `media_album_id`, siatka 2/3/4 zdjęć, tap otwiera pełny rozmiar.

## 2. Interakcja z wiadomościami (P1)

- [x] **Długie przytrzymanie na wiadomości** → action sheet: kopiuj, odpowiedz, przekaż, usuń (własne: `deleteMessages` z `revoke=true`).
- [x] **Odpowiadanie (reply)** — pasek cytatu nad input barem; `sendMessage` z `reply_to = {message_id}`.
- [x] **Edycja** — `editMessageText` + znaczek „edytowano”.
- [x] **Przekazywanie** — `forwardMessages` + prosty wybierak czatu.
- [x] **Kopiowanie tekstu** z bańki.
- [x] **Podświetlanie linków** — adresy URL/e-mail na niebiesko, tap otwiera w Safari.
- [x] **Czytelniejszy wygląd** — kolory autorów w grupach, linki w podpisach, dopracowane bąbelki multimediów.
- [ ] **Link preview** — `formattedText.entities` / `messageText.web_page`: tytuł, opis, miniatura.

## 3. Powiadomienia (P1)

- [ ] **Local notifications** — przy `updateNewMessage` gdy czat nieotwarty → `UNUserNotificationCenter` (dostępne od iOS 10) + dźwięk.
- [ ] **Tap na powiadomienie** → otwarcie właściwego czatu.
- [ ] **Wyciszanie czatów** — `chat.notification_settings` (`updateChatNotificationSettings`): nie budź z czatów wyciszonych.
- [ ] **Badge ikony** = suma nieprzeczytanych (z `updateChatReadInbox`).

## 4. Trwałość i higiena (P2)

- [ ] **Robocze wersje (draft)** — `chat.draft_message`: zapamiętywanie tekstu per czat + `setChatDraftMessage`; „draft:” w liście.
- [ ] **Różnicowe przeładowanie listy** — update rząd po rzędzie z `updateChatLastMessage`/`chatPosition` zamiast pełnego `reloadData`.
- [ ] **Zamykanie TDLib w tle** — `applicationDidEnterBackground` → porządne `close`; rozważać background task (~3 min na iOS 12).
- [ ] **Szyfrowanie bazy** — `database_encryption_key` w `setTdlibParameters`.
- [ ] **Keychain** dla `api_id`/`api_hash` zamiast `NSUserDefaults`.

## 5. Grupy / kanały (P2)

- [ ] **Profil czatu** — duży awatar, bio/username, liczba uczestników, wycisz/wyjdz (`leaveChat`).
- [ ] **Kanał jako nadawca** — podpis kanału przy wiadomości (obecnie tylko tekst).
- [ ] **Zaproszenia** — obsługa linków (publiczne grupy/kanały: `joinChatByInviteLink`).
- [ ] **Akcje admina** — pin/unpin wiadomości, usuwanie cudzych, slow mode; wg `chatMemberStatus`.
- [ ] **Reakcje** — `updateMessageInteractionInfo` + wysyłanie reakcji.

## 6. Lista czatów — zaawansowane (P2)

- [ ] **Menu kontekstowe czatu** (long-press) — pin/unpin, wycisz, oznacz jako przeczytane, usuń historię.
- [ ] **Globalne wyszukiwanie** — `searchPublicChat` / `searchChatsOnServer`: ludzie i kanały poza lokalną listą.
- [ ] **Wyszukiwanie wewnątrz czatu** — `searchChatMessages` z belką wyników.
- [ ] **Saved Messages** — przypięta pozycja u góry.
- [ ] **Foldery czatów** (`chatFolder`) — początkowo tylko wyświetlanie.

## 7. Połączenia (P2)

- [ ] **Rozpoznawanie `updateCall`** — „połączenie w toku” w liście/czacie (render only).
- [ ] Realne WebRTC z TDLib (`acceptCall`…) — duży projekt, na końcu.

## 8. Zaawansowane (P3)

- [ ] **Secret chats** — `createSecretChat`, self-destruct timer, wyjątkowy render.
- [ ] **Login przez QR** (`requestQrCodeAuthentication`) — QR wygenerowany `CIFilter` „CIQRCodeGenerator”.
- [ ] `authorizationStateWaitEmailAddress` / `WaitEmailCode` — konta premium.
- [ ] **Tematy / fora** — `messageThreadInfo`, duży projekt.
- [ ] **Animacje przejść** — bańka wysuwana od input bara, tranzycje czatów.
- [ ] **Dark mode** — ciemna paleta w `TGTheme` + przełącznik w ustawieniach.
- [ ] **Lokalizacja PL/EN** + prosty wrapper `L10n`.

---

## Milstone'y — zaproponowana kolejność

| Krok | Zakres | Efekt na iPanie |
|---|---|---|
| **M1** | działy 0 (dni, typing, checkmarki, czasy, avatary, launch screen) | aplikacja wygląda „po telegramowemu” |
| **M2** | działy 1 (photo viewer, galeria, dokumenty, postęp uploadu) | pełny przepływ zdjęć i plików |
| **M3** | działy 2 (reply, delete, forward, edit, long-press) | zarządzanie wiadomościami |
| **M4** | działy 3 (powiadomienia, mute, badge) | działa jak prawdziwy messenger |
| **M5** | działy 4 (draft, diff-reload listy, szyfrowanie, Keychain) | trwałość i bezpieczeństwo |
| **M6** | działy 5–6 (profil czatu, kanały, reakcje, global search) | życia grupowego |
| **M7** | działy 7–8 (połączenia, secret chats, QR, dark mode, animacje) | polish |

Każdy milestone = jeden cykl: commit → CI → `./install_ci_ipa.sh` → weryfikacja na iPadzie.
