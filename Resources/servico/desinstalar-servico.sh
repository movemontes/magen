#!/bin/bash
# Desliga e remove a proteção do Magen, devolvendo o DNS do Mac como era antes.
# Nada é apagado de vez: os arquivos vão para o Lixo de quem está usando o Mac.
#
# Uso: desinstalar-servico.sh [--from-app <pid do app>] [--remove-app]
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Precisa rodar como administrador."; exit 1; }

FROM_APP_PID=""; REMOVE_APP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from-app) FROM_APP_PID="${2:-}"; shift ;;
    --remove-app) REMOVE_APP=1 ;;
  esac
  shift
done

LABEL="io.github.movemontes.magen"
DIR="/Library/Application Support/Magen"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
BAR_LABEL="io.github.movemontes.magen.bar"
BAR_PLIST="/Library/LaunchAgents/$BAR_LABEL.plist"
CONSOLE_USER=$(stat -f %Su /dev/console)
CONSOLE_UID=$(id -u "$CONSOLE_USER" 2>/dev/null || echo "")

# O serviço devolve o DNS original ao parar.
launchctl bootout "system/$LABEL" 2>/dev/null || true
sleep 2

# Garantia: se o DNS ainda aponta para o Magen, devolve o que havia antes.
SAVED="$DIR/dns-anterior.txt"
networksetup -listallnetworkservices | tail -n +2 | grep -v '^\*' | while IFS= read -r svc; do
  [ -z "$svc" ] && continue
  if [ "$(networksetup -getdnsservers "$svc")" = "127.0.0.1" ]; then
    old=""
    [ -f "$SAVED" ] && old=$(awk -F'\t' -v s="$svc" '$1==s { $1=""; sub(/^ /,""); print }' "$SAVED")
    [ -z "$old" ] && old="Empty"
    # shellcheck disable=SC2086
    networksetup -setdnsservers "$svc" $old
  fi
done

if [ -z "$FROM_APP_PID" ] && [ -n "$CONSOLE_UID" ]; then
  launchctl bootout "gui/$CONSOLE_UID/$BAR_LABEL" 2>/dev/null || true
fi
for pid in $(pgrep -f "Magen.app/Contents/MacOS/MagenBar" || true); do
  [ "$pid" = "$FROM_APP_PID" ] || kill "$pid" 2>/dev/null || true
done

USER_HOME=$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
TRASH="${USER_HOME:-/var/root}/.Trash/Magen removido $(date +%Y-%m-%d_%H%M%S)"
mkdir -p "$TRASH"
[ -f "$PLIST" ] && mv "$PLIST" "$TRASH/"
[ -f "$BAR_PLIST" ] && mv "$BAR_PLIST" "$TRASH/magen-icone.plist"
[ -d "$DIR" ] && mv "$DIR" "$TRASH/Magen (dados)"
[ -L /usr/local/bin/magen ] && rm /usr/local/bin/magen   # só um atalho
[ -f /Library/Logs/Magen.log ] && mv /Library/Logs/Magen.log "$TRASH/"
[ -n "$REMOVE_APP" ] && [ -d /Applications/Magen.app ] && mv /Applications/Magen.app "$TRASH/"
chown -R "$CONSOLE_USER" "$TRASH" 2>/dev/null

dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null || true
echo "ok"
