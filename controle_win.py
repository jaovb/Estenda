"""Controle do Windows por ctypes, sem bibliotecas extras: mouse, teclado, cursor,
monitores, área de transferência, energia, "não dormir" e iniciar com o Windows.

Coordenadas sempre em pixels reais da área de trabalho virtual (o app pede
SetProcessDpiAwareness(2) logo ao abrir, então escala de 125%/150% não atrapalha).
"""
from __future__ import annotations

import ctypes
import struct
import subprocess
import sys
import threading
import time

if sys.platform != "win32":
    raise ImportError("controle_win só funciona no Windows")

import winreg

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

c_int32, c_uint32, c_uint16 = ctypes.c_int32, ctypes.c_uint32, ctypes.c_uint16
ULONG_PTR = ctypes.c_size_t
HANDLE = ctypes.c_void_p
SEM_JANELA = 0x08000000


# ---------------------------------------------------------------- estruturas

class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", c_int32), ("dy", c_int32), ("mouseData", c_uint32), ("dwFlags", c_uint32),
                ("time", c_uint32), ("dwExtraInfo", ULONG_PTR)]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", c_uint16), ("wScan", c_uint16), ("dwFlags", c_uint32), ("time", c_uint32),
                ("dwExtraInfo", ULONG_PTR)]


class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [("uMsg", c_uint32), ("wParamL", c_uint16), ("wParamH", c_uint16)]


class _UNIAO(ctypes.Union):
    _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT), ("hi", HARDWAREINPUT)]


class INPUT(ctypes.Structure):
    _anonymous_ = ("u",)
    _fields_ = [("type", c_uint32), ("u", _UNIAO)]


class POINT(ctypes.Structure):
    _fields_ = [("x", c_int32), ("y", c_int32)]


class RECT(ctypes.Structure):
    _fields_ = [("left", c_int32), ("top", c_int32), ("right", c_int32), ("bottom", c_int32)]


class CURSORINFO(ctypes.Structure):
    _fields_ = [("cbSize", c_uint32), ("flags", c_uint32), ("hCursor", HANDLE), ("ptScreenPos", POINT)]


class MONITORINFOEXW(ctypes.Structure):
    _fields_ = [("cbSize", c_uint32), ("rcMonitor", RECT), ("rcWork", RECT), ("dwFlags", c_uint32),
                ("szDevice", ctypes.c_wchar * 32)]


assert ctypes.sizeof(INPUT) == (40 if ctypes.sizeof(ctypes.c_void_p) == 8 else 28)

MonitorEnumProc = ctypes.WINFUNCTYPE(ctypes.c_int, HANDLE, HANDLE, ctypes.POINTER(RECT), ctypes.c_ssize_t)

user32.SendInput.argtypes = (ctypes.c_uint, ctypes.POINTER(INPUT), ctypes.c_int)
user32.SendInput.restype = ctypes.c_uint
user32.GetSystemMetrics.argtypes = (ctypes.c_int,)
user32.GetSystemMetrics.restype = ctypes.c_int
user32.MapVirtualKeyW.argtypes = (ctypes.c_uint, ctypes.c_uint)
user32.MapVirtualKeyW.restype = ctypes.c_uint
user32.GetCursorPos.argtypes = (ctypes.POINTER(POINT),)
user32.GetCursorInfo.argtypes = (ctypes.POINTER(CURSORINFO),)
user32.LoadCursorW.argtypes = (HANDLE, HANDLE)
user32.LoadCursorW.restype = HANDLE
user32.EnumDisplayMonitors.argtypes = (HANDLE, HANDLE, MonitorEnumProc, ctypes.c_ssize_t)
user32.GetMonitorInfoW.argtypes = (HANDLE, ctypes.POINTER(MONITORINFOEXW))
user32.OpenClipboard.argtypes = (HANDLE,)
user32.GetClipboardData.argtypes = (ctypes.c_uint,)
user32.GetClipboardData.restype = HANDLE
user32.SetClipboardData.argtypes = (ctypes.c_uint, HANDLE)
user32.SetClipboardData.restype = HANDLE
user32.OpenInputDesktop.argtypes = (c_uint32, ctypes.c_int, c_uint32)
user32.OpenInputDesktop.restype = HANDLE
user32.CloseDesktop.argtypes = (HANDLE,)
user32.GetUserObjectInformationW.argtypes = (HANDLE, ctypes.c_int, ctypes.c_void_p, c_uint32,
                                             ctypes.POINTER(c_uint32))
kernel32.GlobalAlloc.argtypes = (ctypes.c_uint, ctypes.c_size_t)
kernel32.GlobalAlloc.restype = HANDLE
kernel32.GlobalLock.argtypes = (HANDLE,)
kernel32.GlobalLock.restype = ctypes.c_void_p
kernel32.GlobalUnlock.argtypes = (HANDLE,)
kernel32.GlobalFree.argtypes = (HANDLE,)
kernel32.GlobalFree.restype = HANDLE
kernel32.SetThreadExecutionState.argtypes = (c_uint32,)
kernel32.SetThreadExecutionState.restype = c_uint32

INPUT_MOUSE, INPUT_KEYBOARD = 0, 1
M_MOVE, M_ABS, M_VDESK = 0x0001, 0x8000, 0x4000
M_WHEEL, M_HWHEEL = 0x0800, 0x1000
BOTOES = {  # botão -> (desce, sobe, mouseData)
    0: (0x0002, 0x0004, 0), 1: (0x0020, 0x0040, 0), 2: (0x0008, 0x0010, 0),
    3: (0x0080, 0x0100, 1), 4: (0x0080, 0x0100, 2),
}
K_EXT, K_UP, K_UNICODE = 0x0001, 0x0002, 0x0004
VK_BACK, VK_TAB, VK_RETURN = 0x08, 0x09, 0x0D
# teclas que precisam do bit "estendida" (sem ele, setas viram números do teclado numérico etc.)
ESTENDIDAS = {0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2C, 0x2D, 0x2E,
              0x5B, 0x5C, 0x5D, 0x6F, 0x90, 0xA3, 0xA5}


# ---------------------------------------------------------------- tela

def preparar_dpi() -> None:
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        try:
            user32.SetProcessDPIAware()
        except Exception:
            pass


def tela_virtual() -> tuple:
    m = user32.GetSystemMetrics
    return m(76), m(77), max(1, m(78)), max(1, m(79))  # SM_[XY]VIRTUALSCREEN, SM_C[XY]VIRTUALSCREEN


def monitores() -> list:
    lista = []

    def cada(hmon, _hdc, _ret, _dado):
        info = MONITORINFOEXW()
        info.cbSize = ctypes.sizeof(MONITORINFOEXW)
        if user32.GetMonitorInfoW(hmon, ctypes.byref(info)):
            r = info.rcMonitor
            lista.append({"x": r.left, "y": r.top, "w": r.right - r.left, "h": r.bottom - r.top,
                          "principal": bool(info.dwFlags & 1), "dispositivo": info.szDevice})
        return 1

    user32.EnumDisplayMonitors(None, None, MonitorEnumProc(cada), 0)
    if not lista:
        x, y, w, h = tela_virtual()
        lista = [{"x": x, "y": y, "w": w, "h": h, "principal": True, "dispositivo": ""}]
    lista.sort(key=lambda m: (not m["principal"], m["x"], m["y"]))
    return lista


def area_de_trabalho() -> str | None:
    """Nome da área de trabalho que recebe o teclado: 'Default' no uso normal. Na tela de
    bloqueio e nos avisos do administrador (UAC) o Windows não deixa nem abrir: devolve None."""
    h = user32.OpenInputDesktop(0, False, 0x0001)  # DESKTOP_READOBJECTS
    if not h:
        return None
    try:
        buf = ctypes.create_unicode_buffer(256)
        n = c_uint32(0)
        if user32.GetUserObjectInformationW(h, 2, buf, ctypes.sizeof(buf), ctypes.byref(n)):  # UOI_NAME
            return buf.value
        return None
    finally:
        user32.CloseDesktop(h)


# ---------------------------------------------------------------- mouse

def _enviar(entradas: list) -> int:
    if not entradas:
        return 0
    feitas = 0
    for i in range(0, len(entradas), 200):
        parte = entradas[i:i + 200]
        arr = (INPUT * len(parte))(*parte)
        feitas += user32.SendInput(len(parte), arr, ctypes.sizeof(INPUT))
    return feitas


def _mouse(dx=0, dy=0, dados=0, flags=0) -> INPUT:
    return INPUT(type=INPUT_MOUSE, mi=MOUSEINPUT(dx, dy, dados & 0xFFFFFFFF, flags, 0, 0))


def _abs(x: int, y: int) -> INPUT:
    vx, vy, vw, vh = tela_virtual()
    x = min(max(x, vx), vx + vw - 1)
    y = min(max(y, vy), vy + vh - 1)
    nx = ((x - vx) * 65536 + vw - 1) // vw  # arredonda para cima: o Windows volta exatamente ao pixel
    ny = ((y - vy) * 65536 + vh - 1) // vh
    return _mouse(nx, ny, 0, M_MOVE | M_ABS | M_VDESK)


def mover(x: int, y: int) -> None:
    _enviar([_abs(x, y)])


def botao(b: int, desce: bool, x: int | None = None, y: int | None = None) -> None:
    if b not in BOTOES:
        return
    f_desce, f_sobe, dados = BOTOES[b]
    entradas = [_abs(x, y)] if x is not None and y is not None else []
    entradas.append(_mouse(0, 0, dados, f_desce if desce else f_sobe))
    _enviar(entradas)


def roda(dy: int = 0, dx: int = 0) -> None:
    entradas = []
    if dy:
        entradas.append(_mouse(0, 0, int(dy), M_WHEEL))
    if dx:
        entradas.append(_mouse(0, 0, int(dx), M_HWHEEL))
    _enviar(entradas)


# ---------------------------------------------------------------- teclado

def _tecla(vk: int, desce: bool, estendida: bool = False) -> INPUT:
    scan = user32.MapVirtualKeyW(vk, 0) & 0xFFFF  # MAPVK_VK_TO_VSC: alguns programas leem o código físico
    flags = (0 if desce else K_UP) | (K_EXT if (estendida or vk in ESTENDIDAS) else 0)
    return INPUT(type=INPUT_KEYBOARD, ki=KEYBDINPUT(vk, scan, flags, 0, 0))


def tecla(vk: int, desce: bool, estendida: bool = False) -> None:
    if 0 < vk < 256:
        _enviar([_tecla(vk, desce, estendida)])


def atalho(vks: list) -> None:
    """Aperta todas em ordem e solta na ordem inversa (Ctrl+Shift+Esc, Win+D...)."""
    vks = [v for v in vks if 0 < v < 256][:6]
    _enviar([_tecla(v, True) for v in vks] + [_tecla(v, False) for v in reversed(vks)])


def texto(s: str) -> None:
    """Digita como Unicode: sai certo com qualquer layout (ABNT2, US...) e com acentos."""
    entradas = []
    especiais = {"\n": VK_RETURN, "\t": VK_TAB, "\b": VK_BACK}
    for ch in s:
        if ch == "\r":
            continue
        if ch in especiais:
            vk = especiais[ch]
            entradas += [_tecla(vk, True), _tecla(vk, False)]
            continue
        for (unidade,) in struct.iter_unpack("<H", ch.encode("utf-16-le")):
            entradas.append(INPUT(type=INPUT_KEYBOARD, ki=KEYBDINPUT(0, unidade, K_UNICODE, 0, 0)))
            entradas.append(INPUT(type=INPUT_KEYBOARD, ki=KEYBDINPUT(0, unidade, K_UNICODE | K_UP, 0, 0)))
    _enviar(entradas)


# ---------------------------------------------------------------- cursor

_IDS_CURSOR = {32512: "seta", 32513: "texto", 32514: "espera", 32515: "cruz", 32516: "seta",
               32642: "nwse", 32643: "nesw", 32644: "we", 32645: "ns", 32646: "mover",
               32648: "proibido", 32649: "mao", 32650: "progresso", 32651: "seta"}
_FORMAS = {}
for _id, _nome in _IDS_CURSOR.items():
    _h = user32.LoadCursorW(None, HANDLE(_id))
    if _h:
        _FORMAS[_h] = _nome


def cursor() -> tuple:
    """(x, y, forma, visível) do cursor do Windows."""
    info = CURSORINFO()
    info.cbSize = ctypes.sizeof(CURSORINFO)
    if user32.GetCursorInfo(ctypes.byref(info)):
        return (info.ptScreenPos.x, info.ptScreenPos.y, _FORMAS.get(info.hCursor, "seta"),
                bool(info.flags & 1))
    p = POINT()
    user32.GetCursorPos(ctypes.byref(p))
    return p.x, p.y, "seta", True


# ---------------------------------------------------------------- área de transferência

CF_UNICODETEXT = 13
GMEM_MOVEABLE = 0x0002


def _abrir_area() -> bool:
    for _ in range(20):  # outro programa pode estar com ela aberta
        if user32.OpenClipboard(None):
            return True
        time.sleep(0.02)
    return False


def area_ler() -> str:
    if not _abrir_area():
        return ""
    try:
        h = user32.GetClipboardData(CF_UNICODETEXT)
        if not h:
            return ""
        p = kernel32.GlobalLock(h)
        if not p:
            return ""
        try:
            return ctypes.wstring_at(p).replace("\r\n", "\n")
        finally:
            kernel32.GlobalUnlock(h)
    finally:
        user32.CloseClipboard()


def area_escrever(s: str) -> bool:
    texto_win = s.replace("\r\n", "\n").replace("\n", "\r\n")
    buf = ctypes.create_unicode_buffer(texto_win)
    tam = ctypes.sizeof(buf)
    h = kernel32.GlobalAlloc(GMEM_MOVEABLE, tam)
    if not h:
        return False
    p = kernel32.GlobalLock(h)
    if not p:
        kernel32.GlobalFree(h)
        return False
    ctypes.memmove(p, buf, tam)
    kernel32.GlobalUnlock(h)
    if not _abrir_area():
        kernel32.GlobalFree(h)
        return False
    try:
        user32.EmptyClipboard()
        if not user32.SetClipboardData(CF_UNICODETEXT, h):
            kernel32.GlobalFree(h)
            return False
        return True  # agora a memória é do Windows
    finally:
        user32.CloseClipboard()


# ---------------------------------------------------------------- energia

def _suspender() -> None:
    powrprof = ctypes.WinDLL("powrprof")
    powrprof.SetSuspendState.argtypes = (ctypes.c_ubyte, ctypes.c_ubyte, ctypes.c_ubyte)
    powrprof.SetSuspendState(0, 0, 0)  # 0 = suspender (não hibernar)


def energia(acao: str) -> None:
    """Executa na hora. A contagem regressiva (que dá para cancelar) fica no servidor:
    o 'shutdown /t N' com N > 0 fecharia os programas à força, sem perguntar se quer salvar."""
    if acao == "bloquear":
        user32.LockWorkStation()
    elif acao == "suspender":
        threading.Thread(target=_suspender, daemon=True).start()  # só volta quando o PC acordar
    elif acao in ("desligar", "reiniciar"):
        subprocess.Popen(["shutdown", "/s" if acao == "desligar" else "/r", "/t", "0"],
                         creationflags=SEM_JANELA, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def manter_acordado(sistema: bool, tela: bool = False) -> None:
    """Vale para a linha de execução que chamou: chame sempre da mesma (a principal do app)."""
    flags = 0x80000000  # ES_CONTINUOUS
    if sistema:
        flags |= 0x00000001  # ES_SYSTEM_REQUIRED
    if tela:
        flags |= 0x00000002  # ES_DISPLAY_REQUIRED
    kernel32.SetThreadExecutionState(flags)


# ---------------------------------------------------------------- iniciar com o Windows

_CHAVE_RUN = r"Software\Microsoft\Windows\CurrentVersion\Run"
_NOME_RUN = "PonteRemota"


def iniciar_com_windows(comando: str | None) -> None:
    """comando=None remove."""
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, _CHAVE_RUN, 0, winreg.KEY_SET_VALUE) as k:
        if comando:
            winreg.SetValueEx(k, _NOME_RUN, 0, winreg.REG_SZ, comando)
        else:
            try:
                winreg.DeleteValue(k, _NOME_RUN)
            except FileNotFoundError:
                pass


def inicia_com_windows() -> str | None:
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, _CHAVE_RUN) as k:
            return winreg.QueryValueEx(k, _NOME_RUN)[0]
    except OSError:
        return None
