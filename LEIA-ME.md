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

## Instalar

Dê dois cliques em **`instalar.command`** e digite a senha do Mac.

## Comandos (no Terminal)

| Comando | O que faz |
|---|---|
| `magen status` | mostra se está ligado e quantos sites bloqueia |
| `magen testar site.com` | diz se um site está bloqueado |
| `sudo magen liberar site.com` | desbloqueia um site bloqueado por engano |
| `sudo magen desfazer site.com` | tira o site da lista de liberados |
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
swift build -c release            # compila
.build/release/magen-selftest     # autoteste (sem internet, sem senha)
.build/release/magend --dir /tmp/magen --port 53535 --no-system-dns   # teste sem mexer no Mac
dig @127.0.0.1 -p 53535 exemplo.com
```

Licença MIT. As listas de bloqueio têm as licenças de cada projeto e são
baixadas direto da fonte. O Magen não as redistribui.
