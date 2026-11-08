#!/usr/bin/env python3
"""Ponte Remota — o aplicativo do PC.

O painel (interface/painel.html) abre numa janela do Edge/Chrome em modo aplicativo e
conversa com este processo por HTTP local (127.0.0.1, porta aleatória, protegido por código).
O acesso remoto (remoto.py) é outra porta, a que o tablet abre.

Fechar a janela encerra o app e desliga o acesso. A exceção é quando ele inicia com o
Windows (--segundo-plano): aí roda sem janela; abrir o atalho mostra o painel e, ao fechar
o painel, o app também encerra.

    python app.py                 # abre o painel e libera o terminal
    python app.py --segundo-plano # sem janela, já com o acesso ligado (ao iniciar com o Windows)
    python app.py --com-terminal  # mantém o terminal com o registro
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import webbrowser
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

import comum
import controle
import qr
import remoto

BASE = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))  # o PyInstaller extrai aqui
PASTA_INTERFACE = BASE / "interface"
PASTA_PROGRAMA = Path(sys.executable).resolve().parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parent


def achar_apk() -> Path | None:
    """O app Android gerado pelo app_tablet/gerar_apk.bat (ou posto ao lado do programa)."""
    for p in (PASTA_PROGRAMA / "dist" / "PonteRemota-tablet.apk", PASTA_PROGRAMA / "PonteRemota-tablet.apk",
              PASTA_PROGRAMA / "Estenda.apk", comum.PASTA / "Estenda.apk",
              PASTA_PROGRAMA / "app_tablet" / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"):
        if p.is_file() and p.stat().st_size > 0:
            return p
    return None
ARQUIVOS = {"/": ("painel.html", "text/html; charset=utf-8"),
            "/index.html": ("painel.html", "text/html; charset=utf-8"),
            "/icone.png": ("icone.png", "image/png"),
            "/ponte.html": ("ponte.html", "text/html; charset=utf-8"),
            "/fontes/SpaceGrotesk.ttf": ("fontes/SpaceGrotesk.ttf", "font/ttf"),
            "/fontes/JetBrainsMono.ttf": ("fontes/JetBrainsMono.ttf", "font/ttf")}
PADRAO = {"porta": comum.PORTA_PADRAO, "so_tailscale": False, "permitir_energia": True, "nao_dormir": True,
          "encontro": ""}  # endereço do ponto de encontro (Cloudflare Worker) para usar de longe


def _url_encontro(v) -> str:
    """https://algo.workers.dev (sem barra no fim). http só para testes no próprio PC."""
    v = str(v or "").strip().rstrip("/")
    if not v:
        return ""
    if "://" not in v:
        v = "https://" + v
    u = urlparse(v)
    local = u.hostname in ("127.0.0.1", "localhost")
    if u.scheme not in ("https", "http") or (u.scheme == "http" and not local) or not u.hostname \
            or u.path not in ("", "/") or u.query or u.fragment:
        raise ErroUsuario("Use o endereço que o publicar.bat mostrou, como https://estenda-encontro.SEU-NOME.workers.dev")
    return f"{u.scheme}://{u.netloc}"


# ---------------------------------------------------------------- terminal e registro

def _soltar_do_terminal() -> bool:
    """Aberto com `python app.py`, reabre sem terminal e devolve True para este processo sair."""
    if getattr(sys, "frozen", False) or os.environ.get("PONTE_REMOTA_SOLTO") or sys.platform != "win32":
        return False
    exe = Path(sys.executable)
    semterm = exe.with_name("pythonw.exe")
    if exe.name.lower() != "python.exe" or not semterm.is_file():
        return False
    try:
        subprocess.Popen([str(semterm), str(Path(__file__).resolve()), *sys.argv[1:]],
                         env=dict(os.environ, PONTE_REMOTA_SOLTO="1"), close_fds=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         creationflags=0x00000008 | 0x00000200)  # DETACHED_PROCESS | NEW_PROCESS_GROUP
    except OSError:
        return False
    return True


def _redirecionar_saidas() -> None:
    """Sem terminal, um print quebraria o app: tudo vai para ~/.ponte-remota/registro.txt."""
    if sys.stdout is not None and sys.stderr is not None and not os.environ.get("PONTE_REMOTA_SOLTO") \
            and not getattr(sys, "frozen", False):
        return
    try:
        comum.PASTA.mkdir(parents=True, exist_ok=True)
        arq = comum.PASTA / "registro.txt"
        if arq.exists() and arq.stat().st_size > 2_000_000:
            arq.replace(comum.PASTA / "registro-antigo.txt")
        saida = open(arq, "a", encoding="utf-8", buffering=1)
    except OSError:
        saida = open(os.devnull, "w")
    sys.stdout = sys.stderr = saida


class ErroUsuario(Exception):
    """Erro para mostrar no painel (extra vai junto no JSON, ex.: pode_fechar)."""

    def __init__(self, msg: str, **extra):
        super().__init__(msg)
        self.extra = extra


# conversas com 127.0.0.1 nunca passam por proxy (AdGuard, VPN etc. atrapalhavam)
_LOCAL = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def quem_usa_porta(porta: int) -> tuple:
    """(pid, nome do programa) de quem escuta na porta TCP, ou (None, None)."""
    if sys.platform != "win32":
        return None, None
    try:
        saida = subprocess.run(["netstat", "-ano", "-p", "TCP"], capture_output=True, text=True, timeout=5,
                               creationflags=comum.SEM_JANELA).stdout
        pid = next((int(l.split()[-1]) for l in saida.splitlines()
                    if len(l.split()) >= 5 and l.split()[1].endswith(f":{porta}") and l.split()[3] == "LISTENING"), None)
        if not pid:
            return None, None
        lista = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"], capture_output=True,
                               text=True, timeout=5, creationflags=comum.SEM_JANELA).stdout
        nome = lista.split(",")[0].strip().strip('"') if "," in lista else None
        return pid, nome
    except (OSError, ValueError, subprocess.SubprocessError):
        return None, None


def e_ponte_remota(porta: int) -> bool:
    """A porta está com um Ponte Remota (a página do tablet responde)?"""
    try:
        with _LOCAL.open(f"http://127.0.0.1:{porta}/", timeout=2) as r:
            return b"Ponte Remota" in r.read(4000)
    except (OSError, ValueError):
        return False


def _porta(v) -> int:
    if v in (None, ""):
        return comum.PORTA_PADRAO
    try:
        p = int(v)
    except (TypeError, ValueError):
        raise ErroUsuario("A porta precisa ser um número.") from None
    if not 1024 <= p <= 65535:
        raise ErroUsuario("Use uma porta entre 1024 e 65535.")
    return p


def comando_inicio() -> str:
    """O que o Windows roda ao entrar na conta: o app, sem janela, com o acesso ligado."""
    if getattr(sys, "frozen", False):
        return f'"{sys.executable}" --segundo-plano'
    exe = Path(sys.executable)
    semterm = exe.with_name("pythonw.exe")
    return f'"{semterm if semterm.is_file() else exe}" "{Path(__file__).resolve()}" --segundo-plano'


# ---------------------------------------------------------------- o app

class App:
    def __init__(self):
        self.lock = threading.RLock()
        self.registro: deque = deque(maxlen=200)
        comum.definir_log(self._log)
        self.cfg = {**PADRAO, **comum.ler_json("config.json", {})}
        self.senha = comum.ler_senha()
        self.token = secrets.token_urlsafe(24)
        self.ultimo_contato = time.monotonic()
        self.pedido_fechar = None
        self.pedido_janela = False
        self.pedido_sair = False
        self.enderecos = comum.Enderecos()
        self.convite = None  # (url, svg, expira em time.time, via)
        self.remoto = remoto.ServidorRemoto(PASTA_INTERFACE, lambda: self.cfg, lambda: self.senha,
                                            socket.gethostname())
        self.uso = comum.ler_json("uso.json", {})  # dia -> segundos com algum aparelho conectado
        self.remoto.ao_fim_sessao = self._somar_uso
        # de longe: a sala deste PC no ponto de encontro (o id vai no QR; a chave fica só aqui)
        self.sala = comum.ler_json("longe.json", {})
        if not (self.sala.get("sala") and self.sala.get("chave")):
            self.sala = {"sala": secrets.token_urlsafe(18), "chave": secrets.token_urlsafe(32)}
            comum.salvar_json("longe.json", self.sala, secreto=True)
        self.remoto.token_ponte = secrets.token_urlsafe(24)
        self.monitor_inst = None     # instalação do monitor virtual: {"estado", "msg"}
        self.ponte_estado = {}       # o que a ponte WebRTC contou da última vez
        self.ponte_visto = 0.0

    def _somar_uso(self, segundos: float) -> None:
        with self.lock:
            hoje = time.strftime("%Y-%m-%d")
            self.uso[hoje] = int(self.uso.get(hoje, 0) + segundos)
            limite = time.strftime("%Y-%m-%d", time.localtime(time.time() - 14 * 86400))
            self.uso = {d: v for d, v in self.uso.items() if d >= limite}
            comum.salvar_json("uso.json", self.uso)

    def uso_semana(self) -> int:
        dias = {time.strftime("%Y-%m-%d", time.localtime(time.time() - i * 86400)) for i in range(7)}
        total = sum(v for d, v in self.uso.items() if d in dias)
        return int(total + sum(time.time() - s.desde for s in list(self.remoto.sessoes.values())))

    def _log(self, linha: str) -> None:
        self.registro.append(linha)
        try:
            print(linha, flush=True)
        except Exception:
            pass

    def _guardar(self, **campos) -> None:
        self.cfg.update(campos)
        comum.salvar_json("config.json", {k: self.cfg[k] for k in PADRAO})

    def avisos(self) -> list:
        lista = []
        if controle.SIMULADO:
            lista.append("Modo de teste: a tela e o controle são simulados (o Windows de verdade não é usado).")
        if sys.platform == "win32" and not controle.SIMULADO:
            try:
                import mss  # noqa: F401
            except ImportError:
                lista.append("Falta a biblioteca mss (rode o instalar.bat). Sem ela a imagem fica mais lenta.")
        return lista

    # --- leitura
    def estado(self) -> dict:
        with self.lock:
            ligado = self.remoto.ligado
            end = self.enderecos.obter()
            convite = None
            if self.convite and ligado:
                url, svg, expira, via = self.convite
                convite = {"url": url, "svg": svg, "expira": expira, "via": via,
                           "vencido": time.time() >= expira,
                           "usado": self.remoto.convite is None and time.time() < expira}  # o servidor apaga ao usar
            return {
                "versao": comum.VERSAO, "simulado": controle.SIMULADO, "pc": socket.gethostname(),
                "ligado": ligado, "porta": self.remoto.porta or self.cfg["porta"], "senha": self.senha,
                "enderecos": end, "sessoes": self.remoto.lista_sessoes() if ligado else [],
                "aparelhos": self.remoto.aparelhos.publico(),
                "config": {k: self.cfg[k] for k in PADRAO},
                "iniciar_windows": bool(controle.inicia_com_windows()),
                "convite": convite,
                "energia": None if not self.remoto.energia else {"acao": self.remoto.energia[0],
                                                                 "prazo": self.remoto.energia[1]},
                "avisos": self.avisos(),
                "monitores": controle.nomes_monitores(controle.monitores()),
                "uso_semana": self.uso_semana(),
                "apk": self._qr_apk(ligado, end),
                "longe": self._estado_longe(ligado),
                "monitor_inst": self.monitor_inst,
                "registro": list(self.registro)[-80:],
            }

    def longe_ativo(self) -> bool:
        return bool(self.remoto.ligado and self.cfg.get("encontro"))

    def _estado_longe(self, ligado: bool) -> dict:
        p = self.ponte_estado if time.monotonic() - self.ponte_visto < 12 else {}
        return {"encontro": self.cfg.get("encontro", ""), "ativo": bool(ligado and self.cfg.get("encontro")),
                "sinal": p.get("sinal") or ("iniciando" if ligado and self.cfg.get("encontro") else "desligado"),
                "erro": p.get("erro") or "", "conexoes": p.get("pares", 0)}

    def instalar_monitor(self, d=None) -> None:
        """Instala o driver de monitor virtual (Virtual Display Driver, código aberto) pelo winget.
        O Windows pede permissão de administrador uma vez; depois aparece uma tela nova."""
        if sys.platform != "win32" and not controle.SIMULADO:
            raise ErroUsuario("Isso só funciona no Windows.")
        if self.monitor_inst and self.monitor_inst["estado"] == "instalando":
            return
        antes = len(controle.monitores())
        self.monitor_inst = {"estado": "instalando", "msg": "Instalando… aceite o pedido de permissão do Windows."}
        comum.log("instalando o monitor virtual (Virtual Display Driver)")

        def rodar():
            try:
                if controle.SIMULADO:
                    time.sleep(1.5)
                    ok = True
                else:
                    log = comum.PASTA / "instalar_monitor.log"
                    ps1 = comum.PASTA / "instalar_monitor.ps1"
                    ps1.write_text(
                        f'Start-Transcript -Path "{log}" -Force\n'
                        "$a = '--accept-source-agreements','--accept-package-agreements','--silent','-e'\n"
                        "winget install --id Microsoft.VCRedist.2015+.x64 @a\n"
                        "winget install --id VirtualDrivers.Virtual-Display-Driver @a\n"
                        "Stop-Transcript\n", encoding="utf-8")
                    cmd = ("try { Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList "
                           f"'-NoProfile -ExecutionPolicy Bypass -File \"{ps1}\"' -ErrorAction Stop; exit 0 }} "
                           "catch { exit 5 }")
                    r = subprocess.run(["powershell", "-NoProfile", "-Command", cmd], capture_output=True,
                                       creationflags=comum.SEM_JANELA, timeout=900)
                    if r.returncode == 5:
                        self.monitor_inst = {"estado": "recusado",
                                             "msg": "O Windows não recebeu a permissão. Tente de novo e clique em Sim."}
                        return
                    ok = False
                    for _ in range(20):  # o Windows leva uns segundos para ligar a tela nova
                        if len(controle.monitores()) > antes:
                            ok = True
                            break
                        time.sleep(1.5)
                if ok:
                    self.monitor_inst = {"estado": "pronto", "msg": "Pronto! O Windows ganhou uma tela nova para o tablet."}
                    comum.log("monitor virtual instalado")
                else:
                    self.monitor_inst = {"estado": "sem_monitor",
                                         "msg": "O instalador terminou, mas a tela nova não apareceu. Reinicie o PC; "
                                                "se ainda não aparecer, veja abaixo como instalar à mão."}
                    comum.log("monitor virtual: instalador terminou sem tela nova (veja instalar_monitor.log)")
            except Exception as e:
                self.monitor_inst = {"estado": "erro", "msg": f"Não deu certo: {e}"}
                comum.log(f"monitor virtual: erro {e}")

        threading.Thread(target=rodar, daemon=True).start()

    def dados_ponte(self) -> dict:
        """Para a ponte WebRTC (ponte.html): onde se encontrar e como entrar no servidor local."""
        return {"ativo": self.longe_ativo(), "encontro": self.cfg.get("encontro", ""),
                "sala": self.sala["sala"], "chave": self.sala["chave"], "porta": self.remoto.porta,
                "token": self.remoto.token_ponte}

    def estado_ponte(self, d: dict) -> None:
        self.ponte_estado = {"sinal": str(d.get("sinal", ""))[:20], "erro": str(d.get("erro", ""))[:200],
                             "pares": int(d.get("pares") or 0)}
        self.ponte_visto = time.monotonic()

    def _qr_apk(self, ligado: bool, end: dict) -> dict | None:
        """Link + QR para o tablet baixar o app direto do PC (só na rede de casa)."""
        self.remoto.apk = achar_apk()
        if not (ligado and self.remoto.apk and end.get("local") and not self.cfg["so_tailscale"]):
            return None
        url = f"http://{end['local'][0]}:{self.remoto.porta}/estenda.apk"
        if getattr(self, "_apk_cache", (None,))[0] != url:
            self._apk_cache = (url, qr.svg(url))
        return {"url": url, "svg": self._apk_cache[1], "mb": round(self.remoto.apk.stat().st_size / 1048576, 1)}

    # --- ações
    def ligar(self, d: dict) -> None:
        with self.lock:
            if self.remoto.ligado:
                return
            porta = _porta(d.get("porta") or self.cfg["porta"])
            pid, nome = quem_usa_porta(porta)
            if d.get("fechar_antigo") and pid and pid != os.getpid() and e_ponte_remota(porta):
                comum.log(f"fechando o Ponte Remota antigo ({nome}, PID {pid}) que ocupava a porta {porta}")
                subprocess.run(["taskkill", "/PID", str(pid), "/F"], capture_output=True, creationflags=comum.SEM_JANELA)
                time.sleep(1.0)
            try:
                self.remoto.iniciar(porta)
            except OSError as e:
                pid, nome = quem_usa_porta(porta)
                if e_ponte_remota(porta):
                    raise ErroUsuario(
                        f"Já tem outro Ponte Remota ligado nesta porta, rodando em segundo plano"
                        f"{f' ({nome}, PID {pid})' if pid else ''}. Feche o antigo para ligar aqui.",
                        pode_fechar=True) from None
                quem = f"o programa {nome} (PID {pid})" if nome else "outro programa"
                raise ErroUsuario(f"A porta {porta} está ocupada por {quem}. Troque a porta em Opções → Senha e porta, "
                                  f"ou feche esse programa. ({e})") from None
            self._guardar(porta=porta)
            self.enderecos.obter(forcar=True)

    def desligar(self, d=None) -> None:
        with self.lock:
            self.convite = None
        self.remoto.parar()

    def nova_senha(self, d: dict) -> None:
        senha = str(d.get("senha") or "").strip()
        if senha and len(comum.normalizar_senha(senha)) < 8:
            raise ErroUsuario("A senha precisa ter pelo menos 8 letras ou números.")
        self.senha = senha or comum.gerar_senha()
        comum.salvar_senha(self.senha)
        comum.log("senha trocada (aparelhos lembrados continuam entrando)")

    def config(self, d: dict) -> None:
        novos = {k: bool(d[k]) for k in ("so_tailscale", "permitir_energia", "nao_dormir") if k in d}
        if "encontro" in d:
            novos["encontro"] = _url_encontro(d["encontro"])
            comum.log("acesso de longe: " + (f"ponto de encontro {novos['encontro']}" if novos["encontro"]
                                              else "desligado"))
        if "porta" in d:
            if self.remoto.ligado:
                raise ErroUsuario("Desligue o acesso para trocar a porta.")
            novos["porta"] = _porta(d["porta"])
        self._guardar(**novos)
        if novos.get("so_tailscale") or novos.get("encontro") == "":
            self.remoto.aplicar_filtro()
        if "iniciar_windows" in d:
            try:
                controle.iniciar_com_windows(comando_inicio() if d["iniciar_windows"] else None)
            except OSError as e:
                raise ErroUsuario(f"O Windows não deixou mudar a inicialização: {e}") from None
            comum.log("vai iniciar com o Windows" if d["iniciar_windows"] else "não inicia mais com o Windows")

    def gerar_convite(self, d: dict) -> None:
        with self.lock:
            if not self.remoto.ligado:
                raise ErroUsuario("Ligue o acesso primeiro.")
            end = self.enderecos.obter()
            via = d.get("via") if d.get("via") in ("tailscale", "local", "longe") else None
            if via is None:
                via = "tailscale" if end["tailscale"] else "local"
            if via == "longe":
                if not self.cfg.get("encontro"):
                    raise ErroUsuario("Configure o ponto de encontro primeiro (Configurações → De longe).")
                token, validade = self.remoto.novo_convite()
                url = f"{self.cfg['encontro']}/#s={self.sala['sala']}&c={token}"
                self.convite = (url, qr.svg(url), time.time() + validade, via)
                return
            ips = end["tailscale"] if via == "tailscale" else end["local"]
            if not ips:
                raise ErroUsuario("O Tailscale não está ligado neste PC." if via == "tailscale"
                                  else "Não achei o endereço deste PC na rede de casa.")
            token, validade = self.remoto.novo_convite()
            url = f"http://{ips[0]}:{self.remoto.porta}/#c={token}"
            self.convite = (url, qr.svg(url), time.time() + validade, via)

    def derrubar(self, d: dict) -> None:
        self.remoto.derrubar(str(d.get("id", "")))

    def esquecer(self, d: dict) -> None:
        ident = d.get("id")
        self.remoto.esquecer_aparelho(None if ident is None else str(ident))
        comum.log("todos os aparelhos foram esquecidos" if ident is None else "aparelho esquecido")

    def cancelar_energia(self, d=None) -> None:
        self.remoto.cancelar_energia_painel()

    def encerrar(self) -> None:
        self.desligar()


# ---------------------------------------------------------------- HTTP local (painel)

def criar_handler(app: App, porta_ref: list):
    acoes = {
        "/api/ligar": app.ligar, "/api/desligar": app.desligar, "/api/senha": app.nova_senha,
        "/api/config": app.config, "/api/convite": app.gerar_convite, "/api/derrubar": app.derrubar,
        "/api/esquecer": app.esquecer, "/api/energia/cancelar": app.cancelar_energia,
        "/api/monitor/instalar": app.instalar_monitor,
    }

    class Handler(BaseHTTPRequestHandler):
        server_version = "PonteRemota"

        def log_message(self, *a):
            pass

        def _host_ok(self) -> bool:  # bloqueia "DNS rebinding": só quem chamou pelo endereço local
            return self.headers.get("Host") in (f"127.0.0.1:{porta_ref[0]}", f"localhost:{porta_ref[0]}")

        def _token_ok(self) -> bool:
            dado = self.headers.get("X-Token") or ""
            if not dado:
                q = urlparse(self.path).query
                dado = next((p[2:] for p in q.split("&") if p.startswith("t=")), "")
            return secrets.compare_digest(dado, app.token)

        def _responder(self, codigo: int, corpo: bytes, tipo: str) -> None:
            self.send_response(codigo)
            self.send_header("Content-Type", tipo)
            self.send_header("Content-Length", str(len(corpo)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(corpo)

        def _json(self, codigo: int, obj) -> None:
            self._responder(codigo, json.dumps(obj, ensure_ascii=False).encode(), "application/json; charset=utf-8")

        def do_GET(self):
            url = urlparse(self.path)
            if not self._host_ok():
                return self._json(403, {"erro": "host"})
            if url.path in ARQUIVOS:
                nome, tipo = ARQUIVOS[url.path]
                try:
                    return self._responder(200, (PASTA_INTERFACE / nome).read_bytes(), tipo)
                except OSError:
                    return self._json(404, {"erro": "arquivo"})
            if url.path == "/api/ponte":  # a ponte WebRTC (não conta como "o painel está aberto")
                if not self._token_ok():
                    return self._json(403, {"erro": "token"})
                return self._json(200, app.dados_ponte())
            if url.path in ("/api/estado", "/api/ping"):
                if not self._token_ok():
                    return self._json(403, {"erro": "token"})
                app.ultimo_contato = time.monotonic()
                return self._json(200, app.estado() if url.path == "/api/estado" else {"ok": True})
            self._json(404, {"erro": "não encontrado"})

        def do_POST(self):
            url = urlparse(self.path)
            if not self._host_ok() or not self._token_ok():
                return self._json(403, {"erro": "acesso negado"})
            tam = min(int(self.headers.get("Content-Length") or 0), 65536)
            bruto = self.rfile.read(tam) if tam else b""
            if url.path == "/api/fechar":  # sendBeacon quando a janela fecha ou recarrega
                app.pedido_fechar = time.monotonic()
                return self._json(200, {"ok": True})
            if url.path == "/api/janela":  # outra cópia do app pediu para mostrar o painel
                app.pedido_janela = True
                return self._json(200, {"ok": True})
            if url.path == "/api/ponte/estado":
                try:
                    app.estado_ponte(json.loads(bruto or b"{}"))
                except (ValueError, TypeError, AttributeError):
                    return self._json(400, {"erro": "pedido inválido"})
                return self._json(200, {"ok": True})
            if url.path == "/api/encerrar":
                app.pedido_sair = True
                return self._json(200, {"ok": True})
            acao = acoes.get(url.path)
            if not acao:
                return self._json(404, {"erro": "não encontrado"})
            try:
                dados = json.loads(bruto or b"{}")
                if not isinstance(dados, dict):
                    raise ValueError
            except ValueError:
                return self._json(400, {"erro": "pedido inválido"})
            try:
                acao(dados)
            except ErroUsuario as e:
                return self._json(400, {"erro": str(e), **e.extra})
            except Exception as e:
                comum.log(f"erro inesperado em {url.path}: {type(e).__name__}: {e}")
                return self._json(500, {"erro": f"{type(e).__name__}: {e}"})
            self._json(200, app.estado())

    return Handler


# ---------------------------------------------------------------- janela e instância única

def achar_navegador() -> str | None:
    """Edge ou Chrome, que abrem uma janela de aplicativo (sem abas nem barra de endereço)."""
    if sys.platform == "win32":
        bases = [os.environ.get(v) for v in ("ProgramFiles(x86)", "ProgramFiles", "LocalAppData")]
        relativos = [r"Microsoft\Edge\Application\msedge.exe", r"Google\Chrome\Application\chrome.exe",
                     r"BraveSoftware\Brave-Browser\Application\brave.exe"]
        candidatos = [str(Path(b) / r) for r in relativos for b in bases if b]
    elif sys.platform == "darwin":
        candidatos = ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                      "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"]
    else:
        candidatos = [shutil.which(n) or "" for n in ("google-chrome", "chromium", "microsoft-edge")]
    return next((c for c in candidatos if c and os.path.isfile(c)), None)


def abrir_janela(url: str):
    exe = achar_navegador()
    if exe:
        perfil = comum.PASTA / "janela"  # perfil próprio: a janela vira um processo nosso
        args = [exe, f"--app={url}", f"--user-data-dir={perfil}", "--window-size=1120,880",
                "--no-first-run", "--no-default-browser-check", "--disable-sync",
                "--disable-features=Translate,msEdgeSidebarV2"]
        try:
            return subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL)
        except OSError as e:
            comum.log(f"não consegui abrir {exe}: {e}")
    webbrowser.open(url)
    return None


def outra_instancia() -> dict | None:
    """Se já há um Ponte Remota rodando (por exemplo, em segundo plano), devolve como falar com ele."""
    info = comum.ler_json("instancia.json", {})
    if not info.get("porta") or not info.get("token"):
        return None
    try:
        pedido = urllib.request.Request(f"http://127.0.0.1:{info['porta']}/api/ping",
                                        headers={"X-Token": info["token"]})
        with _LOCAL.open(pedido, timeout=2) as r:
            return info if r.status == 200 else None
    except (OSError, ValueError):
        return None


def chamar(info: dict, caminho: str) -> None:
    pedido = urllib.request.Request(f"http://127.0.0.1:{info['porta']}{caminho}", data=b"{}", method="POST",
                                    headers={"X-Token": info["token"], "Content-Type": "application/json"})
    try:
        _LOCAL.open(pedido, timeout=3).close()
    except OSError:
        pass


class Ponte:
    """O WebRTC do lado do PC roda num Edge/Chrome sem janela (ponte.html), que já vem com o Windows.
    Ele conversa com o ponto de encontro e repassa cada canal direto do tablet ao servidor local."""

    def __init__(self, url: str):
        self.url = url
        self.proc = None
        self.proxima = 0.0
        self.falhas = 0

    def manter(self, querer: bool) -> None:
        vivo = self.proc is not None and self.proc.poll() is None
        if not querer:
            if vivo:
                self.parar()
            self.falhas = 0
            return
        if vivo or time.monotonic() < self.proxima:
            return
        if self.proc is not None:  # caiu: tenta de novo, cada vez esperando mais
            self.falhas += 1
            comum.log("a ponte de longe parou; reiniciando")
        self.proxima = time.monotonic() + min(60, 3 * 2 ** min(self.falhas, 4))
        exe = achar_navegador()
        if not exe:
            comum.log("de longe: não achei o Edge nem o Chrome neste PC")
            self.proc = None
            return
        args = [exe, "--headless=new", f"--user-data-dir={comum.PASTA / 'ponte-longe'}", "--no-first-run",
                "--no-default-browser-check", "--disable-sync", "--mute-audio", "--disable-gpu",
                "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
                # mostra os IPs reais (e não nomes .local) ao tablet: facilita achar o caminho direto
                "--disable-features=WebRtcHideLocalIpsWithMdns,Translate", self.url]
        if sys.platform.startswith("linux") and hasattr(os, "geteuid") and os.geteuid() == 0:
            args.insert(1, "--no-sandbox")
        try:
            self.proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL, creationflags=comum.SEM_JANELA)
            comum.log("ponte de longe iniciada")
        except OSError as e:
            comum.log(f"de longe: não consegui abrir {exe}: {e}")
            self.proc = None

    def parar(self) -> None:
        if self.proc is not None and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.proc = None


def main() -> None:
    ap = argparse.ArgumentParser(description="Ponte Remota")
    ap.add_argument("--segundo-plano", action="store_true", help="sem janela, já com o acesso ligado")
    ap.add_argument("--com-terminal", action="store_true", help="mantém o terminal aberto (mostra o registro)")
    ap.add_argument("--sem-janela", action="store_true", help="não abre janela; imprime o endereço do painel (testes)")
    args = ap.parse_args()
    if not (args.segundo_plano or args.com_terminal or args.sem_janela) and _soltar_do_terminal():
        return
    _redirecionar_saidas()

    existente = outra_instancia()
    if existente:
        if not args.segundo_plano:
            chamar(existente, "/api/janela")  # mostra o painel do app que já está rodando
        return

    controle.preparar_dpi()
    app = App()
    porta_ref = [0]
    http = ThreadingHTTPServer(("127.0.0.1", 0), criar_handler(app, porta_ref))
    http.daemon_threads = True
    porta_ref[0] = http.server_address[1]
    threading.Thread(target=http.serve_forever, daemon=True).start()
    comum.salvar_json("instancia.json", {"pid": os.getpid(), "porta": porta_ref[0], "token": app.token},
                      secreto=True)
    url = f"http://127.0.0.1:{porta_ref[0]}/?t={app.token}"
    ponte = Ponte(f"http://127.0.0.1:{porta_ref[0]}/ponte.html?t={app.token}")
    comum.log(f"Ponte Remota {comum.VERSAO} aberto")

    if args.segundo_plano:
        try:
            app.ligar({})
        except ErroUsuario as e:
            comum.log(str(e))
    janela = None
    if args.sem_janela:
        print(f"URL {url}", flush=True)
    elif not args.segundo_plano:
        janela = abrir_janela(url)
    aberta_em = time.monotonic()
    tem_janela = janela is not None or not (args.segundo_plano or args.sem_janela)
    acordado = None

    try:
        while not app.pedido_sair:
            time.sleep(0.4)
            agora = time.monotonic()
            fechou = False
            if janela is not None and janela.poll() is not None:
                if agora - aberta_em > 6:
                    fechou = True
                janela = None  # o navegador pode ter repassado a janela a outro processo: usa os sinais da página
            if app.pedido_fechar and agora - app.pedido_fechar > 4 and app.ultimo_contato < app.pedido_fechar:
                fechou = True
                app.pedido_fechar = None
            if fechou and tem_janela:
                comum.log("janela fechada: desligando o acesso e encerrando")
                break
            if app.pedido_janela:
                app.pedido_janela = False
                janela = abrir_janela(url)
                aberta_em, tem_janela = time.monotonic(), True
            if not tem_janela and not app.remoto.ligado and not args.sem_janela:
                if agora - app.ultimo_contato > 20:
                    break  # acesso desligado e ninguém olhando o painel: nada a fazer
            ponte.manter(app.longe_ativo())
            # não deixa o PC dormir: com alguém conectado, nem a tela
            desejado = ("tela" if app.remoto.sessoes else
                        "sistema" if app.remoto.ligado and app.cfg.get("nao_dormir") else None)
            if desejado != acordado:
                acordado = desejado
                try:
                    controle.manter_acordado(desejado is not None, desejado == "tela")
                except Exception:
                    pass
    except KeyboardInterrupt:
        pass
    finally:
        ponte.parar()
        app.encerrar()
        try:
            controle.manter_acordado(False)
        except Exception:
            pass
        info = comum.ler_json("instancia.json", {})
        if info.get("pid") == os.getpid():
            try:
                (comum.PASTA / "instancia.json").unlink()
            except OSError:
                pass
        http.shutdown()
        comum.log("Ponte Remota encerrado")


if __name__ == "__main__":
    main()
