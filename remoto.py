"""Ponte Remota: o servidor que o tablet acessa.

Uma porta só (padrão 24860) serve a página (interface/remoto.html) e a conexão em tempo
real (WebSocket em /ws), tudo com a biblioteca padrão do Python.

Segurança:
- só aceita conexões do Tailscale (100.64.0.0/10) e da rede de casa; da internet aberta, nunca;
- a senha não passa pela rede: o PC manda um número aleatório e o tablet devolve um
  HMAC-SHA256 dele com a senha (ou com a chave do aparelho lembrado, ou do convite do QR);
- 5 erros seguidos bloqueiam aquele endereço por um tempo que dobra a cada novo erro.
Pelo Tailscale tudo vai cifrado (WireGuard). Na rede de casa sem Tailscale, a imagem e o
que se digita passam sem cifra: por isso a opção "só pelo Tailscale".
"""
from __future__ import annotations

import asyncio
import urllib.parse
import base64
import hashlib
import hmac
import json
import os
import secrets
import socket
import struct
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import comum
import controle
import tela

GUID_WS = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
LIMITE_MSG = 2 * 1024 * 1024
MAX_EM_TRANSITO = 2     # quadros enviados e ainda não desenhados: segura o atraso em rede lenta
TEMPO_LOGIN = 120
CONTAGEM_ENERGIA = 10   # segundos para cancelar antes de desligar/reiniciar
PORTA_DESCOBERTA = 24861  # UDP: o app do tablet pergunta "PONTE-REMOTA?" e o PC responde
ARQUIVOS = {
    "/": ("remoto.html", "text/html; charset=utf-8"),
    "/index.html": ("remoto.html", "text/html; charset=utf-8"),
    "/icone.png": ("icone.png", "image/png"),
    "/favicon.ico": ("icone.png", "image/png"),
    "/icone-192.png": ("icone-192.png", "image/png"),
    "/icone-512.png": ("icone-512.png", "image/png"),
    "/icone-mascara.png": ("icone-mascara.png", "image/png"),
    "/icone-apple.png": ("icone-apple.png", "image/png"),
    "/fontes/SpaceGrotesk.ttf": ("fontes/SpaceGrotesk.ttf", "font/ttf"),
    "/fontes/JetBrainsMono.ttf": ("fontes/JetBrainsMono.ttf", "font/ttf"),
}
TEXTO_HTTP = {200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed"}


def _b64(dados: bytes) -> str:
    return base64.b64encode(dados).decode()


def _assinatura(chave: str, nonce: bytes) -> bytes:
    return hmac.new(chave.encode("utf-8"), nonce, hashlib.sha256).digest()


# ---------------------------------------------------------------- WebSocket (RFC 6455)

class WebSocket:
    def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        self.r, self.w = reader, writer
        self._lock = asyncio.Lock()
        self.fechado = False

    async def _quadro(self, op: int, dados: bytes) -> None:
        n = len(dados)
        if n < 126:
            cab = struct.pack("!BB", 0x80 | op, n)
        elif n < 65536:
            cab = struct.pack("!BBH", 0x80 | op, 126, n)
        else:
            cab = struct.pack("!BBQ", 0x80 | op, 127, n)
        async with self._lock:
            if self.fechado and op != 8:
                raise ConnectionError("fechado")
            self.w.write(cab + dados if n < 4096 else cab)
            if n >= 4096:
                self.w.write(dados)
            await self.w.drain()

    async def enviar(self, dados) -> None:
        if isinstance(dados, str):
            await self._quadro(1, dados.encode("utf-8"))
        else:
            await self._quadro(2, bytes(dados))

    async def enviar_json(self, obj) -> None:
        await self.enviar(json.dumps(obj, ensure_ascii=False, separators=(",", ":")))

    async def receber(self):
        """Texto (str), binário (bytes) ou None quando a conexão acaba."""
        partes, op_msg, total = [], None, 0
        try:
            while True:
                b0, b1 = await self.r.readexactly(2)
                fin, op, mascarado, n = b0 & 0x80, b0 & 0x0F, b1 & 0x80, b1 & 0x7F
                if b0 & 0x70 or not mascarado:
                    await self.fechar(1002)
                    return None
                if n == 126:
                    n = struct.unpack("!H", await self.r.readexactly(2))[0]
                elif n == 127:
                    n = struct.unpack("!Q", await self.r.readexactly(8))[0]
                if n > LIMITE_MSG:
                    await self.fechar(1009)
                    return None
                mascara = await self.r.readexactly(4)
                dados = await self.r.readexactly(n)
                if n:
                    m = (mascara * (n // 4 + 1))[:n]
                    dados = (int.from_bytes(dados, "big") ^ int.from_bytes(m, "big")).to_bytes(n, "big")
                if op >= 8:  # controle
                    if not fin or n > 125:
                        await self.fechar(1002)
                        return None
                    if op == 8:
                        await self.fechar(1000)
                        return None
                    if op == 9:
                        await self._quadro(0xA, dados)
                    continue
                if op == 0:
                    if op_msg is None:
                        await self.fechar(1002)
                        return None
                elif op in (1, 2):
                    if op_msg is not None:
                        await self.fechar(1002)
                        return None
                    op_msg = op
                else:
                    await self.fechar(1002)
                    return None
                partes.append(dados)
                total += n
                if total > LIMITE_MSG:
                    await self.fechar(1009)
                    return None
                if fin:
                    corpo = b"".join(partes)
                    return corpo.decode("utf-8", "replace") if op_msg == 1 else corpo
        except (asyncio.IncompleteReadError, ConnectionError, OSError):
            self.fechado = True
            return None

    async def receber_json(self):
        while True:
            dado = await self.receber()
            if dado is None:
                return None
            if isinstance(dado, str):
                try:
                    obj = json.loads(dado)
                except ValueError:
                    continue
                if isinstance(obj, dict):
                    return obj

    async def fechar(self, codigo: int = 1000) -> None:
        if self.fechado:
            return
        try:
            await asyncio.wait_for(self._quadro(8, struct.pack("!H", codigo)), 2)
        except Exception:
            pass
        self.fechado = True
        try:
            self.w.close()
        except Exception:
            pass


# ---------------------------------------------------------------- aparelhos lembrados

class Aparelhos:
    ARQ = "aparelhos.json"

    def __init__(self):
        self._lock = threading.Lock()
        self.lista = [a for a in comum.ler_json(self.ARQ, {}).get("aparelhos", [])
                      if isinstance(a, dict) and a.get("id") and a.get("token")]

    def _salvar(self) -> None:
        comum.salvar_json(self.ARQ, {"aparelhos": self.lista}, secreto=True)

    def novo(self, nome: str) -> dict:
        ap = {"id": secrets.token_hex(6), "nome": (nome or "Aparelho")[:60],
              "token": secrets.token_urlsafe(32), "criado": time.time(), "visto": time.time()}
        with self._lock:
            self.lista.append(ap)
            self._salvar()
        return ap

    def achar(self, ident: str):
        with self._lock:
            return next((a for a in self.lista if a["id"] == ident), None)

    def visto(self, ident: str) -> None:
        with self._lock:
            for a in self.lista:
                if a["id"] == ident:
                    a["visto"] = time.time()
            self._salvar()

    def esquecer(self, ident: str | None) -> None:
        with self._lock:
            self.lista = [a for a in self.lista if ident is not None and a["id"] != ident]
            self._salvar()

    def publico(self) -> list:
        with self._lock:
            return [{k: a.get(k) for k in ("id", "nome", "criado", "visto")} for a in self.lista]


# ---------------------------------------------------------------- descoberta na rede

class _Descoberta(asyncio.DatagramProtocol):
    def __init__(self, srv):
        self.srv = srv
        self.t = None

    def connection_made(self, transport):
        self.t = transport

    def datagram_received(self, dados, addr):
        if dados.strip() != b"PONTE-REMOTA?" or not self.srv._permitido(comum.tipo_de_ip(addr[0])):
            return
        resp = {"ponte": comum.PROTOCOLO, "pc": self.srv.nome_pc, "porta": self.srv.porta}
        self.t.sendto(json.dumps(resp, ensure_ascii=False).encode(), addr)


# ---------------------------------------------------------------- servidor

class ServidorRemoto:
    def __init__(self, pasta_interface: Path, obter_cfg, obter_senha, nome_pc: str):
        self.pasta = Path(pasta_interface)
        self.apk = None   # caminho do app Android, se existir: o tablet baixa em /estenda.apk (QR no painel)
        self.cfg = obter_cfg
        self.senha = obter_senha
        self.nome_pc = nome_pc
        self.aparelhos = Aparelhos()
        self.captura = tela.Captura()
        self.porta = None
        self.loop = None
        self._thread = None
        self._servidores = []
        self.sessoes = {}
        self.falhas = {}
        self.convite = None          # (token, expira_em monotonic)
        self.energia = None          # (acao, prazo time.time, handle)
        self._avisados = {}
        self.lock = threading.Lock()
        self.ao_fim_sessao = None  # chamado com a duração (s) de cada sessão, para o "uso na semana"
        self.token_ponte = None    # a ponte WebRTC (navegador sem janela, neste PC) entra em /ws-ponte com ele

    # --- ligar / desligar (chamados pelo painel, de outra linha de execução)
    @property
    def ligado(self) -> bool:
        return self.loop is not None and self._thread is not None and self._thread.is_alive()

    def iniciar(self, porta: int) -> None:
        if self.ligado:
            return
        pronto, erro = threading.Event(), []

        def rodar():
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                loop.run_until_complete(self._abrir(porta))
            except OSError as e:
                erro.append(e)
                pronto.set()
                loop.close()
                return
            self.loop = loop
            pronto.set()
            try:
                loop.run_forever()
            finally:
                try:
                    loop.run_until_complete(asyncio.sleep(0))
                    loop.close()
                except Exception:
                    pass

        self._thread = threading.Thread(target=rodar, name="remoto", daemon=True)
        self._thread.start()
        pronto.wait(10)
        if erro:
            self._thread = None
            raise erro[0]
        self.porta = porta
        comum.log(f"acesso remoto ligado na porta {porta}")

    async def _abrir(self, porta: int) -> None:
        self.porta = porta
        self._servidores = [await asyncio.start_server(self._conexao, "0.0.0.0", porta, limit=65536)]
        self._descoberta = None
        try:  # o app do tablet acha o PC sozinho na rede
            self._descoberta, _ = await asyncio.get_running_loop().create_datagram_endpoint(
                lambda: _Descoberta(self), local_addr=("0.0.0.0", PORTA_DESCOBERTA))
        except OSError as e:
            comum.log(f"descoberta na rede desligada (porta {PORTA_DESCOBERTA} ocupada: {e})")
        try:  # IPv6 é opcional (nomes do Tailscale às vezes resolvem para IPv6)
            self._servidores.append(await asyncio.start_server(self._conexao, "::", porta, limit=65536))
        except (OSError, ValueError):
            pass

    def parar(self) -> None:
        loop, thread = self.loop, self._thread
        if not loop or not thread:
            return
        fut = asyncio.run_coroutine_threadsafe(self._fechar_tudo("O acesso foi desligado no PC."), loop)
        try:
            fut.result(5)
        except Exception:
            pass
        loop.call_soon_threadsafe(loop.stop)
        thread.join(5)
        self.loop = self._thread = None
        self.porta = None
        with self.lock:
            self.convite = None
        comum.log("acesso remoto desligado")

    async def _fechar_tudo(self, motivo: str) -> None:
        for srv in self._servidores:
            srv.close()
        if getattr(self, "_descoberta", None):
            self._descoberta.close()
        await asyncio.gather(*(s.encerrar(motivo) for s in list(self.sessoes.values())), return_exceptions=True)
        self._cancelar_energia(avisar=False)
        for _ in range(40):  # dá tempo de cada sessão soltar teclas e botões apertados
            if not self.sessoes:
                break
            await asyncio.sleep(0.05)

    def _no_loop(self, coro_ou_func, *args):
        loop = self.loop
        if not loop:
            return
        if asyncio.iscoroutinefunction(coro_ou_func):
            asyncio.run_coroutine_threadsafe(coro_ou_func(*args), loop)
        else:
            loop.call_soon_threadsafe(coro_ou_func, *args)

    # --- usados pelo painel
    def lista_sessoes(self) -> list:
        return [s.resumo() for s in list(self.sessoes.values())]

    def derrubar(self, ident: str) -> None:
        s = self.sessoes.get(ident)
        if s:
            self._no_loop(s.encerrar, "Desconectado pelo PC.")

    def esquecer_aparelho(self, ident: str | None) -> None:
        self.aparelhos.esquecer(ident)
        for s in list(self.sessoes.values()):
            if s.aparelho and (ident is None or s.aparelho == ident):
                self._no_loop(s.encerrar, "Este aparelho foi esquecido no PC. Entre de novo com a senha.")

    def aplicar_filtro(self) -> None:
        """Depois de ligar "só pelo Tailscale", derruba quem já tinha entrado pela rede de casa."""
        for s in list(self.sessoes.values()):
            if not self._permitido(s.tipo):
                self._no_loop(s.encerrar, "O acesso de longe foi desligado no PC." if s.tipo == "p2p"
                              else "Agora este PC só aceita conexões pelo Tailscale.")

    def novo_convite(self) -> tuple:
        token = secrets.token_urlsafe(16)
        with self.lock:
            self.convite = (token, time.monotonic() + 600)
        return token, 600

    # --- conexões
    def _permitido(self, tipo: str) -> bool:
        if tipo in ("loopback", "tailscale"):
            return True
        if tipo == "p2p":  # de longe, pela ponte WebRTC: só com o ponto de encontro configurado
            return bool(self.cfg().get("encontro"))
        return tipo == "local" and not self.cfg().get("so_tailscale")

    def _avisar_uma_vez(self, ip: str, texto: str) -> None:
        agora = time.monotonic()
        if agora - self._avisados.get(ip, -999) > 60:
            self._avisados[ip] = agora
            comum.log(texto)

    async def _responder(self, writer, codigo: int, corpo: bytes, tipo: str, extra: dict | None = None,
                         so_cabecalho: bool = False) -> None:
        cab = {"Content-Type": tipo, "Content-Length": str(len(corpo)), "Connection": "close",
               "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY",
               "Referrer-Policy": "no-referrer", "Content-Security-Policy": "frame-ancestors 'none'"}
        cab.update(extra or {})
        linhas = [f"HTTP/1.1 {codigo} {TEXTO_HTTP.get(codigo, 'OK')}"] + [f"{k}: {v}" for k, v in cab.items()]
        try:
            writer.write(("\r\n".join(linhas) + "\r\n\r\n").encode("latin-1") + (b"" if so_cabecalho else corpo))
            await writer.drain()
        except (ConnectionError, OSError):
            pass
        finally:
            try:
                writer.close()
            except Exception:
                pass

    async def _conexao(self, reader, writer) -> None:
        try:
            writer.get_extra_info("socket").setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except (OSError, AttributeError):
            pass
        peer = writer.get_extra_info("peername") or ("?",)
        ip = str(peer[0])
        try:
            cab = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 15)
            linhas = cab.decode("latin-1").split("\r\n")
            metodo, alvo, _ = linhas[0].split(" ", 2)
        except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, asyncio.TimeoutError,
                ConnectionError, OSError, ValueError):
            writer.close()
            return
        headers = {}
        for linha in linhas[1:]:
            if ":" in linha:
                k, v = linha.split(":", 1)
                headers[k.strip().lower()] = v.strip()
        tipo = comum.tipo_de_ip(ip)
        if not self._permitido(tipo):
            self._avisar_uma_vez(ip, f"recusado: {ip} ({'internet' if tipo == 'externo' else 'rede de casa'}, "
                                     f"{'só Tailscale está ligado' if tipo == 'local' else 'fora do Tailscale'})")
            corpo = ("<!doctype html><meta charset=utf-8><title>Ponte Remota</title>"
                     "<p style='font:16px system-ui;padding:24px'>Este PC não aceita conexões deste endereço. "
                     "Use o Tailscale (veja no PC: Ponte Remota → Detalhes).</p>").encode()
            return await self._responder(writer, 403, corpo, "text/html; charset=utf-8")
        caminho, _, consulta = alvo.partition("?")
        if caminho == "/ws-ponte" and headers.get("upgrade", "").lower() == "websocket":
            # a ponte WebRTC deste PC: só do próprio PC e com o token que o app deu a ela
            q = dict(urllib.parse.parse_qsl(consulta))
            if tipo != "loopback" or not self.token_ponte or not hmac.compare_digest(
                    q.get("t", "").encode(), self.token_ponte.encode()) or not q.get("v"):
                return await self._responder(writer, 403, b"", "text/plain")
            ip_longe = (q.get("ip") or "de longe")[:60]
            return await self._websocket(reader, writer, headers, ip_longe, "p2p", vinculo=q["v"].encode(),
                                         checar_origem=False)
        if caminho == "/ws" and headers.get("upgrade", "").lower() == "websocket":
            return await self._websocket(reader, writer, headers, ip, tipo)
        if metodo not in ("GET", "HEAD"):
            return await self._responder(writer, 405, b"", "text/plain")
        if caminho == "/manifest.webmanifest":
            corpo = json.dumps({"name": f"Estenda · {self.nome_pc}", "short_name": self.nome_pc,
                                "start_url": "/", "display": "fullscreen", "background_color": "#1b1f24",
                                "theme_color": "#1b1f24",
                                "icons": [{"src": "/icone-192.png", "sizes": "192x192", "type": "image/png"},
                                          {"src": "/icone-512.png", "sizes": "512x512", "type": "image/png"}]},
                               ensure_ascii=False).encode()
            return await self._responder(writer, 200, corpo, "application/manifest+json",
                                         so_cabecalho=metodo == "HEAD")
        if caminho == "/estenda.apk":
            try:
                corpo = await asyncio.get_running_loop().run_in_executor(None, self.apk.read_bytes) if self.apk else None
            except OSError:
                corpo = None
            if corpo is None:
                return await self._responder(writer, 404, "O app ainda não foi gerado no PC.".encode(), "text/plain; charset=utf-8")
            comum.log(f"{ip} baixou o app do tablet")
            return await self._responder(writer, 200, corpo, "application/vnd.android.package-archive",
                                         {"Content-Disposition": 'attachment; filename="Estenda.apk"'},
                                         so_cabecalho=metodo == "HEAD")
        if caminho in ARQUIVOS:
            nome, tipo_arq = ARQUIVOS[caminho]
            try:
                corpo = (self.pasta / nome).read_bytes()
            except OSError:
                return await self._responder(writer, 404, b"", "text/plain")
            extra = {"Cache-Control": "max-age=86400"} if caminho.startswith("/fontes/") else None
            return await self._responder(writer, 200, corpo, tipo_arq, extra, so_cabecalho=metodo == "HEAD")
        return await self._responder(writer, 404, b"", "text/plain")

    async def _websocket(self, reader, writer, headers: dict, ip: str, tipo: str, vinculo: bytes = b"",
                         checar_origem: bool = True) -> None:
        chave = headers.get("sec-websocket-key", "")
        origem = headers.get("origin")
        if checar_origem and origem and origem.split("://", 1)[-1].rstrip("/") != headers.get("host", ""):
            self._avisar_uma_vez(ip, f"recusado: conexão de outra página ({origem})")
            return await self._responder(writer, 403, b"", "text/plain")
        if not chave or headers.get("sec-websocket-version") != "13":
            return await self._responder(writer, 400, b"", "text/plain")
        aceite = _b64(hashlib.sha1((chave + GUID_WS).encode()).digest())
        writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                      f"Sec-WebSocket-Accept: {aceite}\r\n\r\n").encode())
        try:
            writer.transport.set_write_buffer_limits(high=256 * 1024)
            await writer.drain()
        except (ConnectionError, OSError, AttributeError):
            return
        ws = WebSocket(reader, writer)
        try:
            await self._sessao(ws, ip, tipo, vinculo)
        except Exception as e:  # um erro numa sessão não derruba o servidor
            comum.log(f"erro na sessão de {ip}: {type(e).__name__}: {e}")
        finally:
            await ws.fechar()

    def _bloqueio(self, ip: str) -> int:
        n, ate = self.falhas.get(ip, (0, 0.0))
        return max(0, int(ate - time.monotonic()))

    def _falhou(self, ip: str) -> None:
        n, _ = self.falhas.get(ip, (0, 0.0))
        n += 1
        ate = time.monotonic() + min(3600, 30 * 2 ** (n - 5)) if n >= 5 else 0.0
        self.falhas[ip] = (n, ate)
        comum.log(f"senha errada vinda de {ip} ({n}ª)" + (f"; bloqueado por {int(ate - time.monotonic())} s"
                                                          if ate else ""))

    def _autenticar(self, msg: dict, nonce: bytes):
        """(ok, id do aparelho ou None, aparelho novo ou None).

        De longe, "nonce" já vem somado ao vínculo do canal (as impressões digitais DTLS dos dois lados):
        se alguém no meio (até o ponto de encontro) trocasse o canal, a assinatura do tablet não bateria."""
        modo = msg.get("modo")
        try:
            mac = bytes.fromhex(str(msg.get("mac", "")))
        except ValueError:
            return False, None, None
        nome = str(msg.get("nome") or "Aparelho").strip()[:60]
        if modo == "senha":
            chave = comum.normalizar_senha(self.senha())
            if not chave or not hmac.compare_digest(_assinatura(chave, nonce), mac):
                return False, None, None
            if msg.get("lembrar"):
                ap = self.aparelhos.novo(nome)
                return True, ap["id"], ap
            return True, None, None
        if modo == "aparelho":
            ap = self.aparelhos.achar(str(msg.get("id", "")))
            if not ap or not hmac.compare_digest(_assinatura(ap["token"], nonce), mac):
                return False, None, None
            self.aparelhos.visto(ap["id"])
            return True, ap["id"], None
        if modo == "convite":
            with self.lock:
                conv = self.convite
                ok = bool(conv and time.monotonic() < conv[1]
                          and hmac.compare_digest(_assinatura(conv[0], nonce), mac))
                if ok:
                    self.convite = None  # vale uma vez só
            if not ok:
                return False, None, None
            ap = self.aparelhos.novo(nome)
            return True, ap["id"], ap
        return False, None, None

    async def _sessao(self, ws: WebSocket, ip: str, tipo: str, vinculo: bytes = b"") -> None:
        nonce = secrets.token_bytes(16)
        await ws.enviar_json({"t": "ola", "pc": self.nome_pc, "nonce": _b64(nonce), "v": comum.PROTOCOLO})
        try:
            msg = await asyncio.wait_for(ws.receber_json(), TEMPO_LOGIN)
        except asyncio.TimeoutError:
            return
        if not msg or msg.get("t") != "auth":
            return
        espera = self._bloqueio(ip)
        if espera:
            await ws.enviar_json({"t": "negado", "motivo": "bloqueado", "espera": espera})
            return
        ok, aparelho, novo = self._autenticar(msg, nonce + vinculo)
        if not ok:
            self._falhou(ip)
            espera = self._bloqueio(ip)
            await ws.enviar_json({"t": "negado", "motivo": "bloqueado" if espera else msg.get("modo", "senha"),
                                  "espera": espera})
            return
        self.falhas.pop(ip, None)
        sessao = Sessao(self, ws, ip, tipo, str(msg.get("nome") or "Aparelho")[:60], aparelho)
        self.sessoes[sessao.id] = sessao
        via = {"tailscale": "Tailscale", "local": "rede de casa", "loopback": "este PC",
               "p2p": "de longe, direto"}.get(tipo, tipo)
        comum.log(f"{sessao.nome} conectou ({ip}, {via})")
        try:
            await sessao.rodar({"id": novo["id"], "token": novo["token"]} if novo else None)
        finally:
            self.sessoes.pop(sessao.id, None)
            comum.log(f"{sessao.nome} desconectou")
            if self.ao_fim_sessao:
                try:
                    self.ao_fim_sessao(time.time() - sessao.desde)
                except Exception:
                    pass

    # --- energia
    def _avisar_todos(self, obj) -> None:
        for s in list(self.sessoes.values()):
            asyncio.ensure_future(s.enviar(obj))

    def pedir_energia(self, acao: str) -> None:
        if acao == "cancelar":
            return self._cancelar_energia(avisar=True)
        if acao in ("bloquear", "suspender"):
            self._avisar_todos({"t": "energia", "acao": acao, "em": 0})
            self.loop.call_later(0.8, controle.energia, acao)
            comum.log(f"pedido do tablet: {acao}")
            return
        if acao not in ("desligar", "reiniciar"):
            return
        self._cancelar_energia(avisar=False)
        handle = self.loop.call_later(CONTAGEM_ENERGIA, self._executar_energia, acao)
        self.energia = (acao, time.time() + CONTAGEM_ENERGIA, handle)
        self._avisar_todos({"t": "energia", "acao": acao, "em": CONTAGEM_ENERGIA})
        comum.log(f"pedido do tablet: {acao} em {CONTAGEM_ENERGIA} s")

    def _executar_energia(self, acao: str) -> None:
        self.energia = None
        comum.log(f"{acao} agora")
        controle.energia(acao)

    def _cancelar_energia(self, avisar: bool) -> None:
        if self.energia:
            self.energia[2].cancel()
            comum.log(f"{self.energia[0]} cancelado")
            self.energia = None
            if avisar:
                self._avisar_todos({"t": "energia", "acao": None})

    def cancelar_energia_painel(self) -> None:
        self._no_loop(self._cancelar_energia, True)


# ---------------------------------------------------------------- uma sessão (um tablet)

class Sessao:
    def __init__(self, srv: ServidorRemoto, ws: WebSocket, ip: str, tipo: str, nome: str, aparelho):
        self.srv, self.ws, self.ip, self.tipo, self.nome, self.aparelho = srv, ws, ip, tipo, nome, aparelho
        self.id = secrets.token_hex(4)
        self.desde = time.time()
        self.preset = "equilibrada"
        self.fps = 30
        self.mons = controle.monitores()
        self.monitor = 0
        self.q = tela.PRESETS[self.preset]["q"]
        self.cod = tela.Codificador()
        self.exec = ThreadPoolExecutor(1, thread_name_prefix="captura")
        self.em_transito = {}
        self.prox_id = 1
        self.ack = asyncio.Event()
        self.acordar = asyncio.Event()
        self.forcar = True
        self.pausado = False
        self.fim = False
        self.ultimo_input = time.monotonic()
        self.atraso = None
        self._ajuste = 0.0
        self.rtt = None
        self.teclas = set()
        self.botoes = set()
        self.aviso = None
        self._janela_stats = [time.monotonic(), 0, 0]  # início, bytes, quadros
        self.stats = {"fps": 0, "kbps": 0}
        self.tam_quadro = (0, 0)

    def resumo(self) -> dict:
        return {"id": self.id, "nome": self.nome, "ip": self.ip, "tipo": self.tipo, "desde": self.desde,
                "fps": self.stats["fps"], "kbps": self.stats["kbps"],
                "ms": round(self.rtt) if self.rtt is not None else None, "qualidade": self.preset,
                "monitor": self.monitor + 1, "aparelho": self.aparelho}

    async def enviar(self, obj) -> None:
        try:
            await self.ws.enviar_json(obj)
        except (ConnectionError, OSError):
            self.fim = True

    async def encerrar(self, motivo: str) -> None:
        if self.fim:
            return
        self.fim = True
        try:
            await asyncio.wait_for(self.ws.enviar_json({"t": "tchau", "motivo": motivo}), 2)
        except Exception:
            pass
        await self.ws.fechar()

    def _mon(self) -> dict:
        if self.monitor >= len(self.mons):
            self.monitor = 0
        return self.mons[self.monitor]

    async def rodar(self, aparelho_novo) -> None:
        await self.enviar({"t": "bem_vindo", "pc": self.srv.nome_pc, "sessao": self.id,
                           "monitores": controle.nomes_monitores(self.mons), "monitor": self.monitor,
                           "energia": bool(self.srv.cfg().get("permitir_energia", True)),
                           "aparelho": aparelho_novo, "via": self.tipo})
        if self.srv.energia:
            acao, prazo, _ = self.srv.energia
            await self.enviar({"t": "energia", "acao": acao, "em": max(0, round(prazo - time.time()))})
        tarefas = [asyncio.ensure_future(f()) for f in (self._receber, self._transmitir, self._cursor)]
        try:
            await asyncio.wait(tarefas, return_when=asyncio.FIRST_COMPLETED)
        finally:
            self.fim = True
            for t in tarefas:
                t.cancel()
            await asyncio.gather(*tarefas, return_exceptions=True)
            self._soltar_tudo()
            self.exec.shutdown(wait=False)

    def _soltar_tudo(self) -> None:
        """Se a conexão cai com Ctrl ou um botão apertado, solta, para nada ficar preso no PC."""
        for vk in list(self.teclas):
            try:
                controle.tecla(vk, False)
            except Exception:
                pass
        for b in list(self.botoes):
            try:
                controle.botao(b, False)
            except Exception:
                pass
        self.teclas.clear()
        self.botoes.clear()

    # --- imagem
    def _capturar(self, mon: dict, forcar: bool, preset: str, q: int):
        img = self.srv.captura.capturar(mon)
        if forcar:
            self.cod.reiniciar()
        return self.cod.codificar(img, preset, q)

    async def _esperar(self, segundos: float) -> None:
        if segundos <= 0:
            return
        try:
            await asyncio.wait_for(self.acordar.wait(), segundos)
        except asyncio.TimeoutError:
            pass
        self.acordar.clear()

    async def _mandar_quadro(self, res, flags_extra: int = 0) -> None:
        completo, w, h, pedacos = res
        ident = self.prox_id
        self.prox_id = (self.prox_id + 1) & 0xFFFFFFFF or 1
        dados = tela.montar_quadro(ident, (1 if completo else 0) | flags_extra, w, h, pedacos)
        self.em_transito[ident] = (time.monotonic(), len(dados))
        self.tam_quadro = (w, h)
        await self.ws.enviar(dados)
        self._janela_stats[1] += len(dados)

    async def _transmitir(self) -> None:
        loop = asyncio.get_running_loop()
        parou_em = time.monotonic()
        refinado = True
        while not self.fim:
            if self.pausado:
                await self._esperar(0.5)
                continue
            while len(self.em_transito) >= MAX_EM_TRANSITO and not self.fim:
                self.ack.clear()
                try:
                    await asyncio.wait_for(self.ack.wait(), 3)
                except asyncio.TimeoutError:
                    agora = time.monotonic()
                    for k in [k for k, (t, _) in self.em_transito.items() if agora - t > 8]:
                        del self.em_transito[k]  # o tablet sumiu sem avisar: não trava para sempre
            if self.fim:
                break
            inicio = time.monotonic()
            forcar, self.forcar = self.forcar, False
            try:
                res = await loop.run_in_executor(self.exec, self._capturar, self._mon(), forcar,
                                                 self.preset, self.q)
                if self.aviso:
                    self.aviso = None
                    await self.enviar({"t": "aviso", "tipo": None})
            except tela.ErroCaptura as e:
                if self.aviso != e.motivo:
                    self.aviso = e.motivo
                    await self.enviar({"t": "aviso", "tipo": e.motivo})
                self.forcar = True
                await self._esperar(1.0)
                continue
            agora = time.monotonic()
            if res:
                await self._mandar_quadro(res)
                parou_em, refinado = agora, False
            elif not refinado and agora - parou_em > 0.3:
                rebaixe = max(0, tela.PRESETS[self.preset]["q"] - self.q)
                res = await loop.run_in_executor(self.exec, self.cod.refinar, self.preset, rebaixe)
                refinado = True
                if res:
                    await self._mandar_quadro(res, 2)
            ativo = agora - self.ultimo_input < 3 or agora - parou_em < 3
            intervalo = 1 / self.fps if ativo else 1 / 6  # parado: olha a tela 6x por segundo
            await self._esperar(inicio + intervalo - time.monotonic())

    def _ack(self, ident) -> None:
        info = self.em_transito.pop(ident, None)
        self.ack.set()
        if not info:
            return
        agora = time.monotonic()
        atraso = agora - info[0]
        self.atraso = atraso if self.atraso is None else self.atraso * 0.8 + atraso * 0.2
        self._janela_stats[2] += 1
        ini, nbytes, nq = self._janela_stats
        if agora - ini >= 1:
            self.stats = {"fps": round(nq / (agora - ini)), "kbps": round(nbytes / 1024 / (agora - ini))}
            self._janela_stats = [agora, 0, 0]
        if agora - self._ajuste > 0.5:  # qualidade automática: rede lenta, imagem mais leve
            self._ajuste = agora
            base = tela.PRESETS[self.preset]["q"]
            if self.atraso > 0.35 and self.q > 30:
                self.q = max(30, self.q - 6)
            elif self.atraso < 0.15 and self.q < base:
                self.q = min(base, self.q + 3)

    # --- cursor
    async def _cursor(self) -> None:
        ultimo, conferir_mons, mexeu = None, time.monotonic(), 0.0
        while not self.fim:
            agora = time.monotonic()
            if agora - conferir_mons > 5:  # monitor ligado/desligado
                conferir_mons = agora
                novos = controle.monitores()
                if novos != self.mons:
                    self.mons = novos
                    self.forcar = True
                    self.srv.captura.renovar()
                    comum.log("as telas do PC mudaram: captura renovada")
                    await self.enviar({"t": "monitores", "monitores": controle.nomes_monitores(novos),
                                       "monitor": min(self.monitor, len(novos) - 1)})
            try:
                x, y, forma, visivel = controle.cursor()
            except Exception:
                x, y, forma, visivel = 0, 0, "seta", False
            mon = self._mon()
            rx, ry = x - mon["x"], y - mon["y"]
            dentro = 0 <= rx < mon["w"] and 0 <= ry < mon["h"]
            estado = (rx, ry, forma, visivel and dentro)
            if estado != ultimo:
                ultimo, mexeu = estado, agora
                await self.enviar({"t": "c", "x": rx, "y": ry, "f": forma, "v": estado[3]})
            rapido = agora - self.ultimo_input < 2 or agora - mexeu < 1
            await asyncio.sleep(0.025 if rapido else 0.1)

    # --- comandos do tablet
    def _xy(self, msg) -> tuple:
        mon = self._mon()
        x = min(max(int(msg.get("x", 0)), 0), mon["w"] - 1)
        y = min(max(int(msg.get("y", 0)), 0), mon["h"] - 1)
        return mon["x"] + x, mon["y"] + y

    async def _receber(self) -> None:
        while not self.fim:
            msg = await self.ws.receber_json()
            if msg is None:
                return
            try:
                await self._tratar(msg)
            except (ValueError, TypeError, KeyError) as e:
                comum.log(f"mensagem inválida de {self.nome}: {type(e).__name__}")

    def _mexeu(self) -> None:
        self.ultimo_input = time.monotonic()
        self.acordar.set()

    async def _tratar(self, msg: dict) -> None:
        t = msg.get("t")
        if t == "a":
            self._ack(int(msg.get("id", 0)))
        elif t == "m":
            controle.mover(*self._xy(msg))
            self._mexeu()
        elif t == "b":
            b, desce = int(msg.get("b", 0)), bool(msg.get("d"))
            xy = self._xy(msg) if "x" in msg else (None, None)
            controle.botao(b, desce, *xy)
            (self.botoes.add if desce else self.botoes.discard)(b)
            self._mexeu()
        elif t == "w":
            controle.roda(int(max(-12000, min(12000, msg.get("dy", 0)))),
                          int(max(-12000, min(12000, msg.get("dx", 0)))))
            self._mexeu()
        elif t == "k":
            vk, desce = int(msg.get("vk", 0)), bool(msg.get("d"))
            controle.tecla(vk, desce, bool(msg.get("e")))
            (self.teclas.add if desce else self.teclas.discard)(vk)
            self._mexeu()
        elif t == "atalho":
            controle.atalho([int(v) for v in (msg.get("vks") or [])][:6])
            self._mexeu()
        elif t == "txt":
            controle.texto(str(msg.get("s", ""))[:4000])
            self._mexeu()
        elif t == "ping":
            if msg.get("rtt") is not None:
                self.rtt = float(msg["rtt"])
            await self.enviar({"t": "pong", "ts": msg.get("ts")})
        elif t == "cfg":
            if msg.get("qualidade") in tela.PRESETS and msg["qualidade"] != self.preset:
                self.preset = msg["qualidade"]
                self.q = tela.PRESETS[self.preset]["q"]
                self.forcar = True
            if msg.get("fps") in (15, 30, 60):
                self.fps = int(msg["fps"])
            self._mexeu()
        elif t == "mon":
            i = int(msg.get("i", 0))
            if 0 <= i < len(self.mons) and i != self.monitor:
                self.monitor = i
                self.forcar = True
                self._mexeu()
        elif t == "completo":
            self.forcar = True
            self._mexeu()
        elif t == "pausa":
            self.pausado = bool(msg.get("v"))
            if not self.pausado:
                self._mexeu()
        elif t == "clip_get":
            texto = await asyncio.get_running_loop().run_in_executor(None, controle.area_ler)
            await self.enviar({"t": "clip", "s": texto[:500000]})
        elif t == "clip_set":
            s = str(msg.get("s", ""))[:500000]
            ok = await asyncio.get_running_loop().run_in_executor(None, controle.area_escrever, s)
            if ok and msg.get("colar"):
                controle.atalho([0x11, 0x56])  # Ctrl+V
            await self.enviar({"t": "clip_ok", "ok": bool(ok), "colou": bool(ok and msg.get("colar"))})
            self._mexeu()
        elif t == "energia":
            if not self.srv.cfg().get("permitir_energia", True):
                await self.enviar({"t": "energia_negada"})
            else:
                self.srv.pedir_energia(str(msg.get("acao")))
