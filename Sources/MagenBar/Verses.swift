// Versículos da Bíblia Livre (BLIVRE), Copyright © Diego Santos, Mario Sérgio
// e Marco Teles, fevereiro de 2018. Licença Creative Commons Atribuição 4.0
// Brasil (http://creativecommons.org/licenses/by/4.0/br/). Texto copiado de
// https://ebible.org/porbr2018/ ; só os colchetes de palavras acrescentadas
// foram tirados, para ficar mais fácil de ler na notificação.
/// `title` é uma frase curta do Magen (não é texto bíblico) que resume o versículo.
struct Verse { let title: String; let text: String; let ref: String }

let verseCredit = "Bíblia Livre (BLIVRE), 2018 · CC BY 4.0"

let verses: [Verse] = [
    Verse(title: "Você pode fugir disso.", text: "Nenhuma tentação vos veio, que não fosse humana; porém Deus é fiel; que não vos deixará tentar mais do que o que podeis, antes com a tentação também dará a saída, para que a possais suportar.", ref: "1 Coríntios 10:13"),
    Verse(title: "Fugir também é vencer.", text: "Fugi do pecado sexual. Todo pecado que o ser humano comete é fora do corpo; mas o que pratica pecado sexual, peca contra seu próprio corpo.", ref: "1 Coríntios 6:18"),
    Verse(title: "Seu corpo não é descartável.", text: "Ou não sabeis que vosso corpo é templo do Espírito Santo, o qual está em vós, o qual tendes de Deus, e que não sois de vós mesmos?", ref: "1 Coríntios 6:19"),
    Verse(title: "Você custou caro demais.", text: "Porque vós fostes comprados por alto preço; então glorificai a Deus em vosso corpo, e em vosso espírito, que são de Deus.", ref: "1 Coríntios 6:20"),
    Verse(title: "Existe um caminho limpo.", text: "Com que um rapaz purificará o seu caminho? Sendo obediente conforme a tua palavra.", ref: "Salmos 119:9"),
    Verse(title: "Guarde a Palavra no coração.", text: "Guardei a tua palavra em meu coração, para eu não pecar contra ti.", ref: "Salmos 119:11"),
    Verse(title: "Desvie os olhos.", text: "Desvia meus olhos para que não olhem para coisas inúteis; vivifica-me pelo teu caminho.", ref: "Salmos 119:37"),
    Verse(title: "Um coração novo é possível.", text: "Cria em mim um coração puro, ó Deus; e renova um espírito firme em meu interior.", ref: "Salmos 51:10"),
    Verse(title: "Nem tudo merece os seus olhos.", text: "Não porei perante meus olhos obra maligna; odeio as ações dos que desviam, tais coisas não me tomarão.", ref: "Salmos 101:3"),
    Verse(title: "Os limpos de coração verão a Deus.", text: "Benditos são os limpos de coração, porque eles verão a Deus.", ref: "Mateus 5:8"),
    Verse(title: "Vigie. A carne é fraca.", text: "Vigiai e orai, para que não entreis em tentação. De fato, o espírito está pronto, mas a carne é fraca.", ref: "Mateus 26:41"),
    Verse(title: "Sua mente pode ser renovada.", text: "E não vos conformeis com a presente era; mas transformai-vos pela renovação da vossa mentalidade, para que experimenteis qual seja a boa, agradável, e perfeita vontade de Deus.", ref: "Romanos 12:2"),
    Verse(title: "Isso não manda em você.", text: "Pois o pecado não vos dominará, porque não estais sob a Lei, mas sim, sob a graça.", ref: "Romanos 6:14"),
    Verse(title: "Não há condenação. Levante-se.", text: "Portanto, agora, nenhuma condenação há para os que estão em Cristo Jesus, que não andam segundo a carne, mas sim segundo o Espírito.", ref: "Romanos 8:1"),
    Verse(title: "Não alimente esse desejo.", text: "Em vez disso, revesti-vos do Senhor Jesus Cristo, e não fiqueis pensando em realizar os desejos da carne.", ref: "Romanos 13:14"),
    Verse(title: "Fuja e siga outro caminho.", text: "Foge também dos desejos da juventude; e segue a justiça, a fé, o amor, e a paz, com os que, de coração puro, invocam o Senhor.", ref: "2 Timóteo 2:22"),
    Verse(title: "Pense no que é puro.", text: "No restante, meus irmãos, tudo o que é verdadeiro, tudo o que é respeitável, tudo o que é justo, tudo o que é puro, tudo o que é amável, tudo o que é de boa fama, se há alguma virtude, e se há algo digno de elogio, nisto pensai.", ref: "Filipenses 4:8"),
    Verse(title: "Você não está sem forças.", text: "Posso todas as coisas em Cristo que me fortalece.", ref: "Filipenses 4:13"),
    Verse(title: "Ande no Espírito.", text: "Mas eu digo: andai no Espírito, e não executeis o mau desejo da carne.", ref: "Gálatas 5:16"),
    Verse(title: "Resistir vale a pena.", text: "Bendito é o homem que suporta a provação; pois, quando for aprovado, receberá a coroa da vida, que o Senhor prometeu aos que o amam.", ref: "Tiago 1:12"),
    Verse(title: "Resista, e ele foge.", text: "Sujeitai-vos, pois, a Deus; resisti ao diabo, e ele fugirá de vós.", ref: "Tiago 4:7"),
    Verse(title: "Chegue perto de Deus.", text: "Aproximai-vos de Deus, e ele se aproximará de vós. Limpai as vossas mãos, pecadores, e vós de dupla mentalidade, purificai os vossos corações.", ref: "Tiago 4:8"),
    Verse(title: "Deus quer algo melhor para você.", text: "Pois esta é a vontade de Deus: a vossa santificação, que não pratiqueis pecado sexual;", ref: "1 Tessalonicenses 4:3"),
    Verse(title: "Você foi chamado para mais.", text: "Pois Deus não nos chamou para a impureza, mas sim para a santificação.", ref: "1 Tessalonicenses 4:7"),
    Verse(title: "Ainda dá para recomeçar.", text: "Se confessarmos nossos pecados, ele é fiel e justo para nos perdoar os pecados e nos purificar de toda injustiça.", ref: "1 João 1:9"),
    Verse(title: "Ele entende a sua luta.", text: "Pois não temos um Sumo Sacerdote que não possa se compadecer das nossas fraquezas; mas, sim, um que foi provado em tudo, conforme a nossa semelhança, porém sem pecado.", ref: "Hebreus 4:15"),
    Verse(title: "Peça ajuda agora.", text: "Portanto, acheguemo-nos com confiança ao trono da graça, para que possamos receber misericórdia e encontrar graça para sermos socorridos no tempo adequado.", ref: "Hebreus 4:16"),
    Verse(title: "Guarde o seu coração.", text: "Acima de tudo o que se deve guardar, guarda o teu coração; porque dele procedem as saídas da vida.", ref: "Provérbios 4:23"),
    Verse(title: "Você não está sozinho.", text: "Não temas, porque eu estou contigo; não te assombres, porque eu sou teu Deus. Eu te fortaleço, te ajudo, e te sustento com a minha mão direita de justiça.", ref: "Isaías 41:10"),
    Verse(title: "Suas forças serão renovadas.", text: "Mas os que confiam no SENHOR renovarão as forças, subirão com asas como águias; correrão, e não se cansarão; caminharão, e não se fatigarão.", ref: "Isaías 40:31"),
    Verse(title: "O velho já passou.", text: "Portanto, se alguém está em Cristo, uma nova criatura é; as coisas velhas já passaram, eis que tudo se fez novo.", ref: "2 Coríntios 5:17"),
    Verse(title: "A graça basta.", text: "Mas ele me disse: “Minha graça te basta, porque meu poder se aperfeiçoa na fraqueza”. Por isso, com muito prazer, eu me orgulharei nas minhas fraquezas, para que o poder de Cristo habite em mim.", ref: "2 Coríntios 12:9"),
    Verse(title: "A misericórdia não acabou.", text: "É pelas bondades do SENHOR que não somos consumidos, porque suas misericórdias não têm fim.", ref: "Lamentações 3:22"),
    Verse(title: "Cada manhã é um novo começo.", text: "Elas são novas a cada manhã; grande é a tua fidelidade.", ref: "Lamentações 3:23"),
    Verse(title: "Seja forte no Senhor.", text: "Por fim, meus irmãos, fortalecei-vos no Senhor e na força do seu poder.", ref: "Efésios 6:10"),
    Verse(title: "Entregue o que pesa.", text: "Lançando sobre ele toda a vossa ansiedade; porque ele tem cuidado de vós.", ref: "1 Pedro 5:7"),
    Verse(title: "Há refúgio para você.", text: "Deus é nosso refúgio e força; socorro oportuno nas angústias.", ref: "Salmos 46:1"),
    Verse(title: "Seu passado foi lançado longe.", text: "Assim como o oriente está longe do ocidente, assim também ele tira para longe de nós nossas transgressões.", ref: "Salmos 103:12"),
    Verse(title: "Seu socorro vem do alto.", text: "Meu socorro vem do SENHOR, que fez os céus e a terra.", ref: "Salmos 121:2"),
    Verse(title: "A alegria de verdade está em outro lugar.", text: "Tu me farás conhecer o caminho da vida; fartura de alegrias há em tua presença; agrados estão em tua mão direita para sempre.", ref: "Salmos 16:11"),
    Verse(title: "Vai, e não peques mais.", text: "E disse ela: Ninguém, Senhor. E disse-lhe Jesus: Nem eu também te condeno; vai, e não peques mais.", ref: "João 8:11"),
    Verse(title: "A verdade liberta.", text: "E conhecereis a verdade, e a verdade vos libertará.", ref: "João 8:32"),
    Verse(title: "Você pode ser livre de verdade.", text: "Portanto, se o Filho vos libertar, verdadeiramente sereis livres.", ref: "João 8:36"),
]
