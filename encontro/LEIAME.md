# Ponto de encontro do Estenda

Um Cloudflare Worker (grátis) que só apresenta o tablet ao PC para eles conversarem direto por
WebRTC. Também entrega a página do tablet, em https, que pode ser instalada como app.

- Publicar ou atualizar: rode `publicar.bat` (precisa do Node.js e de uma conta da Cloudflare).
- O que passa por aqui: oferta, resposta e endereços do WebRTC (umas poucas mensagens por conexão).
- O que NÃO passa: imagem, mouse, teclado, área de transferência, senha.
- Cada PC tem uma sala com id aleatório (vai no QR) e uma chave que só o PC conhece: ninguém
  mais entra na sala como PC. E o login do tablet é amarrado às impressões digitais do canal
  WebRTC, então nem este servidor consegue se colocar no meio da conexão.
- Plano grátis: 100 mil pedidos por dia, muito acima do que o Estenda usa.
