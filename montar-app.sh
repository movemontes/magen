#!/bin/bash
# Compila tudo e monta o Magen.app (ícone da barra de menus) em build/.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="0.2"

swift build -c release
APP="build/Magen.app"
rm -rf "$APP"   # build/ só tem coisas geradas por este script
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MagenBar "$APP/Contents/MacOS/MagenBar"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.movemontes.magen.bar</string>
  <key>CFBundleName</key><string>Magen</string>
  <key>CFBundleDisplayName</key><string>Magen</string>
  <key>CFBundleExecutable</key><string>MagenBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Magen · MIT · Versículos: Bíblia Livre (BLIVRE) CC BY 4.0</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"   # assinatura local (sem conta Apple paga)

mkdir -p bin
cp .build/release/magend .build/release/magen bin/
cp -R "$APP" bin/
echo "Pronto: $APP e bin/"
