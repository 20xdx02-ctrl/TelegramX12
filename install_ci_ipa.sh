#!/bin/bash
# Instaluje świeży IPA z CI na jailbroken iPad przez ssh.
# Naprawiona wersja convert_ipa.sh: transfer tar-em + weryfikacja md5 binarki
# przed instalacją (wcześniej scp katalogu przerywał się / tracił dane).
# Użycie: ./install_ci_ipa.sh [ścieżka-do-ipa]
set -e

IP="192.168.18.157"
IPA="${1:-TelegramX12-unsigned.ipa}"

if [ ! -f "$IPA" ]; then
    echo "Nie znaleziono pliku IPA: $IPA"
    exit 1
fi

echo "1. Rozpakowanie IPA lokalnie..."
rm -rf /tmp/ipa_install
mkdir -p /tmp/ipa_install
python3 -c "import zipfile; zipfile.ZipFile('$IPA').extractall('/tmp/ipa_install')"

BIN_HASH=$(md5sum /tmp/ipa_install/Payload/TelegramX12.app/TelegramX12 | cut -d' ' -f1)
echo "   lokalny md5 binarki: $BIN_HASH"

echo "2. Czyszczenie docelowego /tmp/deb_build/Applications..."
ssh root@$IP "rm -rf /tmp/deb_build/Applications && mkdir -p /tmp/deb_build/Applications" &
LOCAL_PID=$!
wait $LOCAL_PID

echo "3. Transfer tar-em przez ssh (z pominięciem scp -r)..."
tar -C /tmp/ipa_install/Payload -c TelegramX12.app | ssh root@$IP "tar -C /tmp/deb_build/Applications -x" &

TAR_PID=$!
wait $TAR_PID

echo "4. Weryfikacja md5 binarki na urządzeniu..."
DEVICE_HASH=$(ssh root@$IP "md5sum /tmp/deb_build/Applications/TelegramX12.app/TelegramX12 | cut -d' ' -f1")
echo "   urządzenie md5: $DEVICE_HASH"
if [ "$BIN_HASH" != "$DEVICE_HASH" ]; then
    echo "BŁĘDŁA: md5 się nie zgadza, nie instaluję."
    exit 1
fi

echo "5. Podpisanie ldid + instalacja do /Applications + uicache + respring..."
ssh root@$IP "
    set -e
    APP=/tmp/deb_build/Applications/TelegramX12.app
    ldid -S \$APP/TelegramX12
    rm -rf /Applications/TelegramX12.app
    mv \$APP /Applications/
    chown -R root:wheel /Applications/TelegramX12.app
    chmod -R 755 /Applications/TelegramX12.app
    uicache
    killall SpringBoard || true
"

echo "OK: zainstalowano $IPA na root@$IP."
