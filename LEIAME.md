# Estenda

O PC no tablet: **espelhamento** (a mesma tela, controlada com o dedo) e **segundo monitor**, em
casa pelo Wi-Fi ou **de longe pela internet**, como o Remote Play do PlayStation, só que para o
Windows. Dois programas e mais nada: o `Estenda.exe` no PC e o app Estenda no tablet Android.

## Começar

1. **No PC:** baixe o `Estenda.exe` (em Releases, "Programa do PC") e abra. Ligue a chave **Acesso**.
   Na primeira vez, o Windows pergunta sobre o firewall: permita em **Redes privadas**.
2. **No tablet:** leia com a câmera o QR **"Instale o app no tablet"** do painel (ou abra
   `https://github.com/jaovb/Estenda/releases/latest/download/Estenda.apk`) e instale.
3. **Primeira vez, em casa:** abra o app no mesmo Wi-Fi do PC. Toque em **Dispositivos**: o PC aparece
   sozinho. Escolha um modo e digite a senha que aparece no painel do PC.
4. Pronto. Daí em diante o app entra sozinho, **em casa e de longe**.

Fechar a janela do PC desliga o acesso e encerra o programa. Marque **Iniciar com o Windows** para o
acesso voltar sozinho quando você entra na conta.

## Como funciona de longe

Sem configurar nada e sem Tailscale. O tablet primeiro tenta o caminho de casa (milissegundos); se
o PC não responde, ele procura o PC pela internet:

- Os dois trocam um recado curto (a "oferta" e a "resposta" do WebRTC) por **servidores públicos de
  recados** (MQTT). Os recados vão **cifrados** com um segredo que só aparelhos já pareados recebem;
  os servidores só veem bytes embaralhados. São três servidores, e basta um funcionar.
- Com os endereços trocados, os dois **abrem um caminho direto** entre os roteadores (hole punching,
  com STUN) e a imagem e o controle vão **direto**, criptografados de ponta a ponta (DTLS). Nada da
  sua tela passa por servidor nenhum.
- O login é amarrado às impressões digitais do canal: nem quem estiver no meio consegue se passar
  pelo PC ou pelo tablet.

Em algumas redes (sobretudo 4G/5G com NAT muito restritivo nos dois lados) o caminho direto não abre;
o app avisa "a rede não deixou um caminho direto". De propósito, não há retransmissão por servidor.

O PC usa o WebRTC do próprio Edge, rodando escondido enquanto o acesso de longe está ligado. Dá
para desligar em Configurações › **Usar de longe**.

## Segundo monitor

O Windows só cria uma tela nova com um driver. Instale uma vez o **Virtual Display Driver** (grátis,
código aberto): no painel, toque em **Segundo monitor › Criar a tela do tablet**, ou rode o
`criar-tela-do-tablet.bat`. Depois, em Configurações do Windows › Sistema › Tela, deixe a tela nova
em **Estender**. No tablet, escolha **Segundo monitor**.

## Gestos

| | Toque direto (padrão) | Touchpad |
|---|---|---|
| Clicar | toque onde quer | toque |
| Mover o cursor | — | arraste um dedo |
| Clique direito | segure até vibrar | toque com dois dedos |
| Arrastar / selecionar | arraste um dedo | segure até vibrar e arraste |
| Rolar | arraste dois dedos | arraste dois dedos |
| Zoom | pinça | pinça |
| Teclado | toque com três dedos | toque com três dedos |

Mouse e teclado Bluetooth/USB ligados no tablet funcionam direto.

## Segurança

- A senha não passa pela rede: o PC manda um número aleatório e o tablet responde com um
  HMAC-SHA256 dele. O tablet lembrado usa uma chave própria, que dá para esquecer no painel.
- 5 erros seguidos bloqueiam aquele endereço por um tempo que dobra a cada novo erro.
- A porta do PC (24860) só aceita a rede de casa e o Tailscale. De longe, a conexão vem pela ponte
  WebRTC do próprio PC, só para aparelhos que já entraram uma vez.
- Em casa, a imagem vai pela rede local sem cifra; de longe, sempre cifrada.
- Senha, aparelhos lembrados, opções e registro ficam em `C:\Users\<você>\.ponte-remota\`.

## Limitações (honestas)

- **Sem som** nesta versão: só imagem e controle.
- **Tela de bloqueio e avisos do administrador (UAC)** não aparecem no tablet (o Windows protege
  essas telas).
- **Ctrl+Alt+Del** não passa por nenhum programa; use Ctrl+Shift+Esc.
- **Ligar o PC de longe** ainda não (Wake-on-LAN não funciona no Wi-Fi).
- **iPhone/iPad:** não há app; use o QR do navegador (só em casa).

## Testes automáticos

A cada envio de código, o GitHub roda (Actions › "Testes"):

- **Pontos de encontro públicos:** cada servidor conecta e entrega um recado cifrado.
- **Ponta a ponta:** PC simulado + a tela do tablet: em casa com senha, depois sem senha, de longe,
  troca automática casa → longe, PC diferente no mesmo endereço, segundo monitor, servidor de encontro
  fora do ar, desligar o de longe, navegador comum. Com servidores simulados e com os de verdade.
- **App nativo no emulador Android:** instala o APK e confere que a tela do PC chega, em casa e de longe.
- **Duas redes:** PC num servidor Linux e tablet num Mac, em redes diferentes, atravessando os roteadores.

Para rodar aqui: `python testes/e2e.py` (precisa de Chrome e `pip install pillow playwright`).

## Arquivos

| Arquivo | O que é |
|---|---|
| `app.py` | o programa do PC: painel, ponte de longe, instância única, iniciar com o Windows |
| `remoto.py` | o servidor que o tablet usa (WebSocket), login e sessões |
| `tela.py` | captura da tela e compressão por blocos (só manda o que mudou) |
| `controle_win.py` | mouse, teclado, área de transferência e energia no Windows (ctypes) |
| `controle.py`, `controle_sim.py` | escolhe o controle; o simulado serve para testar fora do Windows |
| `qr.py` | gerador de QR Code (sem bibliotecas) |
| `comum.py` | pasta de dados, senha, registro, pontos de encontro |
| `interface/painel.html` | o painel do PC |
| `interface/remoto.html` | a tela do tablet (vai embutida no app; também abre no navegador) |
| `interface/base.js` | cifra, cliente MQTT e WebRTC, comuns ao tablet e à ponte |
| `interface/ponte.html` | a ponte de longe do PC (roda escondida no Edge) |
| `app_tablet/` | o app Android (Flutter) |
| `testes/` | testes automáticos |
