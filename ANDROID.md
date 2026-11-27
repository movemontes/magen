# Magen: a versão de Android

Este guia é para o Claude Code (ou para quem for mexer no projeto). O Magen nasceu no Mac, em Swift (`Sources/`). Depois ganhou a versão de Windows, em Python (`windows/`). A de Android fica em `android/`, em Kotlin, com a mesma lógica, os mesmos textos e o mesmo visual.

## Regras

1. Fale em português simples: o dono não é programador. Use pronomes neutros.
2. **Nunca simule cliques ou arrastos no mouse real da pessoa.** No emulador, use o `adb` (ele toca na tela do celular de mentira, não no mouse).
3. Diga claramente o que foi testado de verdade (emulador) e o que depende de um celular de verdade.
4. **Não quebre o Mac nem o Windows.** Tudo de Android fica em `android/`. Não mexa em `Sources/`, `Package.swift`, `montar-app.sh` nem `windows/`.
5. Nada é apagado de vez: vai para a Lixeira.
6. Peça antes de publicar qualquer coisa: push, release ou site.

## Como funciona no Android (diferente do Mac e do Windows)

Um app comum de Android não pode abrir a porta 53 nem trocar o DNS do sistema. O caminho que os bloqueadores conhecidos usam (DNS66, RethinkDNS, personalDNSfilter) é uma **VPN local**: ela não leva nada para fora do celular.

- O Magen cria uma VPN que diz ao Android "o DNS é `10.111.222.2`" (e `fd00:6d61:6765:6e00::2` no IPv6). **Só esse endereço** passa pela VPN. O resto da internet vai direto, sem tocar no Magen. Por isso não fica lento nem gasta bateria à toa.
- Cada pergunta de DNS que chega é respondida como no Mac e no Windows. Site adulto → "não existe". O resto → Cloudflare (`1.1.1.1`, `1.0.0.1`), com a Quad9 (`9.9.9.9`) de reserva. Também tem o cache de 30 s, a segunda tentativa, a resposta antiga de até 1 dia quando a internet soluça e no máximo 48 perguntas ao mesmo tempo.
- As perguntas à Cloudflare saem por fora da VPN (`protect()`). O próprio app do Magen também fica fora dela (`addDisallowedApplication`), para baixar as listas pela rede normal.
- As listas (cerca de 1,1 milhão de sites) ficam na memória só como resumos de 64 bits, em ordem: uns 9 MB. Procurar um site é uma busca binária. Ao baixar, o Magen lê linha por linha, sem guardar o texto inteiro.
- O leitor da VPN dorme até chegar um pacote (`poll`), sem acordar o celular de tempos em tempos. Um ciclo de 30 s grava as contagens, libera os sites cuja hora chegou e confere se as listas têm mais de 24 h.

| | Mac | Windows | Android |
|---|---|---|---|
| Porteiro DNS | `magend` (launchd) | serviço "Magen" | `MagenVpnService` (VPN local) |
| Troca do DNS | `networksetup` | `netsh` | a VPN diz qual é o DNS |
| Aviso de bloqueio | notificação Darwin | recado UDP local | tudo roda no mesmo processo |
| Senha para mudar algo | senha do Mac | "Permitir?" (UAC) | **nenhuma** (só a frase e a espera) |
| Versículo por cima | janela do app | janela Tk | permissão "Aparecer sobre outros apps" |
| Dados | `/Library/Application Support/Magen` | `C:\ProgramData\Magen` | pasta particular do app (`config.json`, `state.json`, `blocklist-hashes.bin`, `magen.log`) |
| Atualização | `Magen-mac.dmg` | `Magen-<versão>-win-setup.exe` | `Magen-<versão>-android.apk` |

### Contra burla

- **DNS seguro dos navegadores:** os mesmos domínios de `ANTI_BYPASS_DOMAINS` respondem "não existe". Além disso, só no Android, os **endereços** dos servidores de DNS seguro conhecidos (8.8.8.8, 1.1.1.1, 9.9.9.9, os da OpenDNS, AdGuard e outros, em `Rules.ANTI_BYPASS_IPV4` e `_IPV6`) também passam pela VPN. A pergunta comum na porta 53 é filtrada. O DNS seguro (HTTPS na 443, TLS na 853) é recusado na hora com um "RST", para o app desistir sem esperar.
- **"DNS privado" do Android** (Configurações › Rede › DNS privado): no modo **automático**, o Android tenta DNS por TLS no endereço da VPN. O Magen recusa, e o Android volta ao DNS comum (filtrado). No modo **fixo** (com um nome, como `dns.google`), o Android pode passar por fora. O Magen percebe e mostra um aviso vermelho nas abas Início e Proteção, com o botão para abrir as configurações. Não existe atalho oficial direto para a tela do DNS privado.
- **"VPN sempre ativa":** um app não consegue ligar isso sozinho. A aba Proteção explica e tem o botão "Abrir as configurações de VPN". Com ela ligada, o Android liga o Magen ao reiniciar e se ele for fechado.
- **"Bloquear conexões sem VPN":** **não ligue.** Com a VPN que só cuida do DNS, essa opção corta a internet do resto, porque o tráfego normal não passa pela VPN. Fabricantes e versões diferentes podem se comportar diferente: confira no celular.
- **Dificultar a desinstalação:** a opção "Dificultar a desinstalação" (aba Proteção) torna o Magen um "app de administrador do dispositivo", sem nenhuma regra além disso. Enquanto ela está ativa, o Android não desinstala o Magen direto. Desligar pelo app pede a frase "quero remover a proteção". **Não é impossível:** quem souber o caminho desativa em Configurações › Segurança › Apps de administrador. É só um degrau a mais num momento de fraqueza.
- **Desligar a VPN por fora:** a pessoa pode desligar a VPN nas configurações do Android. Aí o Magen mostra a notificação "Magen está desligado" e o Início fica vermelho. O Android não deixa o app religar sozinho sem a pessoa tocar.
- **Outro app de VPN:** o Android só deixa uma VPN ligada por vez. Ligar outra desliga o Magen, com a mesma notificação.

### O que muda em relação ao Mac e ao Windows

- **Não há senha.** No Mac e no Windows, liberar um site, mudar a opção contra burla ou desfazer pede a senha do computador. No Android não existe isso para um app comum. Ficou assim:
  - Liberar: nome adulto é recusado, pede a frase "este site não é pornográfico" e só vale 1 hora depois (igual).
  - Desligar a opção contra burla: pede confirmação.
  - Desligar "Dificultar a desinstalação" e remover: pedem a frase "quero remover a proteção".
  - O × das listas da pessoa desfaz na hora.
- **Remover** (aba Proteção): pede a frase, desliga a VPN, tira o "administrador" e abre a desinstalação do Android. Os dados do app somem junto com ele (o Android não tem Lixeira para a pasta particular de um app).
- **Barra das seções embaixo**, preta, no lugar do trilho da esquerda. O passo 4 do tour diz "ficam aqui embaixo".
- **Versículo sem a permissão de aparecer por cima:** chega como notificação, com o título e o texto. O "Ver como fica" mostra dentro do próprio app.
- **"Testar"** pergunta ao filtro do próprio app (que é o mesmo do porteiro), sem passar pela rede.

## Preparar o computador

Este notebook não tem administrador. Por isso tudo foi posto em pastas da pessoa, sem instalador:

- **Android Studio** (zip): `AppData\Local\Programs\android-studio`. Abra pelo `bin\studio64.exe`.
- **Java 17** (zip da Microsoft): `AppData\Local\Programs\jdk-17.…`. O Java que vem com o Android Studio é o 25, novo demais para o Gradle 8.9.
- **SDK do Android:** `AppData\Local\Android\Sdk`. Tem a plataforma 35, as build-tools 35, o emulador e a imagem `android-35 google_apis x86_64`. A ferramenta nova é `cmdline-tools\latest\bin\android.exe sdk install …`.
- **Defeito deste notebook:** o Java dá "Unable to establish loopback connection" ao usar a pasta temporária do Windows. O conserto é `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\Users\Public\magen-tmp`, e o `montar.ps1` já faz isso.
- **Fonte Clash Grotesk:** vem de `windows\fontes-privadas` na hora de montar, e nunca entra no Git. Sem ela, o app usa a Archivo, e o aviso aparece na montagem.

## Montar

No PowerShell, dentro de `android\`:

```powershell
.\montar.ps1
```

O resultado sai em `android\dist\Magen-1.3-android.apk`. A versão fica em `android\app\build.gradle.kts` (`magenVersion` e `magenCode`) e deve ser o mesmo número do Mac e do Windows. Para só rodar os testes do núcleo (listas, filtro, mensagens DNS, pacotes): `.\montar.ps1 -Testes`.

### A chave que assina o .apk (importante)

O `.apk` é assinado com `android\chave-privada\magen-android.jks`, e a senha fica em `assinatura.properties`, na mesma pasta. Essa pasta **não vai para o GitHub**.

**Guarde uma cópia dela num lugar seguro** (pen drive, nuvem particular). O Android só aceita atualizar um app se a versão nova for assinada com a mesma chave. Se ela se perder, quem já instalou o Magen vai precisar desinstalar e instalar de novo.

## Publicar

Sempre com o OK do dono: suba o `Magen-<versão>-android.apk` **na mesma release** do `Magen-mac.dmg` e do `-win-setup.exe`. O Android procura `-android.apk` e não atrapalha os outros.

A Play Store tem regras próprias para apps de VPN (formulário, justificativa, revisão). Por isso, por enquanto, a distribuição é pelo `.apk` do GitHub. A pessoa precisa permitir "instalar apps desconhecidos" no navegador na primeira vez.

## O que foi testado no emulador (27 nov. 2026)

Num celular de mentira (Pixel 6, Android 15, `google_apis x86_64`), com o `.apk` de release. Os toques foram feitos pelo `adb`, nunca no mouse real.

- **Testes automáticos** (`.\montar.ps1 -Testes`): 8 de 8 passam. Cobrem a leitura das listas, os resumos de sites, a ordem do filtro (liberado > contra burla > bloqueado), a resposta "não existe" e os pacotes UDP e TCP.
- **Primeira vez:** o pop-up de doação aparece (em inglês sem Pix, em português com o Pix e o "Copiar chave Pix"). Depois dele, o tour de 8 passos, com cada passo acendendo o pedaço certo e trocando de aba.
- **Ligar:** o Android pede notificações e a VPN. A chave aparece lá em cima. As 3 listas baixaram em **10 segundos** (1.156.909 sites). Depois de atualizar o app, carregam do disco em meio segundo.
- **Bloqueio:** pornhub.com, www.xvideos.com e xnxx.com dão "unknown host". google.com, wikipedia.org, globo.com e bbc.com abrem. `dns.google` e `use-application-dns.net` (contra burla) também são bloqueados.
- **Contra burla por endereço:** conexões a 1.1.1.1:443, 8.8.8.8:853 e 9.9.9.9:443 são recusadas em **cerca de 10 ms**. Um servidor comum do Google conecta normal.
- **DNS privado fixo (`dns.google`):** nada passa (a internet inteira para, porque o Magen recusa o servidor do Google) e o aviso vermelho aparece. No modo **automático**, o filtro funciona normal.
- **"Bloquear conexões sem VPN":** confirmado que corta a internet ("Permission denied" ao conectar). Desligando, volta.
- **"VPN sempre ativa":** a aba Proteção mostra "✅ Ligada". Depois de **reiniciar** o celular, o Magen liga sozinho e bloqueia.
- **Versículo:** a tela vermelha cobre o Chrome, faz "Respire… 4, 3…", o botão **voltar não fecha** antes da contagem, e o nome do site não aparece. O intervalo mínimo entre telas funciona.
- **Sites:** "Testar" diz bloqueado ou liberado. "Liberar" recusa nome adulto, recusa a frase errada ("A frase não confere. Nada foi liberado.") e, com a frase certa, deixa o site esperando 1 hora ("⏳ … às 19:59"). "Bloquear" vale na hora para nomes novos. O × desfaz.
- **Memória do Android:** um site que o celular já tinha aberto continua abrindo por alguns minutos depois de "Bloquear", porque o próprio Android guarda a resposta. Isso também acontece no Mac e no Windows. Depois de reiniciar, ficou bloqueado.
- **Dificultar a desinstalação:** com ela ativa, `pm uninstall` é recusado (`DELETE_FAILED_DEVICE_POLICY_MANAGER`).
- **Remover:** a frase errada é recusada. Com a certa, a VPN desliga, o "administrador" sai e abre o "Desinstalar este app?" do Android. Prova de que o bloqueio vinha do Magen: com ele desligado, pornhub.com volta a responder.
- **Desligar a VPN nas configurações do Android:** aparece a notificação "⚠️ Magen está desligado".
- **Idioma:** a troca entre português e inglês muda todos os textos na hora.

**Não deu para medir no emulador:** a velocidade e a bateria de verdade. O emulador usa a internet do notebook por um caminho próprio, então os números não valem para um celular.

## O que conferir num celular de verdade

- [ ] Instalar o `.apk` baixado do GitHub (o Android pede "instalar apps desconhecidos").
- [ ] "Ligar a proteção": o Android pede a permissão de VPN e a de notificações. Aparece a chave de VPN lá em cima.
- [ ] Sites adultos não abrem no Chrome, no Samsung Internet (se tiver) e no Firefox. O resto abre normal: WhatsApp, Instagram, YouTube, banco.
- [ ] A tela vermelha do versículo aparece por cima do navegador, com "Respire… 5", e o botão "voltar" não fecha antes da contagem. Antes, dê a permissão "Aparecer sobre outros apps" pelo aviso do app.
- [ ] Wi-Fi e 4G/5G, e a troca entre os dois: a internet continua.
- [ ] Reiniciar o celular: o Magen liga sozinho. Com "VPN sempre ativa", o Android liga. Sem ela, quem liga é o próprio Magen ao iniciar o celular.
- [ ] "VPN sempre ativa" ligada: a aba Proteção mostra "✅ Ligada".
- [ ] **Não** ligar "Bloquear conexões sem VPN". Se alguém ligar, confira se a internet para (é o esperado) e anote o modelo.
- [ ] DNS privado no modo fixo (por exemplo `dns.google`): o aviso vermelho aparece.
- [ ] Chrome com "Usar DNS seguro" num provedor (Configurações › Privacidade): os sites adultos continuam bloqueados.
- [ ] "Dificultar a desinstalação": com ela ligada, o Android não desinstala direto pelo ícone. Desligar pede a frase.
- [ ] Bateria: depois de um dia normal, o Magen não aparece entre os que mais gastam (Configurações › Bateria). Alguns fabricantes (Xiaomi, Samsung, Motorola) fecham apps em segundo plano. Se o Magen desligar sozinho, ponha ele como "sem restrição" de bateria.
- [ ] Rede com página de login (Wi-Fi de hotel ou aeroporto): a página abre.
- [ ] A atualização pelo GitHub: publique uma versão de teste **só com o OK do dono**.
- [ ] Remover: pede a frase, desliga a VPN e abre a desinstalação.
