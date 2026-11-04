#!/bin/bash
# Compile betterSOUND.app (macOS 13 ou plus récent).
set -euo pipefail
cd "$(dirname "$0")"

APP="betterSOUND.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>betterSOUND</string>
    <key>CFBundleDisplayName</key><string>betterSOUND</string>
    <key>CFBundleIdentifier</key><string>local.bettersound</string>
    <key>CFBundleExecutable</key><string>betterSOUND</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>fr</string>
</dict>
</plist>
PLIST

# Icône de l'app (icon.png 1024×1024 -> AppIcon.icns)
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Logo affiché dans la fenêtre
cp logo.png "$APP/Contents/Resources/logo.png"

# Binaire universel (Apple Silicon + Intel)
BUILD="$(mktemp -d)"
for arch in arm64 x86_64; do
    swiftc -O -parse-as-library \
        -target "$arch-apple-macos13.0" \
        main.swift -o "$BUILD/betterSOUND-$arch"
done
lipo -create "$BUILD"/betterSOUND-* -output "$APP/Contents/MacOS/betterSOUND"

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
touch "$APP"   # force le Finder à rafraîchir l'icône

echo "✅ $APP créé. Lancez-le avec : open $APP"
echo "   (ou glissez-le dans /Applications)"
