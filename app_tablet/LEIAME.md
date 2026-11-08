# Ponte Remota — app do tablet (Flutter)

App Android com os dois modos do Ponte Remota:

- **Espelhamento do Computador:** a tela do PC no tablet, com touchpad ou toque direto, teclado
  (com acentos), teclas especiais, atalhos do Windows, copiar e colar, qualidade e energia.
- **Segundo Monitor:** o tablet mostra um monitor extra do PC, com toque direto.

Visual em tons pastel (azul, menta, lavanda, pêssego), modo claro e escuro com transição suave.
O app acha o PC sozinho no mesmo Wi-Fi (o PC precisa estar com o acesso ligado no Ponte Remota).

## Gerar o APK (no PC)

1. Instale o Flutter e o Android Studio (https://docs.flutter.dev/get-started/install/windows/mobile)
   e rode `flutter doctor` até a linha do Android ficar OK.
2. Dê dois cliques em `gerar_apk.bat`. Ele cria a parte Android do projeto, libera a internet e a
   conexão na rede de casa no manifest, põe o ícone e gera `..\dist\PonteRemota-tablet.apk`.
3. Mande o APK para o tablet e instale (o Android pede para permitir "fontes desconhecidas").

Para testar direto no tablet ligado no cabo (depuração USB ativa): `flutter run`.

## Segundo monitor: o que o PC precisa

O Windows só cria um monitor novo com um driver de vídeo. Instale uma vez o **Virtual Display
Driver** (gratuito, código aberto) no PC. Ele aparece em Configurações > Sistema > Tela como um
monitor de verdade: escolha "Estender estas telas" e posicione ao lado do principal. O app usa
esse monitor sozinho no modo Segundo Monitor.

## Arquivos

| Arquivo | O que é |
|---|---|
| `lib/main.dart` | começo do app, temas |
| `lib/tema.dart` | paleta pastel, claro e escuro |
| `lib/estado.dart` | preferências e PCs salvos no tablet |
| `lib/conexao.dart` | protocolo do Ponte Remota: login, imagem, comandos |
| `lib/descoberta.dart` | acha o PC na rede (UDP 24861) |
| `lib/paginas/` | início, configurações, lista de PCs |
| `lib/sessao/` | tela remota, gestos, teclado, folhas (teclas, copiar, tela, energia, gestos) |
| `lib/widgets/comuns.dart` | cards que afundam ao tocar, seletor, fundo animado, ícones dos modos |
