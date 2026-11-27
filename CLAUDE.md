# Magen: recado para o Claude

O Magen tem três versões feitas em chats separados: a de **Mac** (Swift, em `Sources/`), a de **Windows** (Python, em `windows/`) e a de **Android** (Kotlin, em `android/`). Uma não vê o que a outra fez.

**Antes de começar qualquer tarefa, leia [`NOTAS-ENTRE-VERSOES.md`](NOTAS-ENTRE-VERSOES.md).** Lá cada versão deixa o que mudou e a outra ainda não tem.

- No Mac, veja a lista "Windows → Mac". Se o dono pedir para igualar as versões, faça os itens dela.
- No Windows, veja a lista "Mac → Windows".
- No Android, veja a lista "Mac e Windows → Android".
- Quando você mudar algo que a outra versão também deveria ter, escreva na lista do outro sentido, no mesmo commit.
- Quando terminar de portar um item, mova-o para "Já igualado", com a data.
- Mudanças que só fazem sentido de um lado (um defeito do Tk, um detalhe do Swift) entram como "só para saber", para a outra versão não procurar o problema à toa.

Outras regras do projeto: fale em português simples (o dono não é programador) e use pronomes neutros. Peça antes de dar push, publicar release ou mudar o site. Nunca apague nada de vez: mande para a Lixeira. As regras específicas do Windows estão em [`WINDOWS.md`](WINDOWS.md) e as do Android em [`ANDROID.md`](ANDROID.md).
