#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
configuration="${1:-release}"

# The Command Line Tools can ship an SDK whose SwiftUI needs a macro plugin they don't include
# (macOS 27 declares @State as a SwiftUIMacros macro). Fall back to the newest SDK without it.
developer="$(xcode-select -p)"
if [[ -z "${SDKROOT:-}" && "$developer" == */CommandLineTools \
      && ! -e "$developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]]; then
    for sdk in $(ls -d "$developer"/SDKs/MacOSX[0-9]*.sdk | sort -rV); do
        if ! grep -qs 'type: "StateMacro"' \
            "$sdk"/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/*-apple-macos.swiftinterface; then
            export SDKROOT="$sdk"
            echo "Building against $(basename "$sdk"): the newer SDK needs SwiftUI macros the Command Line Tools lack" >&2
            break
        fi
    done
fi

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
