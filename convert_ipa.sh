#!/bin/bash
set -e

IP="192.168.18.157"
USER="root"
IPA_PATH="TelegramX12-unsigned-ipa/TelegramX12-unsigned.ipa"

if [ ! -f "$IPA_PATH" ]; then
    echo "Nie znaleziono pliku IPA: $IPA_PATH"
    exit 1
fi

echo "1. Rozpakowywanie IPA z GitHub Actions..."
rm -rf /tmp/payload_work
mkdir -p /tmp/payload_work/Payload
unzip -q "$IPA_PATH" -d /tmp/payload_work/

APP_DIR=$(find /tmp/payload_work/Payload -maxdepth 1 -name "*.app" | head -n 1)
if [ -z "$APP_DIR" ]; then
    echo "Nie znaleziono aplikacji .app w IPA!"
    exit 1
fi

echo "Znaleziono aplikację: $APP_DIR"

echo "2. Pakowanie do struktury debianowej (deb)..."
mkdir -p /tmp/deb_build/Applications
cp -R "$APP_DIR" /tmp/deb_build/Applications/

mkdir -p /tmp/deb_build/DEBIAN
cat << 'EOT' > /tmp/deb_build/DEBIAN/control
Package: com.telegramx12.app
Name: Telegram X 12 (CI Build)
Version: 1.0.0-ci
Architecture: iphoneos-arm
Description: Telegram X 12 client built by GitHub Actions CI.
Maintainer: TelegramX12 Project
Author: TelegramX12 Project
Section: Applications
Priority: optional
Depends: firmware (>= 12.0), mobilesubstrate
EOT

# Tworzenie pliku .deb za pomocą dpkg-deb jeśli dostępny, lub tar
if which dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -b /tmp/deb_build /tmp/telegramx12_ci.deb
else
    echo "Brak dpkg-deb lokalnie, pakuję przez SSH na iPadzie..."
fi

echo "3. Kopiowanie na iPada..."
scp "$IPA_PATH" root@$IP:/tmp/TelegramX12.ipa
scp -r /tmp/deb_build root@$IP:/tmp/deb_build

echo "4. Podpisywanie binarki i instalacja na iPadzie przez ldid..."
ssh root@$IP "
    cd /tmp/deb_build/Applications/TelegramX12.app
    # Usuń ewentualne stare podpisane atrybuty / podpisy
    codesign --remove-signature TelegramX12 2>/dev/null || true
    # Podpisz ldid-em (ad-hoc / platformowe; IPA z CI nie ma pliku entitlements)
    ldid -S TelegramX12
    
    # Przenieś do /Applications
    rm -rf /Applications/TelegramX12.app
    mv /tmp/deb_build/Applications/TelegramX12.app /Applications/
    
    # Uprawnienia
    chown -R root:wheel /Applications/TelegramX12.app
    chmod -R 755 /Applications/TelegramX12.app
    chmod +x /Applications/TelegramX12.app/TelegramX12
    
    uicache
    killall SpringBoard || true
"

echo "Sukces! Najnowszy build z GitHub CI został zainstalowany na iPadzie."
