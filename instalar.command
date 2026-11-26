#!/bin/bash
# Instala o Magen neste Mac. Dê dois cliques ou rode no Terminal.
# Vai pedir a senha de administrador do Mac (ela não é guardada).
set -euo pipefail
cd "$(dirname "$0")"

LABEL="io.github.movemontes.magen"
DIR="/Library/Application Support/Magen"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

BAR_LABEL="io.github.movemontes.magen.bar"
BAR_PLIST="/Library/LaunchAgents/$BAR_LABEL.plist"

if [ -x "bin/magend" ] && [ -d "bin/Magen.app" ]; then SRC="bin"
else
  echo "Não achei o programa. Se você baixou o código, rode primeiro: ./montar-app.sh"
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "O Magen precisa da senha de administrador para proteger o Mac inteiro."
  exec sudo /bin/bash "$0" "$@"
fi

# A Retransmissão Privada do iCloud precisa estar desligada: com ela ligada,
# apps como o Claude ficam sem internet quando o Magen está ativo.
CONSOLE_USER0=$(stat -f %Su /dev/console)
RELAY=$(sudo -u "$CONSOLE_USER0" "$SRC/Magen.app/Contents/MacOS/MagenBar" --relay-status 2>/dev/null || echo desconhecida)
while [ "$RELAY" = "ligada" ]; do
  echo
  echo "⚠️  A Retransmissão Privada do iCloud está LIGADA."
  echo "   Com ela ligada, apps como o Claude ficam sem internet quando o Magen está ativo."
  echo "   Desligue em: Ajustes do Sistema › (seu nome) › iCloud › Retransmissão Privada."
  sudo -u "$CONSOLE_USER0" open "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings:icloud" 2>/dev/null || true
  read -r -p "   Depois de desligar, aperte Enter (ou digite c e Enter para continuar mesmo assim): " ans
  [ "$ans" = "c" ] && break
  sleep 2
  RELAY=$(sudo -u "$CONSOLE_USER0" "$SRC/Magen.app/Contents/MacOS/MagenBar" --relay-status 2>/dev/null || echo desconhecida)
done

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

# Ícone na barra de menus: vai para /Applications e abre sozinho ao entrar no Mac.
CONSOLE_USER=$(stat -f %Su /dev/console)
CONSOLE_UID=$(id -u "$CONSOLE_USER" 2>/dev/null || echo "")
if [ -n "$CONSOLE_UID" ]; then launchctl bootout "gui/$CONSOLE_UID/$BAR_LABEL" 2>/dev/null || true; fi
pkill -f "Magen.app/Contents/MacOS/MagenBar" 2>/dev/null || true
if [ -d /Applications/Magen.app ]; then
  OLD_TRASH="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory | awk '{print $2}')/.Trash"
  mv /Applications/Magen.app "$OLD_TRASH/Magen antigo $(date +%Y%m%d%H%M%S).app"
fi
cp -R "$SRC/Magen.app" /Applications/Magen.app
xattr -dr com.apple.quarantine /Applications/Magen.app 2>/dev/null || true
cat > "$BAR_PLIST" <<PLISTEND
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$BAR_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/Applications/Magen.app/Contents/MacOS/MagenBar</string><string>--login</string></array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
PLISTEND
chown root:wheel "$BAR_PLIST"; chmod 644 "$BAR_PLIST"
if [ -n "$CONSOLE_UID" ] && [ "$CONSOLE_USER" != "root" ]; then
  launchctl bootstrap "gui/$CONSOLE_UID" "$BAR_PLIST" 2>/dev/null || true
fi

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
