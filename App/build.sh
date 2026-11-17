#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
configuration="${1:-release}"
swift build -c "$configuration"
products="$(swift build -c "$configuration" --show-bin-path)"
app="$root/dist/Float.app"
mkdir -p "$app/Contents/MacOS"
install -m 755 "$products/Float" "$app/Contents/MacOS/Float"
install -m 644 "$root/App/Info.plist" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf '%s\n' "$app"
