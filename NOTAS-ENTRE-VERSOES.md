# Notas entre as versões do Magen (Mac ↔ Windows ↔ Android)

Cada versão é feita num chat diferente. Aqui uma deixa recado para a outra. Leia o `CLAUDE.md` para saber como usar.

---

## Windows → Mac (o Windows tem, o Mac ainda não)

### 1. Tour da primeira vez (sem mascote)

**O que é:** um tour como o do Disquetinho no Treco, mas **sem mascote** (decisão do dono: "mais sério"). A janela escurece, só o pedaço explicado fica aceso (com borda vermelha) e aparece um balão com título, texto, a contagem ("3/8") e os botões **"Pular o tour"** e **"Próximo"** (no último passo, **"Começar"**). Enter avança e Esc pula. O tour troca de aba sozinho quando o passo pede.

**Referência pronta:** `windows/magen_win/ui/tour.py` (os passos e o desenho do balão), mais as marcações `self.spot(...)` em `windows/magen_win/ui/window.py`.

**Quando aparece:**
- Na primeira vez que o app é aberto pela pessoa (não no início com o sistema), **depois** que o pop-up de doação é fechado. No Mac, isso é no `main.swift`, logo depois de `donate.show()`.
- Guarde como visto numa preferência com número de versão (`tourVisto = 1`, com `TOUR_VERSION = 1`). Se o tour mudar, aumente o número e ele aparece de novo uma vez.
- Se a pessoa fechar a janela no meio, conta como "pulou".
- Para rever: botão **"Ver o tour"** na aba Sobre, ao lado de Idioma, e item **"Ver o tour"** no menu do ícone, logo abaixo de "Sobre o Magen".

**Os 8 passos** (aba, o que fica aceso, título, texto). No Mac, troque "Windows" por "Mac" e "permissão do Windows" por "senha do Mac":

1. Início, nada aceso (balão no centro). **Bem-vindo ao Magen**. "Em poucos passos, você vê como ele protege este computador. Dá para pular quando quiser."
2. Início, o cartão grande PROTEGENDO/DESLIGADO. **Está protegendo?** "Preto quer dizer protegendo. Vermelho quer dizer desligado: aí aparece o botão “Ligar a proteção”, e o Windows pede permissão."
3. Início, os 4 cartões de números. **Os números**. "Quantos sites adultos foram bloqueados hoje e no total, e quando as listas foram atualizadas. O nome dos sites nunca é guardado."
4. Início, o trilho preto. **As seções**. "Início, Sites, Versículos e Proteção ficam aqui. Embaixo fica o Sobre."
5. Sites, o campo, os 3 botões e a frase logo abaixo. **Testar, liberar ou bloquear**. "Digite um site para saber se ele está bloqueado. “Liberar” é só para site que não é adulto: pede uma frase, a permissão do Windows, e só vale 1 hora depois."
6. Versículos, o conteúdo da aba inteiro. **O versículo**. "Quando um site adulto é bloqueado, a tela fica vermelha com um versículo e só fecha depois de alguns segundos. Aqui você escolhe esse tempo. “Ver como fica” mostra um exemplo."
7. Proteção, a caixinha do "DNS seguro". **Contra burla**. "Deixe isto ligado: assim os navegadores não fogem do Magen pelo “DNS seguro”. Remover o Magen pede uma frase, de propósito."
8. Início, nada aceso. **Pronto**. "Fechar a janela não desliga a proteção: o Magen fica no escudo perto do relógio. Para rever este tour, vá em Sobre." (No Mac: "fica no escudo da barra de menus".)

**Inglês:** já está em `windows/magen_win/data/en.json` (procure "Bem-vindo ao Magen" e as seguintes). No Mac, ponha em `English.swift`. Use o mesmo nome de botão que o Mac já usa (lá "Ver como fica" é "Preview").

**Onde fica o balão:** se o pedaço aceso é estreito e fica à esquerda (o trilho), o balão vai à direita dele. Se não, o balão vai embaixo do pedaço quando cabe, ou em cima. Se o pedaço é grande demais, o balão vai no canto de baixo à direita. Sempre dentro da janela.

**Visual:** balão branco, borda preta de 2 px, sombra dura; título em negrito 15, texto 12 em cinza-escuro, contagem 11 em cinza. "Próximo" é o botão preto (accent); "Pular o tour" é o botão branco. Escurecido: preto com uns 55 % de opacidade. Borda do pedaço aceso: vermelha, 3 px.

**Cuidado que o Windows ensinou:** o balão tem que ficar **sempre na frente** do escurecido, mesmo se a pessoa clicar no escuro. No Windows, isso deu problema com duas janelas soltas. No Mac, o mais simples é desenhar o escurecido e o balão **dentro da própria janela principal** (uma view por cima de tudo), sem janela extra.

### 2. Números e títulos grandes em tela sem Retina (baixa prioridade)

Na Archivo larga e bem preta (`Theme.wide`), o vão do "5" (entre o traço de cima e a barriga) tem menos de 1 pixel em 22 px. No Windows em 100 % ele sumia, e o 5 parecia grudado. A correção lá foi desenhar 3 vezes maior e reduzir. Num Mac com tela Retina não acontece. Só vale conferir se alguém usar monitor externo comum (sem Retina): se o 5 dos cartões parecer grudado, é isso.

### 3. Atualização: versão publicada só para o outro sistema

O Windows dizia "Não deu para procurar agora" porque a última release (v1.2) só tem `Magen-mac.dmg`. Lá a correção foi: uma release sem o instalador do próprio sistema conta como "nada novo aqui". Se a pessoa clicou em "Procurar atualização", aparece "Você está com a versão mais nova"; na procura automática, não aparece nada. Veja `fetch_latest` em `windows/magen_win/updates.py` e `_update_found` em `windows/magen_win/ui/app.py`.

**No Mac acontece o mesmo, ao contrário,** se um dia sair uma release só com `-win-setup.exe`, em `Updates.fetchLatest` (`AppChrome.swift`):
- A consulta à API não acha o `.dmg` e cai no "plano B".
- O plano B monta o link de `Magen-mac.dmg` sem conferir se ele existe e oferece uma atualização que falha no download.

Correção sugerida: no plano B, confira o link com um pedido HEAD antes de oferecer. Quando a API responder mas a release não tiver `.dmg`, trate como "versão mais nova", não como erro.

### Só para saber (não precisa fazer no Mac)

Correções que só existiam no Windows:
- O texto pequeno da Clash Grotesk ficava ilegível no Tk (motor de texto antigo do Windows). Agora todo texto é desenhado pelo Pillow.
- O cartão do versículo ia para o canto e sumia ao clicar no vermelho. O Mac já faz certo, com o cartão dentro da capa.
- Uma página saía estreita quando montada com a janela escondida.
- O instalador agora para um serviço antigo antes de trocar o caminho dele.
- O `build_win.py` se recusa a montar por cima de um Magen em uso.

---

## Mac → Windows (o Mac tem, o Windows ainda não)

_(vazio por enquanto: o chat do Mac escreve aqui)_

---

## Android → Mac e Windows (o Android tem, os outros ainda não)

### 1. Dois domínios a mais na lista "nunca bloquear" (baixa prioridade)

O Android pôs `android.com` e `googlezip.net` em `NEVER_LIST_ENTRIES` (são endereços que o Android usa para saber se há internet e para economizar dados). Não fazem mal no Mac nem no Windows. Vale acrescentar para as três listas ficarem iguais: no Mac em `Sources/MagenCore`, no Windows em `windows/magen_win/core.py`.

### Só para saber (não precisa fazer no Mac nem no Windows)

- **O porteiro é uma VPN local** (`android/.../vpn/MagenVpnService.kt`). Um app de Android não pode abrir a porta 53 nem trocar o DNS do sistema. A VPN só recebe o DNS falso `10.111.222.2`; o resto da internet passa direto.
- **Contra burla por endereço:** além dos domínios de `ANTI_BYPASS_DOMAINS`, o Android leva para dentro da VPN os **endereços** dos servidores de DNS seguro (8.8.8.8, 1.1.1.1, 9.9.9.9…) e recusa a 443 e a 853 deles. No Mac e no Windows isso não é preciso do mesmo jeito.
- **Sem senha:** o Android não tem senha de administrador para um app pedir. Liberar continua pedindo a frase e a espera de 1 hora. Desligar a opção contra burla pede só uma confirmação. Desligar "Dificultar a desinstalação" e remover pedem a frase "quero remover a proteção".
- **Extras só do Android:** aviso de "DNS privado" fixo, "VPN sempre ativa", "Dificultar a desinstalação" (app de administrador do dispositivo) e a permissão "Aparecer sobre outros apps" para o versículo (sem ela, o versículo vem como notificação).
- **Tour:** já existe no Android (o item 1 de "Windows → Mac" continua valendo só para o Mac). Os mesmos 8 passos, com "celular" no lugar de "computador". As seções ficam numa barra preta **embaixo** (passo 4: "ficam aqui embaixo"). No último passo: "o Magen fica na chave da VPN, lá em cima".
- **Textos em inglês:** `android/app/src/main/assets/en.json` = o `en.json` do Windows + as frases novas do Android. Os versículos vêm de `windows/magen_win/data/versiculos.json` na hora de montar (uma lista só para os dois).
- **Atualização:** procura `-android.apk` na mesma release do GitHub (`Magen-<versão>-android.apk`).
- **Bloquear um site que o celular já abriu** pode levar alguns minutos para valer, porque o próprio Android guarda a resposta. No Mac e no Windows é igual; só ficou mais visível no teste.

---

## Mac e Windows → Android (os outros têm, o Android ainda não)

- **Ponteiro do mouse próprio, "Sumir do Dock", Retransmissão Privada do iCloud:** não se aplicam ao Android.
- _(o chat do Mac e o do Windows escrevem aqui quando mudarem algo que o Android também deveria ter)_

---

## Já igualado

_(nada ainda)_
