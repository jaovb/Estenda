"""Ponte Remota: partes usadas por todo o app (pasta de dados, senha, registro, endereços)."""
from __future__ import annotations

import ipaddress
import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

VERSAO = "1.8"
PROTOCOLO = 1
PORTA_PADRAO = 24860
PASTA = Path(os.environ.get("PONTE_REMOTA_CONFIG") or Path.home() / ".ponte-remota")
SIMULAR = bool(os.environ.get("PONTE_REMOTA_SIMULAR"))  # testes sem Windows: tela e controle de mentira

REDE_TAILSCALE = ipaddress.ip_network("100.64.0.0/10")
REDE_TAILSCALE6 = ipaddress.ip_network("fd7a:115c:a1e0::/48")
SEM_JANELA = 0x08000000 if sys.platform == "win32" else 0  # CREATE_NO_WINDOW: comandos sem piscar terminal

_saida_log = None


def definir_log(func) -> None:
    global _saida_log
    _saida_log = func


def log(msg: str) -> None:
    linha = time.strftime("%H:%M:%S") + " " + msg
    if _saida_log:
        _saida_log(linha)
    elif sys.stdout:
        try:
            print(linha, flush=True)
        except Exception:
            pass


# ---------------------------------------------------------------- arquivos

def ler_json(nome: str, padrao):
    try:
        dados = json.loads((PASTA / nome).read_text(encoding="utf-8"))
        return dados if isinstance(dados, type(padrao)) else padrao
    except (OSError, ValueError):
        return padrao


def salvar_json(nome: str, dados, secreto: bool = False) -> None:
    """Grava num temporário e troca, para um desligamento no meio não corromper o arquivo."""
    try:
        PASTA.mkdir(parents=True, exist_ok=True)
        tmp = PASTA / (nome + ".tmp")
        tmp.write_text(json.dumps(dados, ensure_ascii=False, indent=1), encoding="utf-8")
        if secreto:
            os.chmod(tmp, 0o600)
        os.replace(tmp, PASTA / nome)
    except OSError as e:
        log(f"não consegui salvar {nome}: {e}")


# ---------------------------------------------------------------- senha

def normalizar_senha(senha: str) -> str:
    """Ignora espaços, hífens e maiúsculas, para facilitar digitar no tablet."""
    return "".join(str(senha).split()).replace("-", "").lower()


def gerar_senha() -> str:
    alfabeto = "abcdefghjkmnpqrstuvwxyz23456789"  # sem 0/o, 1/l/i
    s = "".join(secrets.choice(alfabeto) for _ in range(12))  # ~59 bits
    return f"{s[:4]}-{s[4:8]}-{s[8:]}"


def ler_senha() -> str:
    try:
        s = (PASTA / "senha").read_text(encoding="utf-8").strip()
        if len(normalizar_senha(s)) >= 8:
            return s
    except OSError:
        pass
    s = gerar_senha()
    salvar_senha(s)
    return s


def salvar_senha(senha: str) -> None:
    try:
        PASTA.mkdir(parents=True, exist_ok=True)
        arq = PASTA / "senha"
        arq.write_text(senha, encoding="utf-8")
        os.chmod(arq, 0o600)
    except OSError as e:
        log(f"não consegui salvar a senha: {e}")


# ---------------------------------------------------------------- rede

def tipo_de_ip(texto: str) -> str:
    """'loopback', 'tailscale', 'local' (Wi-Fi/cabo de casa) ou 'externo'."""
    try:
        ip = ipaddress.ip_address(texto.split("%")[0])
    except ValueError:
        return "externo"
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    if ip.is_loopback:
        return "loopback"
    if (ip.version == 4 and ip in REDE_TAILSCALE) or (ip.version == 6 and ip in REDE_TAILSCALE6):
        return "tailscale"
    if ip.is_private or ip.is_link_local:
        return "local"
    return "externo"


def _ips_da_maquina() -> list:
    ips = []
    try:  # a interface que sai para a internet (o Wi-Fi ou o cabo), sem enviar nada
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        ips.append(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            if info[4][0] not in ips:
                ips.append(info[4][0])
    except OSError:
        pass
    return [ip for ip in ips if not ip.startswith(("127.", "169.254."))]


def _achar_tailscale() -> str | None:
    achado = shutil.which("tailscale")
    if achado:
        return achado
    if sys.platform == "win32":
        for base in (os.environ.get("ProgramFiles"), os.environ.get("ProgramFiles(x86)")):
            if base:
                c = Path(base) / "Tailscale" / "tailscale.exe"
                if c.is_file():
                    return str(c)
    elif sys.platform == "darwin":
        c = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
        if os.path.isfile(c):
            return c
    return None


def _status_tailscale() -> dict:
    exe = _achar_tailscale()
    if not exe:
        return {"estado": "ausente"}
    try:
        r = subprocess.run([exe, "status", "--json"], capture_output=True, timeout=4,
                           creationflags=SEM_JANELA, stdin=subprocess.DEVNULL)
        dados = json.loads(r.stdout.decode("utf-8", "replace") or "{}")
    except (OSError, ValueError, subprocess.SubprocessError):
        return {"estado": "ausente"}
    eu = dados.get("Self") or {}
    estado = {"Running": "ligado", "NeedsLogin": "sem-login", "Stopped": "desligado"}.get(
        dados.get("BackendState"), "desligado")
    ips = [ip for ip in (eu.get("TailscaleIPs") or []) if ":" not in ip]
    dns = (eu.get("DNSName") or "").rstrip(".") or None
    return {"estado": estado, "ips": ips, "dns": dns}


class Enderecos:
    """Endereços para abrir no tablet. O status do Tailscale demora (roda um comando),
    então é atualizado numa linha de execução separada e lido da memória."""

    def __init__(self):
        self._dados = {"tailscale": [], "local": [], "dns": None, "estado_tailscale": "verificando"}
        self._quando = 0.0
        self._rodando = False
        self._lock = threading.Lock()

    def _atualizar(self) -> None:
        try:
            ts = {"estado": "ausente"} if SIMULAR else _status_tailscale()
            ips = _ips_da_maquina()
            tailscale = list(ts.get("ips") or [])
            for ip in ips:
                if tipo_de_ip(ip) == "tailscale" and ip not in tailscale:
                    tailscale.append(ip)
            local = [ip for ip in ips if tipo_de_ip(ip) == "local"]
            estado = ts["estado"]
            if estado == "ausente" and tailscale:
                estado = "ligado"  # sem o comando, mas com o IP 100.x na máquina
            with self._lock:
                self._dados = {"tailscale": tailscale if estado == "ligado" else [], "local": local[:3],
                               "dns": ts.get("dns") if estado == "ligado" else None,
                               "estado_tailscale": estado}
                self._quando = time.monotonic()
        finally:
            self._rodando = False

    def obter(self, forcar: bool = False) -> dict:
        with self._lock:
            velho = forcar or time.monotonic() - self._quando > 15
            if velho and not self._rodando:
                self._rodando = True
                threading.Thread(target=self._atualizar, daemon=True).start()
            return dict(self._dados)
