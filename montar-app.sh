#!/bin/bash
# Compila tudo e monta o Magen.app (ícone da barra de menus) em build/.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="1.2"

swift build -c release
APP="build/Magen.app"
rm -rf "$APP"   # build/ só tem coisas geradas por este script
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MagenBar "$APP/Contents/MacOS/MagenBar"
cp -R Resources/fonts "$APP/Contents/Resources/fonts"   # Archivo (SIL OFL)
# Clash Grotesk (ITF FFL): pode ir dentro do app, mas não no repositório público.
# Vem de fora do Git; sem ela, o app usa a Archivo.
for dir in "/Volumes/Dados/PautaCodigo/fontes-privadas" "$HOME/Library/Fonts"; do
  if [ -f "$dir/ClashGrotesk-Medium.otf" ] && [ -f "$dir/ClashGrotesk-Semibold.otf" ]; then
    cp "$dir/ClashGrotesk-Medium.otf" "$dir/ClashGrotesk-Semibold.otf" "$APP/Contents/Resources/fonts/"
    break
  fi
done
# O serviço que bloqueia (vai junto, o app instala sozinho)
mkdir -p "$APP/Contents/Resources/servico"
cp .build/release/magend .build/release/magen Resources/servico/*.sh "$APP/Contents/Resources/servico/"
chmod 755 "$APP/Contents/Resources/servico/"*
# Ícone do app (Dock e Finder), desenhado pelo próprio Magen
# (desenho em Resources/icone: broquel com M; refaça com desenhar_icone.py)
rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
for sz in 16 32 128 256 512; do
  sips -z $sz $sz Resources/icone/icone-1024.png --out "build/AppIcon.iconset/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) Resources/icone/icone-1024.png --out "build/AppIcon.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/icone/icone-1024.png Resources/icone/escudo-512.png Resources/icone/mateus.png "$APP/Contents/Resources/"
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
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHumanReadableCopyright</key><string>Magen · MIT · Versículos: Bíblia Livre (BLIVRE) CC BY 4.0</string>
</dict>
</plist>
EOF
codesign --force --deep --sign - "$APP"   # assinatura local (sem conta Apple paga)

mkdir -p bin
cp .build/release/magend .build/release/magen bin/
rm -rf bin/Magen.app   # bin/ só tem cópias geradas por este script
cp -R "$APP" bin/
# Arquivo para baixar: Magen.app + atalho para Aplicativos, num .dmg
rm -rf build/dmg && mkdir -p build/dmg dist
ditto "$APP" build/dmg/Magen.app
ln -s /Applications build/dmg/Aplicativos
rm -f "dist/Magen-$VERSION-mac.dmg"
hdiutil create -quiet -volname "Magen" -srcfolder build/dmg -fs HFS+ -format UDZO "dist/Magen-$VERSION-mac.dmg"
cp "dist/Magen-$VERSION-mac.dmg" dist/Magen-mac.dmg
echo "Pronto: $APP, bin/ e dist/Magen-$VERSION-mac.dmg"
