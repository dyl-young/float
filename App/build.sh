#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
configuration="${1:-release}"
swift build -c "$configuration"
products="$(swift build -c "$configuration" --show-bin-path)"
app="$root/dist/Float.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 755 "$products/Float" "$app/Contents/MacOS/Float"
install -m 644 "$root/App/Info.plist" "$app/Contents/Info.plist"
install -m 644 "$root/App/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
install -m 644 "$root/design/assets/providers/antigravity.png" "$app/Contents/Resources/antigravity.png"
mkdir -p "$app/Contents/Resources/languages"
install -m 644 "$root"/design/assets/languages/*.svg "$root/design/assets/languages/LICENSE.md" "$app/Contents/Resources/languages/"
codesign --force --sign - "$app"
printf '%s\n' "$app"
