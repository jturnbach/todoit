#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${CONFIG:-release}
APP_NAME="TodoIt"
APP_BUNDLE="build/${APP_NAME}.app"
INFO_PLIST="Resources/Info.plist"

APP_BUILD_PATH=".build/app"
CLI_BUILD_PATH=".build/cli"

mkdir -p build

echo "→ Building ${APP_NAME} (${CONFIG})…"
swift build -c "${CONFIG}" \
    --product "${APP_NAME}" \
    --build-path "${APP_BUILD_PATH}" \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __info_plist \
    -Xlinker "${INFO_PLIST}"

echo "→ Building todoit CLI (${CONFIG})…"
swift build -c "${CONFIG}" \
    --product todoit \
    --build-path "${CLI_BUILD_PATH}"

APP_BIN_DIR="$(swift build -c "${CONFIG}" --build-path "${APP_BUILD_PATH}" --show-bin-path)"
CLI_BIN_DIR="$(swift build -c "${CONFIG}" --build-path "${CLI_BUILD_PATH}" --show-bin-path)"

echo "→ Assembling ${APP_BUNDLE}…"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${APP_BIN_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${INFO_PLIST}"              "${APP_BUNDLE}/Contents/Info.plist"
printf 'APPL????'             > "${APP_BUNDLE}/Contents/PkgInfo"

mkdir -p build/bin
cp "${CLI_BIN_DIR}/todoit" build/bin/todoit
chmod +x build/bin/todoit

# Ad-hoc sign so macOS accepts the bundle without quarantine fuss
codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true

echo ""
echo "✓ Built ${APP_BUNDLE}"
echo "✓ Built build/bin/todoit"
echo ""
echo "Run with:     open ${APP_BUNDLE}"
echo "Install with: ./install.sh"
