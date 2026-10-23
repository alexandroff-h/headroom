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
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)"
printf 'Toolchain: %s (macOS %s SDK)\n' \
    "$(xcrun swift --version 2>/dev/null | head -1 | sed -E 's/.*Apple Swift version ([0-9.]+).*/Swift \1/')" \
    "$SDK_VERSION"

# AppKit decides which era of controls to draw from the SDK version recorded in
# the binary, not from the OS running it — that is how Apple ships an
# appearance change without redrawing every app already in the field. Build an
# app against the macOS 14 SDK and macOS 26 will keep serving it macOS 14
# controls forever, Liquid Glass included.
#
# SwiftPM records the *deployment target* as the SDK version, so Headroom was
# shipping `minos 14.0 / sdk 14.0` and opting itself out of the system
# materials it is supposed to inherit. Every other Mac app links the newest SDK
# and deploys back; this says the same thing in the one dialect ld still
# accepts (`-sdk_version` is obsolete). check-compat.sh asserts both halves.
BUILD_FLAGS=(
    -c release
    --disable-sandbox
    --cache-path /private/tmp/headroom-package-cache
    -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION"
)

# `glassEffect` is a macOS 26 SDK symbol, and @available cannot conjure a
# symbol the compiler never saw. An older SDK — the Command Line Tools ship
# one — still builds a working app; it builds the pre-26 half of every control
# and nothing else. The runtime check stays in the source regardless, because
# this binary deploys to macOS 14.
if [[ "${SDK_VERSION%%.*}" -ge 26 ]]; then
    BUILD_FLAGS+=(-Xswiftc -DLIQUID_GLASS)
    printf 'Liquid Glass: compiled in (macOS 26+ at runtime)\n'
else
    printf 'Liquid Glass: not in this SDK, building the pre-26 controls only\n'
fi

export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
xcrun swift build "${BUILD_FLAGS[@]}"

BINARY_DIRECTORY="$(xcrun swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
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
