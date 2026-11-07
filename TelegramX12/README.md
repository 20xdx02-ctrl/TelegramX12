# Telegram X 12

Nowy, samodzielny klient Telegrama dla **iOS 12**, oparty na nowoczesnym **TDLib 1.8.69** (API layer 233), a nie na starym `TelegramCore` z tego repozytorium.

Aplikacja jest napisana w Objective-C/UIKit i buduje się lokalnie przez **Theos** (Linux/macOS) oraz przez **GitHub Actions** (macOS + Xcode). Interfejs jest inspirowany Telegramem X, ale nie kopiuje kodu Swift z `TelegramUI` — szczegóły w sekcji „Dlaczego nie Swift UI z Telegram X?”.

## Co już działa

- logowanie numerem telefonu,
- kod z wiadomości/SMS/połączenia,
- hasło dwuetapowe,
- rejestracja nowego konta i akceptacja regulaminu,
- lista czatów z sortowaniem, przypięciami i licznikiem nieprzeczytanych,
- historia wiadomości (ładowanie starszych przez pull-to-refresh),
- wysyłanie wiadomości tekstowych,
- oznaczanie wiadomości jako przeczytane,
- aktualizacje w czasie rzeczywistym (nowe wiadomości, zmiany pozycji czatu, tytułu, licznika),
- ekran ustawień `api_id` / `api_hash` oraz wylogowanie,
- dane TDLib w `Library/Application Support/TelegramX12`.

Czego jeszcze nie ma: avatary i pobieranie plików, zdjęcia/wideo/stickery, powiadomienia push, wyszukiwanie, drafts, tematy, zarządzanie grupami, połączenia. To jest baza pod dalszy rozwój, a nie pełny klon Telegrama.

## Ważne: własne `api_id` i `api_hash`

Telegram wymaga własnej pary `api_id` / `api_hash`. Zdobędziesz ją bezpłatnie na <https://my.telegram.org> w sekcji **API development tools**.

Po pierwszym uruchomieniu:

1. Otwórz **Ustawienia API** (na ekranie logowania lub w prawym górnym rogu listy czatów).
2. Wpisz `api_id` i `api_hash`.
3. Zapisz i wróć do logowania.

Dane są zapisywane w `NSUserDefaults` (nie są szyfrowane). Nie commituj ich do repozytorium. Możesz też podać je na etapie kompilacji:

```sh
make TelegramX12_CFLAGS="-DTG_DEFAULT_API_ID=12345678 '-DTG_DEFAULT_API_HASH=@\"...\"'"
```

albo w `TGConfig.h`.

## Budowanie lokalnie (Linux, Theos)

Wymagania:

- Theos (`$THEOS`) z SDK `iPhoneOS12.4.sdk`,
- clang z toolchainu Theos,
- `ldid` (Theos ma go w `$THEOS/bin`),
- ok. 100 MB miejsca na statyczny TDLib.

Statyczny framework TDLib jest już w `Vendor/TDLibFramework.framework` (iOS arm64, `minos 12.0`). Jeśli go brakuje:

```sh
./Scripts/fetch-tdlib.sh
```

Build:

```sh
cd TelegramX12
make clean
make package
```

Wynik: `packages/com.telegramx12.app_*_iphoneos-arm.deb`.

Niepodpisany IPA do późniejszego podpisania (Sideloadly/AltStore/开发者 certificate):

```sh
make
./Scripts/make-ipa.sh
# packages/TelegramX12-unsigned.ipa
```

Uwaga: `make package` tworzy paczkę dla jailbroken iOS 12. Na urządzeniu bez jailbreaka trzeba podpisać `.app`/IPA własnym certyfikatem i provisioning profile.

## Budowanie przez GitHub Actions

Workflow `.github/workflows/ios.yml`:

- uruchamia się na `macos-15` (Xcode 16.4; `macos-14` wycofano 2026-11-02),
- instaluje XcodeGen,
- generuje projekt Xcode z `TelegramX12/project.yml`,
- buduje `TelegramX12.app` dla `iphoneos/arm64` z deployment target `12.0`,
- pakuje niepodpisany IPA i wrzuca go jako artefakt.

Uruchomienie: wypchnij branch `telegramx12` (albo użyj **Run workflow**). Artefakt: `TelegramX12-unsigned-ipa`.

Build w Xcode lokalnie na macOS:

```sh
brew install xcodegen
cd TelegramX12
xcodegen generate
open TelegramX12.xcodeproj
```

W Xcode ustaw swój Team / Signing i uruchom na urządzeniu z iOS 12+.

## Dlaczego Objective-C, a nie Swift/TelegramUI?

To świadoma decyzja techniczna:

1. **Stary `TelegramCore` nie obsłuży dzisiejszego Telegrama.** `currentLayer()` w `TelegramCore/Serialization.swift` zwraca 100, a serwery wymagają warstwy ≥ 176 do logowania. Układy `User`, `Chat`, `Message`, `Dialog` i `updates.Difference` zmieniły się od 2019 roku, więc sam login nie wystarczy.
2. **`TelegramUI` z Telegram X nie da się podmienić na TDLib.** 608 z 993 plików importuje `TelegramCore`, 579 — `Postbox`, 603 — `SwiftSignalKit`, 739 — `Display`. To nie jest warstwa prezentacji, tylko mocno związany framework.
3. **Brak licencji.** Repozytorium `peter-iakovlev/TelegramUI` nie ma pliku LICENSE. Kopiowanie kodu bez zgody jest ryzykowne prawne. Dlatego UI jest napisane od zera „w stylu Telegram X”: niebieski akcent, okrągłe avatary z inicjałami, bańki wiadomości, duży tytuł listy czatów, pole tekstowe z przyciskiem wysyłania.
4. **To środowisko nie ma Xcode ani iOS-owego Swift SDK.** Theos z `iPhoneOS12.4.sdk` nie zawiera `.swiftmodule`, a `xtool` wymaga `Xcode.xip`. Objective-C + Theos pozwala zbudować i zweryfikować aplikację tutaj. TDLib i tak jest C/C++, więc backend jest nowoczesny.

Jeśli w przyszłości chcesz przenieść wybrane widoki z Telegram X, najprostsza droga to port pojedynczych plików prezentacyjnych (np. style, animacje, assety) do UIKit/ObjC lub zbudowanie całej aplikacji w Swift na macOS z Xcode. Nie kopiuj całego `TelegramUI` — pociąga za sobą `TelegramCore`/`Postbox`.

## Struktura

```
TelegramX12/
  Makefile                  # build Theos
  project.yml               # projekt Xcode dla XcodeGen / CI
  Info.plist
  control                   # metadane .deb
  Sources/
    main.m
    TGAppDelegate.*
    TGConfig.*              # api_id/api_hash
    TGTDLibClient.*         # most do TDLib JSON API, cache, auth, czaty
    TGModels.*              # TGChat/TGMessage + parsowanie JSON
    TGLoginViewController.* # telefon/kod/2FA/rejestracja/ToS
    TGChatListViewController.*
    TGChatListCell.*
    TGChatViewController.*
    TGMessageCell.*
    TGInputBar.*
    TGSettingsViewController.*
    TGTheme.*, TGAvatarView.*, TGLogoView.*
    compat.c                # shim ___darwin_check_fd_set_overflow dla iOS 12
  Vendor/TDLibFramework.framework  # TDLib 1.8.69, statyczny, iOS arm64
  Resources/                # ikony
  Scripts/                  # fetch-tdlib.sh, make-ipa.sh
```

## TDLib

- wersja: `1.8.69-4c6377aa`
- źródło binarne: [Swiftgram/TDLibFramework](https://github.com/Swiftgram/TDLibFramework) (statyczny XCFramework, `minos 12.0`)
- API: C `td_json_client` (`td_create_client_id`, `td_send`, `td_receive`, `td_execute`)
- TDLib sam utrzymuje połączenie, szyfrowanie, bazę i synchronizację; aplikacja tylko wysyła JSON i renderuje update'y.

`compat.c` dostarcza `__darwin_check_fd_set_overflow`, którego brakuje w systemowej libc iOS 12, a którego wymaga BoringSSL z nowszego SDK. Bez tego shimu linkowanie kończy się błędem.

## Bezpieczeństwo i znaki towarowe

- To projekt niezależny, niepowiązany z Telegram FZ-LLC.
- „Telegram” i logo Telegram są znakami towarowymi Telegram FZ-LLC. Używaj ich zgodnie z zasadami marki.
- TDLib jest na licencji Boost 1.0.
- Kod UI w tym repozytorium jest nowy; nie zawiera kodu `TelegramUI`.
- `api_hash` jest przechowywany lokalnie w `NSUserDefaults`; w produkcji warto użyć Keychain i włączyć szyfrowanie bazy TDLib (`database_encryption_key`).

## Znane ograniczenia

- brak pobierania avatarów (wyświetlane są inicjały),
- brak obsługi multimediów (poza tekstem),
- brak powiadomień push i dźwięków,
- brak obsługi `authorizationStateWaitEmailAddress` / `WaitEmailCode` / `WaitPremiumPurchase` (typowe konto telefonem tego nie wymaga),
- brak obsługi QR (`requestQrCodeAuthentication`),
- brak grupowania wiadomości według daty,
- brak obsługi kanałów jako nadawcy (wyświetlany jest tekst wiadomości),
- `UILaunchScreen` jest kluczem iOS 14+; na iOS 12 aplikacja po prostu startuje bez launch screenu.
