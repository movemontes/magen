#!/bin/bash
# Desliga e remove o Magen, devolvendo o DNS do Mac como era antes.
# Também serve de "socorro" se a internet parar de funcionar com o Magen.
set -uo pipefail

LABEL="io.github.movemontes.magen"
DIR="/Library/Application Support/Magen"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

if [ "$(id -u)" -ne 0 ]; then
  echo "Precisa da senha de administrador para remover o Magen."
  exec sudo /bin/bash "$0" "$@"
fi

echo "Desligando o Magen…"
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
    echo "  DNS de \"$svc\" devolvido: $old"
  fi
done

# Nada é apagado de vez: os arquivos vão para o Lixo de quem pediu a remoção.
USER_HOME=$(dscl . -read "/Users/${SUDO_USER:-$(stat -f %Su /dev/console)}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
TRASH="${USER_HOME:-/var/root}/.Trash/Magen removido $(date +%Y-%m-%d_%H%M%S)"
mkdir -p "$TRASH"
[ -f "$PLIST" ] && mv "$PLIST" "$TRASH/"
[ -d "$DIR" ] && mv "$DIR" "$TRASH/Magen (dados)"
[ -L /usr/local/bin/magen ] && rm /usr/local/bin/magen   # só um atalho
[ -f /Library/Logs/Magen.log ] && mv /Library/Logs/Magen.log "$TRASH/"
[ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER" "$TRASH" 2>/dev/null

dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null || true
echo "Magen removido. Os arquivos estão no Lixo, em: $(basename "$TRASH")"
