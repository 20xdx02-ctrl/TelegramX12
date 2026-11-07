#!/usr/bin/env bash
#
# Creates an unsigned IPA from the Theos build output.
# Useful for re-signing with Sideloadly/AltStore or a developer certificate.
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-${PROJECT_DIR}/.theos/obj/debug/TelegramX12.app}"
OUTPUT_DIR="${PROJECT_DIR}/packages"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

if [ ! -d "${APP}" ]; then
    echo "App bundle not found at ${APP}. Run 'make' first." >&2
    exit 1
fi
if [ ! -f "${APP}/Info.plist" ]; then
    echo "${APP}/Info.plist is missing. Run 'make' first." >&2
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"
mkdir -p "${WORK_DIR}/Payload"
cp -R "${APP}" "${WORK_DIR}/Payload/TelegramX12.app"
rm -rf "${WORK_DIR}/Payload/TelegramX12.app/TelegramX12.dSYM"

( cd "${WORK_DIR}" && zip -qry "${OUTPUT_DIR}/TelegramX12-unsigned.ipa" Payload )
echo "Created ${OUTPUT_DIR}/TelegramX12-unsigned.ipa"
