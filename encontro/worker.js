// Estenda · ponto de encontro (Cloudflare Worker + Durable Object)
//
// Só apresenta o tablet ao PC: os dois trocam aqui umas poucas mensagens (oferta, resposta e
// endereços do WebRTC) e depois conversam DIRETO, sem passar por este servidor. A imagem, o
// mouse, o teclado e a senha nunca passam por aqui.
//
// Rotas:
//   /sala/<id>?papel=pc&k=<chave>  WebSocket do PC. A primeira chave que entra numa sala fica dona
//                                  dela (guardada só como SHA-256): ninguém mais entra como PC.
//   /sala/<id>?papel=tab           WebSocket de um tablet (no máximo 8 por sala).
//   resto                          a página do tablet (pasta publico/).
//
// Mensagens (JSON): o tablet manda {t, ...} e o PC recebe {t, de, ...}; o PC manda {t, para, ...}
// e só aquele tablet recebe {t, ...}. A sala avisa {t:"pc", on} e {t:"saiu", de}.

import { DurableObject } from "cloudflare:workers";

const SALA_OK = /^[A-Za-z0-9_-]{16,64}$/;
const MAX_TABLETS = 8;
const MAX_MSG = 64 * 1024;
const TIPOS = new Set(["oferta", "resposta", "ice", "fim"]);

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const m = url.pathname.match(/^\/sala\/([^/]+)$/);
    if (!m) return env.ASSETS.fetch(req);
    if (!SALA_OK.test(m[1])) return new Response("sala inválida", { status: 400 });
    if (req.headers.get("Upgrade") !== "websocket") return new Response("use WebSocket", { status: 426 });
    return env.SALAS.get(env.SALAS.idFromName(m[1])).fetch(req);
  },
};

async function sha256(texto) {
  const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto));
  return [...new Uint8Array(h)].map(b => b.toString(16).padStart(2, "0")).join("");
}

export class Sala extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    // o "estou vivo" é respondido sem acordar a sala (não gasta nada)
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('{"t":"ping"}', '{"t":"pong"}'));
  }

  async fetch(req) {
    const url = new URL(req.url);
    const papel = url.searchParams.get("papel");
    const [cliente, servidor] = Object.values(new WebSocketPair());

    if (papel === "pc") {
      const k = url.searchParams.get("k") || "";
      if (k.length < 32) return new Response("chave curta", { status: 400 });
      const h = await sha256(k);
      const dona = await this.ctx.storage.get("chave");
      if (dona && dona !== h) return new Response("esta sala é de outro PC", { status: 403 });
      if (!dona) await this.ctx.storage.put("chave", h);
      for (const velho of this.ctx.getWebSockets("pc")) {
        try { velho.close(4000, "o PC entrou de novo"); } catch (_) {}
      }
      this.ctx.acceptWebSocket(servidor, ["pc"]);
      servidor.serializeAttachment({ papel: "pc" });
      this.avisarTablets({ t: "pc", on: true });
    } else if (papel === "tab") {
      if (this.ctx.getWebSockets("tab").length >= MAX_TABLETS) return new Response("sala cheia", { status: 429 });
      const n = crypto.randomUUID().replaceAll("-", "").slice(0, 12);
      this.ctx.acceptWebSocket(servidor, ["tab", "tab:" + n]);
      servidor.serializeAttachment({ papel: "tab", n });
      servidor.send(JSON.stringify({ t: "pc", on: this.ctx.getWebSockets("pc").length > 0 }));
    } else {
      return new Response("papel inválido", { status: 400 });
    }
    return new Response(null, { status: 101, webSocket: cliente });
  }

  avisarTablets(obj, exceto) {
    const texto = JSON.stringify(obj);
    for (const t of this.ctx.getWebSockets("tab")) {
      if (t !== exceto) try { t.send(texto); } catch (_) {}
    }
  }

  async webSocketMessage(ws, msg) {
    if (typeof msg !== "string" || msg.length > MAX_MSG) return;
    let m;
    try { m = JSON.parse(msg); } catch (_) { return; }
    if (!m || !TIPOS.has(m.t)) return;
    const quem = ws.deserializeAttachment() || {};
    if (quem.papel === "tab") {
      const pc = this.ctx.getWebSockets("pc")[0];
      if (!pc) return ws.send(JSON.stringify({ t: "pc", on: false }));
      m.de = quem.n;
      pc.send(JSON.stringify(m));
    } else if (quem.papel === "pc" && typeof m.para === "string") {
      const alvo = this.ctx.getWebSockets("tab:" + m.para)[0];
      if (!alvo) return;
      delete m.para;
      alvo.send(JSON.stringify(m));
    }
  }

  async webSocketClose(ws) {
    this.saiu(ws);
    try { ws.close(1000, "tchau"); } catch (_) {}
  }

  async webSocketError(ws) {
    this.saiu(ws);
  }

  saiu(ws) {
    const quem = ws.deserializeAttachment() || {};
    if (quem.papel === "tab") {
      const pc = this.ctx.getWebSockets("pc")[0];
      if (pc) try { pc.send(JSON.stringify({ t: "saiu", de: quem.n })); } catch (_) {}
    } else if (quem.papel === "pc") {
      const outro = this.ctx.getWebSockets("pc").some(p => p !== ws);
      if (!outro) this.avisarTablets({ t: "pc", on: false });
    }
  }
}
