"""Controle de mentira, para testar o app fora do Windows (PONTE_REMOTA_SIMULAR=1).
Guarda o que o tablet mandou; a captura simulada (tela.py) desenha isso numa área de
trabalho falsa, então dá para ver cliques, rolagem e texto chegando."""
from __future__ import annotations

import threading
import time

_lock = threading.Lock()
MONITORES = [
    {"x": 0, "y": 0, "w": 1920, "h": 1080, "principal": True, "dispositivo": "SIM1"},
    {"x": 1920, "y": 0, "w": 1280, "h": 1024, "principal": False, "dispositivo": "SIM2"},
]
estado = {
    "cursor": [960, 540], "cliques": [], "texto": "", "rolagem": 0, "area": "texto do PC simulado",
    "botoes": set(), "teclas": [], "energia": [],
}


def preparar_dpi() -> None:
    pass


def tela_virtual() -> tuple:
    return 0, 0, 3200, 1080


def monitores() -> list:
    return [dict(m) for m in MONITORES]


def area_de_trabalho():
    return "Default"


def _clamp(x, y):
    return min(max(int(x), 0), 3199), min(max(int(y), 0), 1079)


def mover(x, y) -> None:
    with _lock:
        estado["cursor"] = list(_clamp(x, y))


def botao(b, desce, x=None, y=None) -> None:
    with _lock:
        if x is not None and y is not None:
            estado["cursor"] = list(_clamp(x, y))
        if desce:
            estado["botoes"].add(b)
            estado["cliques"].append((time.monotonic(), tuple(estado["cursor"]), b))
            estado["cliques"] = estado["cliques"][-20:]
        else:
            estado["botoes"].discard(b)


def roda(dy=0, dx=0) -> None:
    with _lock:
        estado["rolagem"] += int(dy)


def tecla(vk, desce, estendida=False) -> None:
    with _lock:
        if desce:
            estado["teclas"] = (estado["teclas"] + [vk])[-12:]
            if vk == 0x08:
                estado["texto"] = estado["texto"][:-1]
            elif vk == 0x0D:
                estado["texto"] += "\n"


def atalho(vks) -> None:
    with _lock:
        estado["teclas"] = (estado["teclas"] + ["+".join(hex(v) for v in vks)])[-12:]


def texto(s) -> None:
    with _lock:
        for ch in s:
            if ch == "\b":
                estado["texto"] = estado["texto"][:-1]
            elif ch != "\r":
                estado["texto"] += ch
        estado["texto"] = estado["texto"][-600:]


def cursor() -> tuple:
    with _lock:
        x, y = estado["cursor"]
    return x, y, ("texto" if 300 <= x <= 1300 and 200 <= y <= 700 else "seta"), True


def area_ler() -> str:
    with _lock:
        return estado["area"]


def area_escrever(s) -> bool:
    with _lock:
        estado["area"] = s
    return True


def energia(acao) -> None:
    with _lock:
        estado["energia"].append(acao)


def manter_acordado(sistema, tela=False) -> None:
    pass


def iniciar_com_windows(comando) -> None:
    pass


def inicia_com_windows():
    return None
