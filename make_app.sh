#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OUTPUT_DIR="${PLUGIN_SAFE_CLEANER_OUTPUT_DIR:-${SCRIPT_DIR}/dist}"
BUILD_DIR="${SCRIPT_DIR}/.build"
APP_NAME="PluginSafeCleaner"
APP_DIR="${OUTPUT_DIR}/${APP_NAME}.app"
MODULE_CACHE="${BUILD_DIR}/ModuleCache"
ARCHITECTURE="$(uname -m)"

mkdir -p "${OUTPUT_DIR}" "${MODULE_CACHE}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${SCRIPT_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${SCRIPT_DIR}/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

xcrun swiftc \
    -swift-version 5 \
    -O \
    -parse-as-library \
    -target "${ARCHITECTURE}-apple-macosx13.0" \
    -module-cache-path "${MODULE_CACHE}" \
    -o "${APP_DIR}/Contents/MacOS/${APP_NAME}" \
    "${SCRIPT_DIR}/Sources/PluginSafeCleaner/Models.swift" \
    "${SCRIPT_DIR}/Sources/PluginSafeCleaner/PlugInScanner.swift" \
    "${SCRIPT_DIR}/Sources/PluginSafeCleaner/QuarantineManager.swift" \
    "${SCRIPT_DIR}/Sources/PluginSafeCleaner/AppModel.swift" \
    "${SCRIPT_DIR}/Sources/PluginSafeCleaner/Views.swift" \
    "${SCRIPT_DIR}/Sources/PluginSafeCleaner/PluginSafeCleanerApp.swift" \
    -framework SwiftUI \
    -framework AppKit \
    -framework Foundation

codesign --force --deep --sign - "${APP_DIR}"
plutil -lint "${APP_DIR}/Contents/Info.plist"
codesign --verify --deep --strict "${APP_DIR}"

rm -f "${OUTPUT_DIR}/${APP_NAME}.zip" "${OUTPUT_DIR}/${APP_NAME}-Source.zip"
COPYFILE_DISABLE=1 ditto -c -k --keepParent "${APP_DIR}" "${OUTPUT_DIR}/${APP_NAME}.zip"
(
    cd "${SCRIPT_DIR:h}"
    /usr/bin/zip -qry "${OUTPUT_DIR}/${APP_NAME}-Source.zip" "${APP_NAME}" \
        -x "${APP_NAME}/.build/*" "${APP_NAME}/dist/*" "${APP_NAME}/.git/*" \
        "${APP_NAME}/.DS_Store" "${APP_NAME}/**/.DS_Store"
)

echo "Built ${APP_DIR}"
