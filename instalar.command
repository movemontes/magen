#!/bin/bash
# Instala o Magen neste Mac. Dê dois cliques ou rode no Terminal.
# Vai pedir a senha de administrador do Mac (ela não é guardada).
set -euo pipefail
cd "$(dirname "$0")"

LABEL="io.github.movemontes.magen"
DIR="/Library/Application Support/Magen"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

if [ -x "bin/magend" ]; then SRC="bin"
elif [ -x ".build/release/magend" ]; then SRC=".build/release"
else
  echo "Não achei o programa. Se você baixou o código, rode primeiro: swift build -c release"
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "O Magen precisa da senha de administrador para proteger o Mac inteiro."
  exec sudo /bin/bash "$0" "$@"
fi

echo "Instalando o Magen…"
# Se já estiver instalado, para a versão antiga primeiro (ela devolve o DNS ao parar).
launchctl bootout "system/$LABEL" 2>/dev/null || true
sleep 1

mkdir -p "$DIR/bin"
install -m 755 -o root -g wheel "$SRC/magend" "$DIR/bin/magend"
install -m 755 -o root -g wheel "$SRC/magen" "$DIR/bin/magen"
xattr -dr com.apple.quarantine "$DIR/bin" 2>/dev/null || true
chown root:wheel "$DIR"; chmod 755 "$DIR"
mkdir -p /usr/local/bin
ln -sf "$DIR/bin/magen" /usr/local/bin/magen

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$DIR/bin/magend</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>StandardOutPath</key><string>/Library/Logs/Magen.log</string>
  <key>StandardErrorPath</key><string>/Library/Logs/Magen.log</string>
</dict>
</plist>
EOF
chown root:wheel "$PLIST"; chmod 644 "$PLIST"
: > /Library/Logs/Magen.log
launchctl bootstrap system "$PLIST"

echo "Esperando o Magen ligar e baixar as listas (pode levar até 1 minuto)…"
for i in $(seq 1 45); do
  n=$(grep -o '"domains" : [0-9]*' "$DIR/state.json" 2>/dev/null | grep -o '[0-9]*$' || echo 0)
  if [ "${n:-0}" -gt 1000 ]; then break; fi
  sleep 2
done
echo
/usr/local/bin/magen status || true
echo
/usr/local/bin/magen testar pornhub.com || true
/usr/local/bin/magen testar google.com || true
echo
echo "Pronto. Para desligar e remover: dê dois cliques em desinstalar.command"
