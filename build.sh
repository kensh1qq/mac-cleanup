#!/bin/bash
# Сборка «Чистка.app» (SwiftUI) и zip для отправки. Подпись ad-hoc: у друзей macOS спросит
# «Открыть всё равно» (Настройки → Конфиденциальность и безопасность).
# Апгрейд: Developer ID + notarytool — тогда откроется без предупреждений.
set -euo pipefail
cd "$(dirname "$0")"
./test.sh

APP="dist/Чистка.app"
rm -rf dist build && mkdir -p dist build "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14 App.swift -o build/arm64
swiftc -O -swift-version 5 -parse-as-library -target x86_64-apple-macos14 App.swift -o build/x86_64
lipo -create build/arm64 build/x86_64 -output "$APP/Contents/MacOS/Chistka"
cp cleanup "$APP/Contents/Resources/cleanup"

# иконка
swift icon.swift build/icon.png
mkdir build/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Чистка</string>
  <key>CFBundleDisplayName</key><string>Чистка</string>
  <key>CFBundleIdentifier</key><string>cc.kensh1qq.cleanup</string>
  <key>CFBundleExecutable</key><string>Chistka</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Чтобы очистить Корзину через Finder.</string>
</dict></plist>
PLIST

codesign --force --deep -s - "$APP"
ditto -c -k --keepParent "$APP" dist/Chistka.zip
echo "Готово: $APP и dist/Chistka.zip"
