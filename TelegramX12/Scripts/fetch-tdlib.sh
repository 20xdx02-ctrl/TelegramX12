#!/usr/bin/env bash
#
# Downloads the prebuilt TDLibFramework (TDLib 1.8.69) static framework and
# installs the iOS arm64 slice into Vendor/. The archive is large (~355 MB),
# but only the device slice is copied into the project.
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${PROJECT_DIR}/Vendor"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

URL="https://github.com/Swiftgram/TDLibFramework/releases/download/1.8.69-4c6377aa/TDLibFramework.zip"
EXPECTED_SHA256="c86ca527be4adb4e2562693176b28a74290a86e9a55988af5c169420c6b77d49"

echo "Downloading TDLibFramework.zip…"
curl -fL --retry 3 -o "${TMP_DIR}/TDLibFramework.zip" "${URL}"

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA256="$(sha256sum "${TMP_DIR}/TDLibFramework.zip" | awk '{print $1}')"
else
    ACTUAL_SHA256="$(shasum -a 256 "${TMP_DIR}/TDLibFramework.zip" | awk '{print $1}')"
fi
if [ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]; then
    echo "Checksum mismatch: expected ${EXPECTED_SHA256}, got ${ACTUAL_SHA256}" >&2
    exit 1
fi

echo "Extracting iOS arm64 slice…"
unzip -q "${TMP_DIR}/TDLibFramework.zip" \
    'TDLibFramework.xcframework/ios-arm64/*' -d "${TMP_DIR}"

mkdir -p "${VENDOR_DIR}"
rm -rf "${VENDOR_DIR}/TDLibFramework.framework"
cp -R "${TMP_DIR}/TDLibFramework.xcframework/ios-arm64/TDLibFramework.framework" "${VENDOR_DIR}/"

echo "Installed ${VENDOR_DIR}/TDLibFramework.framework"
