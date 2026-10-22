#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Any toolchain with a macOS 15 SDK or newer will do. Headroom deploys to
# macOS 14, so the SDK only decides which niceties the system draws for you
# (the toolbar tabs are Liquid Glass on macOS 26, a plain segmented control
# before that). Set DEVELOPER_DIR yourself to pin a specific one.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
printf 'Toolchain: %s (macOS %s SDK)\n' \
    "$(xcrun swift --version 2>/dev/null | head -1 | sed -E 's/.*Apple Swift version ([0-9.]+).*/Swift \1/')" \
    "$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)"

export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
xcrun swift build -c release --disable-sandbox --cache-path /private/tmp/headroom-package-cache

BINARY_DIRECTORY="$(xcrun swift build -c release --disable-sandbox --cache-path /private/tmp/headroom-package-cache --show-bin-path)"
APP_DIRECTORY="$PROJECT_ROOT/dist/Headroom.app"
mkdir -p "$APP_DIRECTORY/Contents/MacOS" "$APP_DIRECTORY/Contents/Resources"
cp "$BINARY_DIRECTORY/Headroom" "$APP_DIRECTORY/Contents/MacOS/Headroom"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_DIRECTORY/Contents/Info.plist"

ICON_DIRECTORY="$PROJECT_ROOT/.build/Headroom.iconset"
mkdir -p "$ICON_DIRECTORY"
xcrun swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" "$PROJECT_ROOT/scripts/make-icon.swift" "$PROJECT_ROOT/.build/Headroom-1024.png"
for ICON_SIZE in 16 32 128 256 512; do
    sips -z "$ICON_SIZE" "$ICON_SIZE" "$PROJECT_ROOT/.build/Headroom-1024.png" --out "$ICON_DIRECTORY/icon_${ICON_SIZE}x${ICON_SIZE}.png" >/dev/null
    RETINA_SIZE=$((ICON_SIZE * 2))
    sips -z "$RETINA_SIZE" "$RETINA_SIZE" "$PROJECT_ROOT/.build/Headroom-1024.png" --out "$ICON_DIRECTORY/icon_${ICON_SIZE}x${ICON_SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_DIRECTORY" -o "$APP_DIRECTORY/Contents/Resources/Headroom.icns"
codesign --force --sign - "$APP_DIRECTORY"
codesign --verify --strict "$APP_DIRECTORY"
printf 'Built %s\n' "$APP_DIRECTORY"
printf 'Open with: open "%s"\n' "$APP_DIRECTORY"
