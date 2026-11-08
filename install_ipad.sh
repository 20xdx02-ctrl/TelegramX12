#!/bin/bash
set -e

IP="192.168.18.157"
USER="root"
DEB_PATH="TelegramX12/packages/com.telegramx12.app_1.0.0-5+debug_iphoneos-arm.deb"

if [ ! -f "$DEB_PATH" ]; then
    echo "Nie znaleziono paczki .deb w $DEB_PATH. Upewnij się, że została zbudowana."
    exit 1
fi

echo "1. Kopiowanie paczki .deb na iPada ($IP)..."
scp "$DEB_PATH" "$USER@$IP:/tmp/telegramx12.deb"

echo "2. Instalacja paczki za pomocą dpkg na iPadzie..."
ssh "$USER@$IP" "dpkg -i /tmp/telegramx12.deb"

echo "3. Odświeżenie ikon (uicache) i restart SpringBoard..."
ssh "$USER@$IP" "uicache && killall SpringBoard || true"

echo "Instalacja zakończona pomyślnie!"
