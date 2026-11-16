"use strict";
/* Estenda · base comum à tela do tablet (remoto.html) e à ponte do PC (ponte.html)

   - SHA-256 e HMAC em JavaScript puro (em http:// o navegador não libera o crypto.subtle).
   - Cifra dos recados de encontro: só quem já pareou com o PC (e por isso tem o segredo) consegue
     ler ou escrever. O servidor de encontro vê apenas bytes embaralhados.
   - Cliente MQTT mínimo (3.1.1 sobre WebSocket): os pontos de encontro são servidores públicos de
     recados. Por eles passam só a oferta e a resposta do WebRTC (uns poucos KB, cifrados); a imagem
     e o controle vão direto entre o tablet e o PC.
   - Pedaços: o canal WebRTC não gosta de mensagens grandes, então elas vão fatiadas. */

const SHA = (() => {
  const K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]);
  function hash(bytes) {
    const n = bytes.length, total = ((n + 9 + 63) >> 6) << 6;
    const m = new Uint8Array(total);
    m.set(bytes); m[n] = 0x80;
    const dv = new DataView(m.buffer);
    dv.setUint32(total - 8, Math.floor(n / 0x20000000));
    dv.setUint32(total - 4, (n * 8) >>> 0);
    const H = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
    const W = new Uint32Array(64);
    for (let o = 0; o < total; o += 64) {
      for (let i = 0; i < 16; i++) W[i] = dv.getUint32(o + i * 4);
      for (let i = 16; i < 64; i++) {
        const a = W[i - 15], b = W[i - 2];
        W[i] = W[i - 16] + ((a >>> 7 | a << 25) ^ (a >>> 18 | a << 14) ^ (a >>> 3)) + W[i - 7]
             + ((b >>> 17 | b << 15) ^ (b >>> 19 | b << 13) ^ (b >>> 10));
      }
      let a = H[0], b = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
      for (let i = 0; i < 64; i++) {
        const t1 = (h + ((e >>> 6 | e << 26) ^ (e >>> 11 | e << 21) ^ (e >>> 25 | e << 7)) + ((e & f) ^ (~e & g)) + K[i] + W[i]) | 0;
        const t2 = (((a >>> 2 | a << 30) ^ (a >>> 13 | a << 19) ^ (a >>> 22 | a << 10)) + ((a & b) ^ (a & c) ^ (b & c))) | 0;
        h = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
      }
      H[0] += a; H[1] += b; H[2] += c; H[3] += d; H[4] += e; H[5] += f; H[6] += g; H[7] += h;
    }
    const out = new Uint8Array(32), odv = new DataView(out.buffer);
    for (let i = 0; i < 8; i++) odv.setUint32(i * 4, H[i]);
    return out;
  }
  function hmac(chave, msg) {
    if (chave.length > 64) chave = hash(chave);
    const k = new Uint8Array(64); k.set(chave);
    const dentro = new Uint8Array(64 + msg.length), fora = new Uint8Array(96);
    for (let i = 0; i < 64; i++) { dentro[i] = k[i] ^ 0x36; fora[i] = k[i] ^ 0x5c; }
    dentro.set(msg, 64);
    fora.set(hash(dentro), 64);
    return hash(fora);
  }
  const hex = b => Array.from(b, x => x.toString(16).padStart(2, "0")).join("");
  return { hash, hmac, hex };
})();

const Base = (() => {
  const utf8 = s => new TextEncoder().encode(s);
  const texto = b => new TextDecoder().decode(b);
  const aleatorio = n => crypto.getRandomValues(new Uint8Array(n));
  const hex = b => Array.from(b, x => x.toString(16).padStart(2, "0")).join("");
  function juntarBytes(...partes) {
    const p = partes.map(x => x instanceof Uint8Array ? x : Uint8Array.from(x));
    const out = new Uint8Array(p.reduce((s, x) => s + x.length, 0));
    let o = 0;
    for (const x of p) { out.set(x, o); o += x.length; }
    return out;
  }

  /* ---------------------------------------------------------------- cifra dos recados
     chave de fluxo = HMAC(ke, nonce || contador); etiqueta = HMAC(km, nonce || cifrado)  */
  function derivar(segredo) {
    const s = utf8(String(segredo));
    const h = rot => SHA.hmac(s, utf8("estenda/v1/" + rot));
    return { topico: hex(h("topico")).slice(0, 32), ke: h("cifra"), km: h("mac") };
  }
  function fluxo(ke, nonce, dados) {
    const out = new Uint8Array(dados.length), bloco = new Uint8Array(20);
    bloco.set(nonce);
    for (let i = 0, c = 0; i < dados.length; i += 32, c++) {
      bloco[16] = c >>> 24; bloco[17] = c >>> 16; bloco[18] = c >>> 8; bloco[19] = c;
      const ks = SHA.hmac(ke, bloco);
      for (let j = 0; j < 32 && i + j < dados.length; j++) out[i + j] = dados[i + j] ^ ks[j];
    }
    return out;
  }
  function selar(k, obj) {
    const nonce = aleatorio(16);
    const corpo = juntarBytes(nonce, fluxo(k.ke, nonce, utf8(JSON.stringify(obj))));
    return juntarBytes(corpo, SHA.hmac(k.km, corpo));
  }
  function abrir(k, dados) {
    if (!(dados instanceof Uint8Array) || dados.length < 49) return null;
    const corpo = dados.subarray(0, dados.length - 32), etiqueta = dados.subarray(dados.length - 32);
    const certa = SHA.hmac(k.km, corpo);
    let dif = 0;
    for (let i = 0; i < 32; i++) dif |= certa[i] ^ etiqueta[i];
    if (dif) return null;
    try { return JSON.parse(texto(fluxo(k.ke, corpo.subarray(0, 16), corpo.subarray(16)))); } catch (_) { return null; }
  }

  /* ---------------------------------------------------------------- MQTT mínimo */
  function varint(n) { const o = []; do { let b = n % 128; n = Math.floor(n / 128); if (n) b |= 128; o.push(b); } while (n); return o; }
  const campo = s => { const b = utf8(s); return juntarBytes([b.length >> 8, b.length & 255], b); };
  function pacote(tipo, ...partes) { const corpo = juntarBytes(...partes); return juntarBytes([tipo], varint(corpo.length), corpo); }

  class Mqtt {
    constructor(url, { aoConectar, aoMensagem, aoFechar } = {}) {
      this.url = url; this.aoConectar = aoConectar; this.aoMensagem = aoMensagem; this.aoFechar = aoFechar;
      this.pronto = false; this.fechado = false; this.buf = new Uint8Array(0); this.pid = 1; this.visto = Date.now();
      let ws;
      try { ws = this.ws = new WebSocket(url, "mqtt"); } catch (e) { setTimeout(() => this._fim(), 0); return; }
      ws.binaryType = "arraybuffer";
      ws.onopen = () => ws.send(pacote(0x10, campo("MQTT"), [4, 2, 0, 50], campo("est" + hex(aleatorio(8)))));
      ws.onmessage = e => { if (typeof e.data !== "string") this._dados(new Uint8Array(e.data)); };
      ws.onclose = () => this._fim();
      this.abertura = setTimeout(() => { if (!this.pronto) this.fechar(); }, 12000);
      this.pulso = setInterval(() => {
        if (!this.pronto) return;
        if (Date.now() - this.visto > 70000) return this.fechar();  // o servidor sumiu sem avisar
        try { ws.send(Uint8Array.of(0xC0, 0)); } catch (_) {}
      }, 25000);
    }
    _dados(novo) {
      this.visto = Date.now();
      let b = this.buf = this.buf.length ? juntarBytes(this.buf, novo) : novo;
      for (;;) {
        if (b.length < 2) break;
        let tam = 0, mult = 1, i = 1, completo = false;
        for (; i < b.length && i <= 4; i++) { tam += (b[i] & 127) * mult; mult *= 128; if (!(b[i] & 128)) { completo = true; i++; break; } }
        if (!completo) { if (i > 4) return this.fechar(); break; }
        if (b.length < i + tam) break;
        this._pacote(b[0], b.subarray(i, i + tam));
        b = b.subarray(i + tam);
      }
      this.buf = b.slice();
    }
    _pacote(cab, corpo) {
      const tipo = cab >> 4;
      if (tipo === 2) {  // CONNACK
        if (corpo[1] !== 0) return this.fechar();
        this.pronto = true; clearTimeout(this.abertura);
        if (this.aoConectar) this.aoConectar(this);
      } else if (tipo === 3) {  // PUBLISH
        const qos = (cab >> 1) & 3, n = (corpo[0] << 8) | corpo[1];
        const topico = texto(corpo.subarray(2, 2 + n));
        if (this.aoMensagem) this.aoMensagem(topico, corpo.slice(2 + n + (qos ? 2 : 0)));
      }
    }
    assinar(topico) { this._enviar(pacote(0x82, [this.pid >> 8, this.pid++ & 255], campo(topico), [0])); }
    publicar(topico, dados) { return this._enviar(pacote(0x30, campo(topico), dados)); }
    _enviar(p) { if (!this.pronto || this.ws.readyState !== 1) return false; try { this.ws.send(p); return true; } catch (_) { return false; } }
    fechar() { try { if (this.ws.readyState === 1) this.ws.send(Uint8Array.of(0xE0, 0)); this.ws.close(); } catch (_) {} this._fim(); }
    _fim() {
      if (this.fechado) return;
      this.fechado = true; this.pronto = false;
      clearTimeout(this.abertura); clearInterval(this.pulso);
      if (this.aoFechar) this.aoFechar(this);
    }
  }

  /* ---------------------------------------------------------------- encontro
     O PC escuta em .../pc; cada tablet escuta em .../t/<id sorteado>. O mesmo recado sai por todos
     os servidores que estiverem conectados (se um cair, os outros seguram) e os repetidos são ignorados. */
  class Encontro {
    constructor({ segredo, urls, papel, id, aoMensagem, aoEstado }) {
      this.k = derivar(segredo);
      this.papel = papel; this.id = id || hex(aleatorio(6));
      this.aoMensagem = aoMensagem; this.aoEstado = aoEstado;
      this.raiz = "estenda/v1/" + this.k.topico;
      this.caixa = papel === "pc" ? this.raiz + "/pc" : this.raiz + "/t/" + this.id;
      this.vistos = new Set(); this.fechado = false;
      this.linhas = urls.map(url => ({ url, mqtt: null, espera: 1000, timer: 0 }));
      this.linhas.forEach(l => this._ligar(l));
    }
    get total() { return this.linhas.length; }
    get conectados() { return this.linhas.filter(l => l.mqtt && l.mqtt.pronto).length; }
    _ligar(l) {
      if (this.fechado) return;
      l.mqtt = new Mqtt(l.url, {
        aoConectar: m => { l.espera = 1000; m.assinar(this.caixa); this._estado(); },
        aoMensagem: (topico, dados) => { if (topico === this.caixa) this._recado(dados); },
        aoFechar: () => {
          this._estado();
          if (this.fechado) return;
          l.timer = setTimeout(() => this._ligar(l), l.espera);
          l.espera = Math.min(30000, l.espera * 2);
        },
      });
    }
    _estado() { if (this.aoEstado && !this.fechado) this.aoEstado(this.conectados, this.total); }
    _recado(dados) {
      const m = abrir(this.k, dados);
      if (!m || typeof m._i !== "string" || this.vistos.has(m._i)) return;
      this.vistos.add(m._i);
      if (this.vistos.size > 600) this.vistos = new Set([...this.vistos].slice(-300));
      delete m._i;
      if (this.aoMensagem) this.aoMensagem(m);
    }
    /** tablet → PC: enviar(obj). PC → tablet: enviar(obj, idDoTablet). Devolve por quantos servidores saiu. */
    enviar(obj, para) {
      const topico = this.papel === "pc" ? this.raiz + "/t/" + para : this.raiz + "/pc";
      const recado = selar(this.k, { ...obj, de: this.papel === "pc" ? "pc" : this.id, _i: hex(aleatorio(8)) });
      let n = 0;
      for (const l of this.linhas) if (l.mqtt && l.mqtt.publicar(topico, recado)) n++;
      return n;
    }
    fechar() {
      this.fechado = true;
      for (const l of this.linhas) { clearTimeout(l.timer); if (l.mqtt) l.mqtt.fechar(); }
    }
  }

  /* ---------------------------------------------------------------- WebRTC: utilidades */
  const ICE = [{ urls: ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"] }];
  function impressao(sdp) {
    const m = /a=fingerprint:(\S+) ([0-9A-Fa-f:]+)/.exec(sdp || "");
    return m ? m[1].toLowerCase() + " " + m[2].toUpperCase() : "";
  }
  /** Espera o navegador juntar os endereços (ou "ms" milissegundos) e devolve o SDP já com eles. */
  function sdpCompleto(pc, ms = 2000) {
    return new Promise(ok => {
      const fim = () => { clearTimeout(t); pc.removeEventListener("icegatheringstatechange", ver); ok(pc.localDescription ? pc.localDescription.sdp : ""); };
      const ver = () => { if (pc.iceGatheringState === "complete") fim(); };
      const t = setTimeout(fim, ms);
      pc.addEventListener("icegatheringstatechange", ver);
      ver();
    });
  }
  const MAX_PARTE = 16000;
  /** Manda texto ou bytes em pedaços: byte 0 tem bit 1 = é texto e bit 0 = ainda vem mais. */
  function enviarPartes(dc, dados) {
    const eTexto = typeof dados === "string";
    const bytes = eTexto ? utf8(dados) : new Uint8Array(dados);
    let i = 0;
    do {
      const n = Math.min(MAX_PARTE, bytes.length - i), fim = i + n >= bytes.length;
      const parte = new Uint8Array(n + 1);
      parte[0] = (eTexto ? 2 : 0) | (fim ? 0 : 1);
      parte.set(bytes.subarray(i, i + n), 1);
      dc.send(parte);
      i += n;
    } while (i < bytes.length);
  }
  /** Junta os pedaços: devolve null enquanto falta, depois o texto ou o ArrayBuffer inteiro. */
  function juntarPartes(guarda, dados) {
    const b = new Uint8Array(dados), marca = b[0];
    guarda.push(b.slice(1));
    if (marca & 1) return null;
    const tudo = juntarBytes(...guarda.splice(0));
    return marca & 2 ? texto(tudo) : tudo.buffer;
  }

  return { utf8, texto, hex, aleatorio, derivar, selar, abrir, Mqtt, Encontro, ICE, impressao, sdpCompleto, enviarPartes, juntarPartes };
})();
if (typeof module !== "undefined") module.exports = { SHA, Base };
