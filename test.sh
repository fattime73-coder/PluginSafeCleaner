#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
BUILD_DIR="${SCRIPT_DIR}/.build/tests"
ARCHITECTURE="$(uname -m)"

mkdir -p "${BUILD_DIR}/ScannerModuleCache" "${BUILD_DIR}/BatchModuleCache"

xcrun swiftc \
    -swift-version 5 \
    -target "${ARCHITECTURE}-apple-macosx13.0" \
    -module-cache-path "${BUILD_DIR}/ScannerModuleCache" \
    "${SCRIPT_DIR}/Sources/PluginSafeCleaner/Models.swift" \
    "${SCRIPT_DIR}/Sources/PluginSafeCleaner/PlugInScanner.swift" \
    "${SCRIPT_DIR}/Tests/ScannerSmoke/main.swift" \
    -o "${BUILD_DIR}/scanner-smoke"

xcrun swiftc \
    -swift-version 5 \
    -target "${ARCHITECTURE}-apple-macosx13.0" \
    -module-cache-path "${BUILD_DIR}/BatchModuleCache" \
    "${SCRIPT_DIR}/Sources/PluginSafeCleaner/Models.swift" \
    "${SCRIPT_DIR}/Sources/PluginSafeCleaner/QuarantineManager.swift" \
    "${SCRIPT_DIR}/Tests/BatchMoveSmoke/main.swift" \
    -o "${BUILD_DIR}/batch-move-smoke" \
    -framework AppKit \
    -framework Foundation

"${BUILD_DIR}/scanner-smoke"
"${BUILD_DIR}/batch-move-smoke"

echo "All tests passed"
