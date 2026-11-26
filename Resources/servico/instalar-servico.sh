#!/bin/bash
# Liga a proteção do Magen: instala o serviço que bloqueia os sites (roda como
# administrador) e o ícone da barra de menus. É chamado pelo próprio Magen.app
# (botão "Ligar a proteção") ou pelo instalar.command.
#
# Uso: instalar-servico.sh <caminho do Magen.app> [--from-app <pid do app>]
set -euo pipefail

APP_SRC="${1:?caminho do Magen.app}"
FROM_APP_PID=""
if [ "${2:-}" = "--from-app" ]; then FROM_APP_PID="${3:-}"; fi
[ "$(id -u)" -eq 0 ] || { echo "Precisa rodar como administrador."; exit 1; }

LABEL="io.github.movemontes.magen"
DIR="/Library/Application Support/Magen"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
BAR_LABEL="io.github.movemontes.magen.bar"
BAR_PLIST="/Library/LaunchAgents/$BAR_LABEL.plist"
APP="/Applications/Magen.app"
CONSOLE_USER=$(stat -f %Su /dev/console)
CONSOLE_UID=$(id -u "$CONSOLE_USER" 2>/dev/null || echo "")
USER_HOME=$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')

SERV="$APP_SRC/Contents/Resources/servico"
[ -x "$SERV/magend" ] && [ -x "$SERV/magen" ] || { echo "Não achei o serviço dentro de $APP_SRC"; exit 1; }

# 1) O app vai para /Applications (a versão antiga, se houver, vai para o Lixo).
if [ "$(cd "$APP_SRC" && pwd -P)" != "$(cd "$APP" 2>/dev/null && pwd -P || echo none)" ]; then
  if [ -d "$APP" ]; then
    mkdir -p "$USER_HOME/.Trash"
    mv "$APP" "$USER_HOME/.Trash/Magen antigo $(date +%Y%m%d%H%M%S).app"
  fi
  ditto "$APP_SRC" "$APP"
fi
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# 2) O serviço (para a versão antiga primeiro: ela devolve o DNS ao parar).
launchctl bootout "system/$LABEL" 2>/dev/null || true
sleep 1
mkdir -p "$DIR/bin"
install -m 755 -o root -g wheel "$APP/Contents/Resources/servico/magend" "$DIR/bin/magend"
install -m 755 -o root -g wheel "$APP/Contents/Resources/servico/magen" "$DIR/bin/magen"
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

# 3) O ícone da barra de menus abre sozinho ao entrar no Mac.
cat > "$BAR_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$BAR_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$APP/Contents/MacOS/MagenBar</string><string>--login</string></array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF
chown root:wheel "$BAR_PLIST"; chmod 644 "$BAR_PLIST"

# Fecha outras cópias do ícone (menos o app que pediu a instalação).
for pid in $(pgrep -f "Magen.app/Contents/MacOS/MagenBar" || true); do
  [ "$pid" = "$FROM_APP_PID" ] || kill "$pid" 2>/dev/null || true
done
if [ -z "$FROM_APP_PID" ] && [ -n "$CONSOLE_UID" ] && [ "$CONSOLE_USER" != "root" ]; then
  launchctl bootout "gui/$CONSOLE_UID/$BAR_LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$CONSOLE_UID" "$BAR_PLIST" 2>/dev/null || true
fi

# 4) Espera o serviço ligar e carregar as listas (até ~1 minuto).
for i in $(seq 1 45); do
  n=$(grep -o '"domains" : [0-9]*' "$DIR/state.json" 2>/dev/null | grep -o '[0-9]*$' || echo 0)
  if [ "${n:-0}" -gt 1000 ]; then break; fi
  sleep 2
done
echo "ok"
