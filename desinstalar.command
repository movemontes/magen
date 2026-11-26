#!/bin/bash
# Desliga e remove o Magen, devolvendo o DNS do Mac como era antes.
# Também serve de "socorro" se a internet parar de funcionar com o Magen.
# Nada é apagado de vez: tudo vai para o Lixo.
set -uo pipefail
cd "$(dirname "$0")"
if [ "$(id -u)" -ne 0 ]; then
  echo "Precisa da senha de administrador para remover o Magen."
  exec sudo /bin/bash "$0" "$@"
fi
SCRIPT="/Applications/Magen.app/Contents/Resources/servico/desinstalar-servico.sh"
[ -f "$SCRIPT" ] || SCRIPT="Resources/servico/desinstalar-servico.sh"
echo "Desligando o Magen…"
/bin/bash "$SCRIPT" --remove-app >/dev/null
echo "Magen removido. Os arquivos estão no Lixo."
