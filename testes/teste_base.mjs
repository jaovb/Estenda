// Testa o cliente MQTT e o Encontro do base.js contra um ou mais servidores.
// Uso: node teste_base.mjs ws://127.0.0.1:28801 ws://127.0.0.1:28802     (ou os públicos, wss://...)
import { createRequire } from "module";
const { Base } = createRequire(import.meta.url)("../interface/base.js");
const urls = process.argv.slice(2);
const espera = (ms) => new Promise(r => setTimeout(r, ms));
let falhas = 0;
const t = (c, nome) => { console.log((c ? "ok     " : "FALHOU ") + nome); if (!c) falhas++; };

// 1) cada servidor, sozinho: dois clientes trocam um recado cifrado
const bons = [];
for (const url of urls) {
  const segredo = Base.hex(Base.aleatorio(16));
  const visto = [];
  const pc = new Base.Encontro({ segredo, urls: [url], papel: "pc", aoMensagem: m => visto.push(m) });
  const tab = new Base.Encontro({ segredo, urls: [url], papel: "tab" });
  const t0 = Date.now();
  while (Date.now() - t0 < 12000 && !(pc.conectados && tab.conectados)) await espera(100);
  const ligou = pc.conectados === 1 && tab.conectados === 1, tLigar = Date.now() - t0;
  let chegou = false, tIda = 0;
  if (ligou) {
    await espera(600);  // dá tempo da assinatura valer
    const t1 = Date.now();
    tab.enviar({ t: "oferta", sdp: "x".repeat(3000) });
    while (Date.now() - t1 < 6000 && !visto.length) await espera(50);
    chegou = visto.length === 1 && visto[0].t === "oferta" && visto[0].sdp.length === 3000 && visto[0].de === tab.id;
    tIda = Date.now() - t1;
  }
  t(ligou && chegou, `${url}  conectou em ${tLigar} ms, recado de 3 KB em ${tIda} ms`);
  if (ligou && chegou) bons.push(url);
  pc.fechar(); tab.fechar();
}

// 2) todos juntos: o recado sai por todos e chega uma vez só; a resposta volta só para aquele tablet
if (bons.length) {
  const segredo = Base.hex(Base.aleatorio(16));
  const noPc = [], noTab = [], noOutro = [], noIntruso = [];
  const pc = new Base.Encontro({ segredo, urls: bons, papel: "pc", aoMensagem: m => noPc.push(m) });
  const tab = new Base.Encontro({ segredo, urls: bons, papel: "tab", aoMensagem: m => noTab.push(m) });
  const outro = new Base.Encontro({ segredo, urls: bons, papel: "tab", aoMensagem: m => noOutro.push(m) });
  const intruso = new Base.Encontro({ segredo: "outro-segredo", urls: bons, papel: "pc", aoMensagem: m => noIntruso.push(m) });
  const t0 = Date.now();
  while (Date.now() - t0 < 12000 && !(pc.conectados === bons.length && tab.conectados === bons.length && outro.conectados === bons.length)) await espera(100);
  await espera(800);
  const saiu = tab.enviar({ t: "oferta", n: 1 });
  await espera(2500);
  t(saiu === bons.length && noPc.length === 1, `oferta saiu por ${saiu} servidor(es) e chegou ${noPc.length} vez ao PC`);
  pc.enviar({ t: "resposta", n: 2 }, noPc[0] ? noPc[0].de : "x");
  await espera(2500);
  t(noTab.length === 1 && noTab[0].de === "pc" && noOutro.length === 0, "resposta chegou só ao tablet certo, uma vez");
  t(noIntruso.length === 0, "quem não tem o segredo não recebe nada");
  for (const e of [pc, tab, outro, intruso]) e.fechar();
}
console.log(`\nservidores bons: ${bons.length}/${urls.length}  ${bons.join(" ")}`);
await espera(300);
process.exit(falhas && !process.env.SO_INFORMAR ? 1 : 0);
