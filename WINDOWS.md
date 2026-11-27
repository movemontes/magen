# Magen: montar a versão de Windows

Este guia é para o Claude Code no notebook com Windows. O Magen nasceu no Mac, em Swift, na pasta `Sources/`. As peças do Mac não existem no Windows. Por isso a versão de Windows foi **reescrita em Python**, na pasta `windows/`, com a mesma lógica, o mesmo visual e os mesmos textos. Ela foi escrita e testada no Mac, mas **nunca rodou num Windows de verdade**.

## Regras

1. Fale em português simples: o dono não é programador. Use pronomes neutros.
2. **Nunca simule cliques ou arrastos no mouse real da pessoa.** No Windows, um teste assim já deixou o botão do mouse preso no Treco.
3. Diga claramente o que foi testado de verdade e o que depende de um teste manual.
4. **Não quebre o Mac.** Tudo de Windows fica em `windows/`. Não mexa em `Sources/`, `Package.swift` nem `montar-app.sh`, a não ser que o dono peça.
5. Nunca apague nem mova os originais da pessoa. O que for apagado vai para a Lixeira.
6. Peça antes de publicar qualquer coisa: push, release ou site.
7. **Cuidado com a internet do notebook.** O Magen muda o DNS do Windows. Se algo der errado com o serviço ligado, a internet pode parar. O conserto está em "Se a internet parar", mais abaixo. Teste primeiro com `--no-system-dns`.

## Como funciona no Windows (diferente do Mac)

| | Mac | Windows |
|---|---|---|
| Porteiro DNS | `magend`, daemon do launchd | serviço do Windows "Magen" (`Magen.exe --service`, pywin32), como SYSTEM |
| Troca do DNS | `networksetup` | `netsh` em todas as conexões, IPv4 → `127.0.0.1` e IPv6 → `::1`; lê o registro a cada 30 s |
| Aviso de bloqueio | notificação Darwin | recado UDP local: o serviço manda `blocked` para `127.0.0.1:53531` |
| Pedido de recarga ou atualização | sinais e notificação | recado UDP para `127.0.0.1:53530` (`reload`, `update`; `update` no máximo a cada 5 min) |
| Senha | janela do macOS | "Permitir?" do Windows (UAC): `Magen.exe --admin <comando>` |
| Ícone | barra de menus | perto do relógio (pystray) |
| Dados | `/Library/Application Support/Magen` | `C:\ProgramData\Magen` (só SYSTEM e administradores escrevem) |
| Ajustes da pessoa | UserDefaults | `%APPDATA%\Magen\prefs.json` |
| Atualização | `Magen-mac.dmg` | `Magen-<versão>-win-setup.exe`, rodado com `/SILENT` |

Um programa só, `Magen.exe`, faz tudo. Veja os modos em `windows/magen.py`.

O instalador **pede administrador**, ao contrário do Treco. Um bloqueador precisa disso, senão qualquer um o desligaria. Ele instala em Arquivos de Programas, cria e liga o serviço com reinício automático em 2 s se cair, e põe o ícone para abrir com o Windows em todas as contas. A desinstalação pede a frase "quero remover a proteção", a mesma do Mac.

## Preparar o notebook

1. Instale o **Python 3.12** do python.org, marcando "Add python.exe to PATH".
2. Instale o **Git** e o **Inno Setup 6** (jrsoftware.org).
3. No terminal, dentro de `windows\` do projeto, rode:
   ```
   py -3.12 -m venv .venv
   .venv\Scripts\pip install -r requirements.txt
   ```
4. A fonte **Clash Grotesk** não vai no GitHub por causa da licença. Copie `ClashGrotesk-Medium.otf` e `ClashGrotesk-Semibold.otf` do Mac para `windows\fontes-privadas\`. No Mac, elas ficam em `/Volumes/Dados/PautaCodigo/fontes-privadas` ou em `~/Library/Fonts`. Sem ela, o app usa a Segoe UI. A pasta já está no `.gitignore`.

Nada mais fica fora do GitHub. As listas de sites são baixadas pelo próprio serviço.

## Testar pelo código (antes de montar)

Primeiro **sem mexer no DNS**, numa porta de teste:
```
.venv\Scripts\python magen.py --foreground --port 53535 --no-system-dns
```
Em outro terminal:
```
nslookup pornhub.com 127.0.0.1 -port=53535     (deve dizer "Non-existent domain")
nslookup google.com 127.0.0.1 -port=53535      (deve dar um endereço)
```
`nslookup` pode não aceitar `-port` em todas as versões. Se não aceitar, use:
```
.venv\Scripts\python -c "import sys; sys.path.insert(0,'.'); from magen_win import core; print(core.dns_check('pornhub.com', 53535), core.dns_check('google.com', 53535))"
```
O resultado deve ser `True False`.

Depois o app, com as variáveis apontando para a porta de teste: `set MAGEN_PORT=53535` e `.venv\Scripts\python magen.py`.

## Montar

```
.venv\Scripts\python build_win.py
```
O resultado sai em `windows\dist\Magen\Magen.exe` e `windows\dist\Magen-<versão>-win-setup.exe`. A versão fica em `windows\magen_win\version.py` e deve ser o mesmo número do Mac (`montar-app.sh`).

Para publicar, sempre com o OK do dono: suba o `Magen-<versão>-win-setup.exe` **na mesma release** do `Magen-mac.dmg`. O Mac procura `-mac.dmg` e o Windows procura `-win-setup.exe`. Um não atrapalha o outro.

## O que conferir no Windows (nada disto foi testado lá)

- [ ] `pip install` e `build_win.py` funcionam e o instalador sai.
- [ ] O instalador pede administrador, mostra o aviso "O Windows protegeu o computador" (sem assinatura) e instala.
- [ ] O serviço "Magen" aparece em `services.msc`, rodando e em automático. Ele abre a porta 53. **Se a porta 53 estiver ocupada**, o log `C:\ProgramData\Magen\magen.log` diz. Hyper-V, "Compartilhamento de Internet" e Docker às vezes usam essa porta.
- [ ] O DNS de todas as conexões vira `127.0.0.1` e `::1`. Confira com `ipconfig /all`. Os sites adultos não abrem e o resto abre normal, inclusive o app do Claude.
- [ ] A Wi-Fi caiu e voltou, ou o computador dormiu e acordou: o Magen continua respondendo.
- [ ] Ao desligar o serviço (`Magen.exe --stop-service` como admin), o DNS volta ao que era, automático ou fixo. Confira com `ipconfig /all`.
- [ ] O ícone perto do relógio: escudo vermelho quando liga, cinza quando desliga. O menu e a troca de idioma funcionam.
- [ ] A janela no estilo da família: trilho preto, título largo com marca-texto, botões com sombra dura e a Clash Grotesk. Os ícones das seções vêm da fonte Segoe Fluent Icons ou MDL2, que só existe no Windows. Confira se aparecem.
- [ ] Tela com zoom de 125 % ou 150 %: tudo nítido e no tamanho certo (`theme.SCALE`).
- [ ] A janela do versículo cobre **todas** as telas, fica por cima de tudo, faz a contagem "Respire… 5" e só fecha depois dela.
- [ ] Na aba Sites: Testar, Liberar e Bloquear. Liberar pede a frase, depois o "Permitir?", e só vale 1 hora depois. Um nome adulto é recusado. O × desfaz.
- [ ] Na aba Proteção, o "DNS seguro" dos navegadores. Com o Chrome ou o Edge em "DNS seguro" ligado, os sites adultos continuam bloqueados.
- [ ] O pop-up de doação na primeira vez, com Pix só em português.
- [ ] A atualização automática: publique uma versão de teste **só com o OK do dono**, ou teste com `updates.fetch_latest()`.
- [ ] A remoção pelo app (aba Proteção) e pelas Configurações do Windows. As duas pedem a frase. O DNS volta ao normal e a pasta `C:\ProgramData\Magen` vai para a Lixeira.

## Se a internet parar

Isso acontece quando o DNS aponta para o Magen mas o serviço não responde. Num terminal **como administrador**, rode:
```
"C:\Program Files\Magen\Magen.exe" --admin restaurar-dns
```
Pelo código: `.venv\Scripts\python magen.py --admin restaurar-dns`.

Também dá para fazer à mão: Configurações → Rede → conexão → DNS → Automático. O app também mostra o botão "Consertar a internet" na aba Início quando percebe isso.

## O que é só do Mac (de propósito)

- **Retransmissão Privada do iCloud:** não existe no Windows. A opção some da aba Proteção, mas fica no `config.json` para o arquivo ser igual nos dois.
- **"Sumir do Dock ao fechar":** no Windows, fechar a janela sempre deixa o Magen só perto do relógio.
- **Deslize da página ao trocar de aba:** não foi feito no Tk. Dá para fazer depois.
- **Ponteiro do mouse próprio:** ainda não tem no Windows. Usa a mãozinha do sistema nos botões. Seria preciso um `.cur` desenhado.
