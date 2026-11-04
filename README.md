# Cantorial

Aplicativo para Android e iPhone para aprender a cantar: mostra em tempo real a nota que você canta, fala ou toca,
traz exercícios guiados com pontuação de afinação, material de estudo e ensina **segunda voz** e
**backing vocal** a partir das músicas que você adicionar.

## Baixar e instalar

1. No celular, abra a página da [release mais recente](../../releases/latest).
2. Toque em **Cantorial.apk** para baixar e depois em **Instalar**.
3. Se o Android pedir, permita "instalar apps desconhecidos" para o navegador.

Link direto do APK: `https://github.com/RaulHrN/Typescript-study/releases/latest/download/Cantorial.apk`

Cada envio para o repositório gera um APK novo pelo GitHub Actions (`.github/workflows/android.yml`).
Versões novas instalam por cima da anterior (veja "Assinatura" abaixo), inclusive sobre o app quando ele
ainda se chamava Vox.

## iPhone (iOS 17 ou mais novo)

Cada envio também gera o app para iPhone (`.github/workflows/ios.yml`), publicado nas
[releases](../../releases) com a etiqueta `ios-v1.2.N`, arquivo **Cantorial-ios.ipa**.

A Apple só deixa instalar apps fora da App Store se eles forem assinados com uma conta Apple. O IPA sai sem
assinatura, então a instalação é feita por uma ferramenta que assina com o seu Apple ID:

1. No computador (Windows ou Mac), instale o [Sideloadly](https://sideloadly.io) ou o
   [AltStore](https://altstore.io) e conecte o iPhone pelo cabo.
2. Baixe o **Cantorial-ios.ipa** da release mais recente com etiqueta `ios-v…`.
3. Arraste o IPA para a ferramenta e entre com o seu Apple ID.
4. No iPhone: Ajustes → Geral → VPN e Gerenciamento de Dispositivos → confie no seu Apple ID.
   No iOS 16 ou mais novo, ative também Ajustes → Privacidade e Segurança → Modo de Desenvolvedor.

Com um Apple ID gratuito a assinatura dura 7 dias (o AltStore renova sozinho com o computador ligado).
Com uma conta paga do Apple Developer Program dá para assinar por um ano ou distribuir pelo TestFlight.

## O que o app faz

- **Ouvir**: afinador vocal. Mostra a nota (Dó Ré Mi ou C D E), a frequência, o desvio em cents,
  o desenho da sua voz ao longo do tempo e as últimas notas cantadas.
- **Treinar**: exercícios de respiração, aquecimento, afinação, técnica, ouvido, segunda voz e backing
  vocal. O app toca o modelo, você repete e ele pontua cada nota. O tom sobe e desce conforme a sua extensão,
  medida pelo **teste de extensão** (que também sugere a sua classificação vocal).
  - **Tipos de segunda voz**: 3ª acima, 3ª abaixo, 6ª abaixo, 6ª acima, conduzida (alterna 3ª e 6ª),
    movimento contrário, nota pedal e dobra, cada um com lição, exemplo para ouvir e exercício.
  - **Laboratório de backing vocal**: você escolhe o tipo de voz do regente e o estilo (harmonia, pad,
    resposta, dobra, com 1 ou 2 vozes) e o app mostra onde a sua parte fica, quantos dB abaixo do regente
    cada voz deve cantar e dicas para aquela combinação de vozes.
  - **Equilíbrio de volume**: grava a sua voz no volume de regente e treina os níveis de backing, pad e
    resposta com um medidor em dB.
- **Músicas**: adicione uma música por arquivo de áudio, cantando a melodia ou digitando as notas. Num
  arquivo, o app **separa a voz do instrumental** e transcreve só o que é cantado; trechos sem voz aparecem
  como instrumentais. Para não confundir instrumento com voz ele observa a posição no estéreo (a voz fica no
  centro), os harmônicos, o vibrato, se a nota sustenta ou morre como num piano ou violão, se a linha cai
  exatamente na afinação temperada (teclas e trastes) ou flutua como a voz, notas longas paradas (pads) e
  notas soltas longe das frases cantadas. Na prática:
  - modo **Segunda voz** (qualquer um dos 8 tipos) ou **Backing vocal** (conforme a voz do regente);
  - música **original, sem voz (karaokê) ou com a voz em destaque**;
  - guias da melodia e da sua parte, frase a frase, repetição de trecho, velocidade 0,5× ou 0,75×,
    afinação ao vivo e medidor de equilíbrio do backing;
  - correção manual das notas da melodia, inclusive apagar de uma vez uma frase que era instrumental;
  - aviso quando a música toca no alto-falante sem fones, porque aí o microfone também ouve os instrumentos.
- **Estudar**: textos curtos sobre respiração, apoio, registros, intervalos, campo harmônico, tipos de
  segunda voz, backing vocal, equilíbrio, combinações de vozes, saúde vocal e rotina de estudo.

## Desempenho

- Detecção de altura ao vivo pelo método McLeod (MPM) com FFT: cerca de 0,06 ms por quadro de 23 ms.
- Extração da melodia de músicas mais de 100 vezes mais rápida que o tempo real, sem guardar o áudio.
- Uma única thread de áudio, com buffers alocados uma vez (sem coleta de lixo durante a captura).
- O microfone só fica ligado nas telas que precisam dele e desliga quando o app sai da tela.
- Gráficos desenhados direto no Canvas, sem recompor a interface a cada quadro.
- Sem bibliotecas além do Jetpack Compose; R8 e remoção de recursos não usados no APK final.
- Sem permissão de internet: nada sai do aparelho.

## Desenvolvimento

Android: Kotlin + Jetpack Compose, `minSdk` 26 (Android 8.0).

```
./gradlew testReleaseUnitTest   # testes da lógica de áudio e música
./gradlew assembleRelease       # APK em app/build/outputs/apk/release/
```

- `app/src/main/java/com/raulhrn/vox/core`: lógica pura (detecção de altura, extração da melodia vocal,
  segmentação de notas, tom, tipos de segunda voz, backing vocal, exercícios, conteúdo), coberta por testes
  em `app/src/test`. O pacote mantém o nome `vox` do primeiro nome do app.
- `audio`: microfone, sintetizador-guia, player com separação de voz e análise de arquivos.
- `ui`: telas e componentes.

iPhone: Swift + SwiftUI, iOS 17, na pasta `ios/`.

- `ios/CantorialCore`: pacote Swift com a mesma lógica do pacote `core` do Android (detecção de altura,
  extração da melodia vocal, segmentação, tom, segunda voz, backing vocal, exercícios), com testes que
  repetem os casos do Android. Os textos (exercícios, estudos, dicas e lições) vêm de
  `Resources/content.json`, gerado a partir do Kotlin para os dois apps ensinarem a mesma coisa:
  `gradle -p tools/content-export run`.
- `ios/Cantorial`: app (AVAudioEngine para microfone, sintetizador e player com separação de voz; telas em
  SwiftUI).
- `ios/project.yml`: projeto do Xcode gerado com o [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```
swift test --package-path ios/CantorialCore   # testes do núcleo (num Mac)
cd ios && xcodegen generate && open Cantorial.xcodeproj
```

### Assinatura

Sem configuração extra, o GitHub Actions assina o APK com uma chave de depuração guardada no cache do
Actions, para que versões novas instalem por cima das antigas. Se esse cache expirar (fica 7 dias sem uso),
a chave muda e será preciso desinstalar o app antes de instalar a versão nova.

Para uma assinatura fixa, crie uma chave e cadastre-a como secrets do repositório
(Settings → Secrets and variables → Actions):

```
keytool -genkeypair -keystore vox.keystore -alias vox -keyalg RSA -keysize 2048 -validity 20000
base64 -w0 vox.keystore   # conteúdo do secret VOX_KEYSTORE_BASE64
```

Secrets: `VOX_KEYSTORE_BASE64`, `VOX_KEYSTORE_PASSWORD`, `VOX_KEY_ALIAS` (ex.: `vox`) e `VOX_KEY_PASSWORD`.
Nunca coloque a chave nem as senhas no repositório.
