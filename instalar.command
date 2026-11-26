#!/bin/bash
# Instala o Magen neste Mac. Dê dois cliques ou rode no Terminal.
# Vai pedir a senha de administrador do Mac (ela não é guardada).
set -euo pipefail
cd "$(dirname "$0")"

# (Para quem baixou o código. Quem baixou o .dmg só precisa abrir o Magen.app.)
if [ -d "bin/Magen.app" ]; then SRC="bin"
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
/bin/bash "$SRC/Magen.app/Contents/Resources/servico/instalar-servico.sh" "$PWD/$SRC/Magen.app" >/dev/null
echo
/usr/local/bin/magen status || true
echo
/usr/local/bin/magen testar pornhub.com || true
/usr/local/bin/magen testar google.com || true
echo
echo "Pronto. Para desligar e remover: dê dois cliques em desinstalar.command"
