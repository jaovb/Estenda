# Ponte Remota

A tela do PC no tablet (ou no celular), em casa ou de longe, controlada com o dedo, como o
Remote Play do PlayStation, só que para o Windows. O tablet não instala nada: abre uma página
no Chrome. Feito no mesmo estilo da Ponte KVM.

## Instalar no PC (Windows)

**Jeito mais simples:** dê dois cliques em `instalar.bat`. Ele confere o Python (oferece instalar
pelo winget se faltar), instala as bibliotecas `mss` e `pillow` e cria o atalho **Ponte Remota** na
Área de Trabalho e no Menu Iniciar.

**Executável (.exe), sem depender do Python depois:** rode `construir.bat`. Sai `dist\PonteRemota.exe`.
Para um instalador com desinstalador, rode depois o `gerar_instalador.bat`. Também dá para gerar
pelo GitHub: suba a pasta, vá em Actions → "Gerar executável" → Run workflow.

Na primeira vez que ligar o acesso, o Windows pergunta sobre o firewall: permita em **Redes
privadas**. Se o tablet não conectar mesmo assim, rode `liberar_firewall.bat` (pede administrador;
libera a porta só para o Tailscale e a rede de casa).

## Usar

1. Abra o Estenda (Ponte Remota) no PC e ligue a chave **Acesso**.
2. No tablet, aponte a câmera para o **QR do navegador** do painel: ele abre a página e entra sem senha
   (o QR vale 10 minutos, uma vez só). Funciona no Chrome do Android e no Safari do iPhone/iPad.
   Ou digite no navegador o endereço mostrado e a senha.
   - **Instalar o app Android pelo QR:** depois de gerar o APK (`app_tablet\gerar_apk.bat`), o painel
     mostra um segundo QR. A câmera do tablet baixa o app direto do PC, pelo Wi-Fi de casa.
3. Pronto. A barra no alto do tablet tem teclado, modo do toque, teclas especiais, copiar e colar,
   tela e qualidade, energia e a ajuda dos gestos. Ela se esconde sozinha; toque na alça para voltar.

Fechar a janela do PC **desliga o acesso e encerra o app**. Só com **Iniciar com o Windows** ele roda
sem janela; abrir o atalho mostra o painel, e fechar o painel encerra.

Marque **Iniciar com o Windows** para o acesso voltar sozinho depois de reiniciar (ele liga quando
você entra na conta do Windows).

## App nativo no tablet (Android), compilado pelo GitHub

Sem instalar Flutter nem Android Studio no PC: o GitHub compila o app na nuvem, de graça.

1. Em github.com, crie um repositório **privado** (ex.: `estenda`).
2. Clique em **uploading an existing file** e arraste para lá **tudo** o que está dentro da pasta
   do Estenda (inclusive a pasta `.github`). Clique em **Commit changes**.
3. Em **Actions**, o "App do tablet" e o "Programa do PC" começam sozinhos (uns 10 minutos na
   primeira vez). O do PC gera o `Estenda.exe`, que roda sem Python: baixe em Releases.
4. No tablet, abra `https://github.com/SEU-USUARIO/estenda/releases/latest/download/Estenda.apk`
   (entre na sua conta do GitHub no navegador do tablet, porque o repositório é privado), toque
   no arquivo e permita instalar.

Para atualizar: suba os arquivos novos do mesmo jeito; o app instala por cima.
Se a compilação der erro (bolinha vermelha em Actions), abra, copie o erro e me mande.

## Usar o tablet como uma tela a mais

1. No painel, toque no cartão **Segundo monitor** › **Criar a tela do tablet**. O Windows pede
   permissão uma vez (clique em Sim). Ele instala o Virtual Display Driver, gratuito e de código
   aberto, e aparece uma tela nova em Configurações › Sistema › Tela.
2. Lá, deixe em **Estender estas telas** e arraste a tela nova para o lado do monitor principal.
3. No tablet, escolha **Segundo monitor**. Arraste janelas para lá como num monitor de verdade.

## Usar de longe e instalar o app (sem Tailscale)

O tablet e o PC conversam **direto** (WebRTC, criptografado de ponta a ponta). Um "ponto de
encontro" seu, grátis na Cloudflare, só apresenta os dois: troca umas 4 mensagens e sai do caminho.
A imagem, o mouse, o teclado e a senha nunca passam por ele.

1. Dê dois cliques em `encontro\publicar.bat`. Ele instala o Node.js se faltar, abre o navegador
   para você entrar (ou criar, grátis) na conta da Cloudflare, publica e já configura o Estenda.
   Na primeira vez a Cloudflare pode perguntar um nome para o seu endereço `workers.dev`:
   escreva qualquer nome e Enter.
2. No painel, o cartão do acesso mostra "De longe: pronto".
3. Leia o QR **App (casa e longe)** com o tablet ou o iPhone. Ele abre o Estenda e entra sem senha.
   - **Android:** toque em **Instalar o app Estenda** (ou no menu do Chrome › Instalar app).
   - **iPhone/iPad:** Compartilhar › **Adicionar à Tela de Início**.
   Depois, é só abrir o ícone: funciona em casa e fora, e entra sozinho.

O lado do PC usa o WebRTC do próprio Edge, rodando escondido enquanto o acesso de longe está
ligado (aparece como "msedge" no Gerenciador de Tarefas). Fechar o Estenda fecha ele também.

**Quando não conecta de longe:** algumas redes (sobretudo 4G/5G, com os dois lados atrás de NAT
restrito) não deixam abrir o caminho direto. Aí o tablet avisa "a rede não deixou um caminho
direto": tente outro Wi-Fi ou os dados do celular. Por enquanto não há retransmissão (TURN), de
propósito, para nada passar por servidor.

Sempre que atualizar o Estenda, rode o `publicar.bat` de novo (ele atualiza a página do tablet).

## Usar de longe (Tailscale, opcional)

O Tailscale liga o tablet ao PC como se estivessem no mesmo Wi-Fi, de qualquer lugar, com tudo
cifrado, e funciona mesmo com operadora que usa CGNAT (sem abrir porta no roteador). É grátis para
uso pessoal.

- **No PC:** instale em tailscale.com/download e entre com uma conta (Google, Microsoft, GitHub).
- **No tablet:** instale o Tailscale pela Play Store, entre com a **mesma conta** e ligue.
- No painel aparece o endereço que começa com `100.` e o QR "De qualquer lugar".

Não abra a porta no roteador: o Ponte Remota recusa conexões vindas da internet aberta.

## Gestos

| | Touchpad (padrão) | Toque direto |
|---|---|---|
| Mover o cursor | arraste um dedo | — |
| Clicar | toque | toque onde quer |
| Clique direito | toque com dois dedos | segure até vibrar |
| Arrastar / selecionar | segure até vibrar e arraste | arraste um dedo |
| Rolar | arraste dois dedos | arraste dois dedos |
| Zoom | pinça | pinça |
| Teclado | toque com três dedos | toque com três dedos |

Mouse e teclado Bluetooth/USB ligados no tablet funcionam direto.

## Segurança

- A porta (24860) só aceita o Tailscale (100.64.0.0/10) e a rede de casa; da internet, nunca.
- A senha não passa pela rede: o PC manda um número aleatório e o tablet responde com um
  HMAC-SHA256 dele. O tablet lembrado usa uma chave própria, que dá para esquecer no painel.
- 5 erros seguidos bloqueiam aquele endereço por um tempo que dobra a cada novo erro.
- Pelo Tailscale, imagem e teclado vão cifrados. Pela rede de casa sem Tailscale, não: em Wi-Fi de
  outras pessoas, use o Tailscale ou ligue **Só aceitar pelo Tailscale**.
- Senha, aparelhos lembrados, opções e registro ficam em `C:\Users\<você>\.ponte-remota\`.

## Limitações (honestas)

- **Sem som** nesta versão: só imagem e controle.
- **Tela de bloqueio e avisos do administrador (UAC)** não aparecem no tablet: o Windows protege
  essas telas. Bloquear o PC pelo tablet tira o seu acesso até alguém entrar no PC.
- **Ctrl+Alt+Del** não passa por nenhum programa; use Ctrl+Shift+Esc.
- **Janelas abertas como administrador** só aceitam o controle se o Ponte Remota também rodar
  como administrador.
- **De longe** precisa do ponto de encontro (Cloudflare, grátis) e, em algumas redes móveis, o
  caminho direto não abre (veja acima).
- **Ligar o PC de longe** ainda não (Wake-on-LAN não funciona no Wi-Fi). Próximo passo: tomada
  inteligente ou ESP32 no botão de ligar.
- **Jogos:** a imagem é JPEG por blocos, feita para trabalhar. Para jogar, Sunshine + Moonlight.
- Depois de reiniciar, o acesso só volta quando alguém entra na conta do Windows (a não ser que
  o login automático esteja ligado).

## Problemas

- **"Não encontrei o PC"**: o acesso está ligado? PC acordado? De longe, o Tailscale está ligado
  nos dois, na mesma conta? Rode `liberar_firewall.bat`. No ícone do Tailscale do PC, confira que
  "Allow incoming connections" está marcado.
- **"Este PC não aceita conexões deste endereço"**: "Só aceitar pelo Tailscale" está ligado e o
  tablet veio pelo Wi-Fi. Ligue o Tailscale no tablet.
- **Imagem lenta**: no tablet, em Tela, escolha "Leve" ou 15 fps. O app também diminui a qualidade
  sozinho quando a rede aperta e deixa a imagem nítida quando ela para.
- **Algo estranho**: o registro fica em `C:\Users\<você>\.ponte-remota\registro.txt` (e no painel,
  em "Registro de atividade").

## Arquivos

| Arquivo | O que é |
|---|---|
| `app.py` | o aplicativo: painel, segundo plano, instância única, iniciar com o Windows |
| `remoto.py` | o servidor que o tablet abre (página + WebSocket), login e sessões |
| `tela.py` | captura da tela e compressão por blocos (só manda o que mudou) |
| `controle_win.py` | mouse, teclado, área de transferência e energia no Windows (ctypes) |
| `controle.py`, `controle_sim.py` | escolhe o controle; o simulado serve para testar fora do Windows |
| `qr.py` | gerador de QR Code (sem bibliotecas) |
| `comum.py` | pasta de dados, senha, registro, endereços do Tailscale |
| `interface/painel.html` | o painel do PC |
| `interface/remoto.html` | a página do tablet |
| `instalar.bat`, `abrir.bat`, `PonteRemota.pyw` | instalar e abrir sem gerar .exe |
| `construir.bat`, `gerar_instalador.bat`, `instalador.iss` | gerar o .exe e o instalador |
| `liberar_firewall.bat` | libera a porta no firewall (só Tailscale e rede de casa) |

Para testar fora do Windows (Linux/Mac), com tela e controle simulados:
`PONTE_REMOTA_SIMULAR=1 python3 app.py --com-terminal`.
