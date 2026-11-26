# Magen 🛡️

**Magen** quer dizer "escudo" em hebraico. É um bloqueador **grátis** de sites
pornográficos para Mac, sem conta e sem anúncios.

## Como funciona

Antes de abrir qualquer site, o Mac pergunta "qual é o endereço deste site?".
Essa pergunta se chama DNS. O Magen responde a essa pergunta: se o site está
numa lista de sites adultos, a resposta é "esse site não existe", e ele não abre.
Isso vale para **todos os navegadores e apps**.

- Cerca de **1,15 milhão** de sites adultos, de três listas abertas:
  [OISD NSFW](https://oisd.nl), [Block List Project](https://github.com/blocklistproject/Lists)
  e [StevenBlack](https://github.com/StevenBlack/hosts) (extensão "porn").
- As listas se atualizam sozinhas uma vez por dia.
- O Magen não olha imagens, só o nome do site. Por isso **não bloqueia
  fotos de pessoas vestidas** em sites normais.
- Tem uma lista de "nunca bloquear" com sites grandes (Google, YouTube, Reddit,
  Wikipedia, Globo, UOL…), para que um erro numa lista não quebre a internet.
- Ele também bloqueia truques comuns para fugir do filtro: o "DNS seguro" dos
  navegadores e a Retransmissão Privada do iCloud.
- Quando o Magen é desligado, o DNS do Mac volta a ser o que era antes.

## O app Magen 🛡️

Depois de instalado, um escudo aparece no topo da tela. Clique nele e escolha
**Abrir o Magen** (ou abra o Magen em Aplicativos). A janela tem o mesmo estilo
do Treco, em vermelho, com cinco abas:

- **Início:** se está protegendo, bloqueios de hoje e do total, sites na lista.
- **Sites:** testar, liberar ou bloquear um site, e ver os que você mudou.
- **Versículos:** ligar ou desligar a janela, quanto tempo até poder fechar,
  intervalo entre janelas e uma prévia.
- **Proteção:** bloquear ou não a Retransmissão Privada do iCloud e o "DNS
  seguro" dos navegadores.
- **Sobre:** créditos.

Quando um site adulto é bloqueado, **a tela fica vermelha** e aparece um cartão
no centro com uma frase e um versículo, por exemplo "Você pode fugir disso."
com 1 Coríntios 10:13. O botão só funciona depois de alguns segundos. O nome do
site nunca aparece, e os bloqueios automáticos "anti-burla" não abrem a janela.

**Aviso da Retransmissão Privada:** o Magen bloqueia a Retransmissão Privada
do iCloud, porque sem isso o Safari passa por fora dele. Por isso o Mac mostra
uma vez em cada rede o aviso "não é compatível com a Retransmissão Privada".
Escolha **"Usar sem a Retransmissão Privada"**. Dá para mudar isso na aba
Proteção.

Versículos: **Bíblia Livre (BLIVRE)**, Copyright © Diego Santos, Mario Sérgio
e Marco Teles, fevereiro de 2018, [Licença Creative Commons Atribuição 4.0
Brasil](http://creativecommons.org/licenses/by/4.0/br/). Os títulos acima dos
versículos são do Magen. Fonte: Archivo (SIL Open Font License).

## Velocidade

O Magen só vê o *nome* do site, uma vez, e não o conteúdo das páginas. Num
teste com 16 sites comuns, a resposta direto da Cloudflare levou cerca de 25 ms,
e pelo Magen, 26 ms. Sites bloqueados respondem em menos de 1 ms. Para os sites
normais, o Magen pergunta à Cloudflare (1.1.1.1).

## Instalar

Dê dois cliques em **`instalar.command`** e digite a senha do Mac.

## Comandos (no Terminal)

| Comando | O que faz |
|---|---|
| `magen status` | mostra se está ligado e quantos sites bloqueia |
| `magen testar site.com` | diz se um site está bloqueado |
| `sudo magen liberar site.com` | desbloqueia um site bloqueado por engano |
| `sudo magen desfazer site.com` | desfaz um "liberar" ou "bloquear" |
| `sudo magen retransmissao sim\|nao` | bloqueia (ou não) a Retransmissão Privada |
| `sudo magen antiburla sim\|nao` | bloqueia (ou não) o "DNS seguro" dos navegadores |
| `sudo magen bloquear site.com` | bloqueia um site a mais |
| `sudo magen atualizar` | baixa as listas novas agora |

## Remover (ou se a internet parar)

Dê dois cliques em **`desinstalar.command`**. Ele devolve o DNS do Mac como
era antes e manda os arquivos do Magen para o Lixo.

## Limites (honestos)

- Bloqueia **a maioria** dos sites adultos, nunca 100%. Sites novos surgem
  todo dia.
- Quem tem a senha de administrador do Mac consegue desligar o Magen.
- Uma VPN ligada (por exemplo, a Kaspersky VPN) pode usar o próprio DNS e
  passar por fora do Magen.
- Ainda não bloqueia anúncios adultos dentro de sites normais. Isso vem numa
  próxima versão, com uma extensão para Safari e Chrome.

## Para quem programa

```
./montar-app.sh                   # compila tudo e monta bin/ (o instalador usa essa pasta)
.build/release/magen-selftest     # autoteste (sem internet, sem senha)
.build/release/magend --dir /tmp/magen --port 53535 --no-system-dns   # teste sem mexer no Mac
dig @127.0.0.1 -p 53535 exemplo.com
```

Licença MIT. As listas de bloqueio têm as licenças de cada projeto e são
baixadas direto da fonte. O Magen não as redistribui.
