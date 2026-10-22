#!/bin/bash
# Asserts that a built Headroom.app still deploys as far back as it claims.
# Run after scripts/build-app.sh. Exits non-zero if anything regressed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$ROOT/dist/Headroom.app/Contents/MacOS/Headroom"
PLIST="$ROOT/dist/Headroom.app/Contents/Info.plist"
EXPECTED="14.0"
status=0

[[ -f "$BINARY" ]] || { echo "No build at $BINARY. Run scripts/build-app.sh first."; exit 1; }

minos=$(otool -l "$BINARY" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')
sdk=$(otool -l "$BINARY" | awk '/LC_BUILD_VERSION/{f=1} f&&/[^n]sdk/{print $2; exit}')
plist=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST" 2>/dev/null || echo "missing")

printf 'Mach-O minimum   %s\n' "$minos"
printf 'Built against    macOS %s SDK\n' "$sdk"
printf 'Info.plist says  %s\n' "$plist"

[[ "$minos" == "$EXPECTED" ]] || { echo "FAIL: Mach-O minimum is $minos, expected $EXPECTED"; status=1; }
[[ "$plist" == "$EXPECTED" ]] || { echo "FAIL: Info.plist minimum is $plist, expected $EXPECTED"; status=1; }

# Weak-linked SwiftUI entry points are normal: Swift emits them with an
# availability check and a fallback. They are listed so a new one gets noticed
# and traced rather than assumed safe.
echo
echo "Weak-linked SwiftUI entry points (each must be behind an availability check):"
nm -mu "$BINARY" 2>/dev/null | grep "weak external" | grep "from SwiftUI" \
  | sed -E 's/.*external _(\$[A-Za-z0-9_$]+).*/  \1/' \
  | while read -r sym; do printf '  %s\n' "$(xcrun swift demangle --compact "${sym# }" 2>/dev/null || echo "${sym# }")"; done

echo
[[ $status -eq 0 ]] && echo "OK: deploys to macOS $EXPECTED and later."
exit $status
