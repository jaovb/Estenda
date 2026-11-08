"""Ponte Remota: captura da tela e compressão.

A tela é reduzida para o tamanho escolhido e dividida em blocos de 64×64. Só os blocos
que mudaram vão para o tablet, em JPEG. Mudança pequena (digitar, um menu) já vai nítida;
mudança grande (rolar, vídeo) vai mais leve e, quando a tela para, os mesmos blocos são
reenviados nítidos ("refino"). Assim a imagem anda rápido e fica bonita parada.
"""
from __future__ import annotations

import io
import math
import struct
import sys
import threading
import time
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

import comum
import controle

BLOCO = 64
PRESETS = {  # escala máxima, maior lado máximo, qualidade em movimento, qualidade do refino
    "nitida": {"escala": 1.0, "lado": 2560, "q": 74, "q_fina": 92},
    "equilibrada": {"escala": 0.75, "lado": 1920, "q": 64, "q_fina": 90},
    "leve": {"escala": 0.5, "lado": 1280, "q": 52, "q_fina": 86},
}
FRACAO_FINA = 0.04  # até 4% da tela mudando: manda nítido de uma vez
MAX_RETANGULOS = 24


class ErroCaptura(Exception):
    def __init__(self, motivo: str):
        super().__init__(motivo)
        self.motivo = motivo  # "segura" (bloqueio/UAC) ou "falhou"


def _limiar(v: int) -> int:
    return 255 if v else 0


# ---------------------------------------------------------------- captura

class Captura:
    def __init__(self):
        self._local = threading.local()
        self._simulada = _CapturaSimulada() if controle.SIMULADO else None
        self._mss = None
        if not self._simulada:
            try:
                import mss
                self._mss = mss
            except ImportError:
                comum.log("biblioteca mss ausente: usando a captura do Pillow (mais lenta)")

    def capturar(self, mon: dict) -> Image.Image:
        if self._simulada:
            return self._simulada.desenhar(mon)
        try:
            img = self._capturar(mon)
        except Exception as e:
            self._local.sct = None
            raise ErroCaptura("segura" if controle.area_de_trabalho() != "Default" else "falhou") from e
        if img.getbbox() is None and controle.area_de_trabalho() != "Default":
            raise ErroCaptura("segura")  # tela de bloqueio costuma vir toda preta
        return img

    def _capturar(self, mon: dict) -> Image.Image:
        if self._mss:
            sct = getattr(self._local, "sct", None)
            if sct is None:  # a mss guarda recursos por linha de execução: uma instância por linha
                sct = self._local.sct = self._mss.mss()
            shot = sct.grab({"left": mon["x"], "top": mon["y"], "width": mon["w"], "height": mon["h"]})
            return Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX")
        from PIL import ImageGrab
        return ImageGrab.grab(bbox=(mon["x"], mon["y"], mon["x"] + mon["w"], mon["y"] + mon["h"]),
                              all_screens=True).convert("RGB")


# ---------------------------------------------------------------- compressão

def _jpeg(img: Image.Image, q: int, sub: int) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=int(q), subsampling=sub, optimize=False)
    return buf.getvalue()


def tamanho_reduzido(w: int, h: int, preset: str) -> tuple:
    p = PRESETS.get(preset, PRESETS["equilibrada"])
    esc = min(p["escala"], p["lado"] / max(w, h))
    return max(1, round(w * esc)), max(1, round(h * esc))


class Codificador:
    """Guarda o último quadro enviado e devolve só o que mudou."""

    def __init__(self):
        self.ant = None
        self.cols = self.lins = 0
        self.baixa = bytearray()  # blocos que foram em qualidade baixa e ainda não foram refinados

    def reiniciar(self) -> None:
        self.ant = None

    def _reduzir(self, img: Image.Image, preset: str) -> Image.Image:
        w, h = tamanho_reduzido(*img.size, preset)
        if (w, h) == img.size:
            return img
        if w * 2 == img.width and h * 2 == img.height:
            return img.reduce(2)
        return img.resize((w, h), Image.BILINEAR, reducing_gap=2.0)

    def _mascara(self, dif: Image.Image) -> bytearray:
        """1 por bloco que mudou. Reduz em duas etapas de 8, reforçando entre elas,
        para nem um pixel alterado sumir na média."""
        m = dif.point(_limiar).convert("L").point(_limiar)
        m = m.reduce(8).point(_limiar).reduce(8)
        return bytearray(1 if v else 0 for v in m.tobytes())

    def _retangulos(self, mascara: bytearray, w: int, h: int) -> list:
        cols, lins = self.cols, self.lins
        abertos, fechados = {}, []
        for li in range(lins):
            linha = mascara[li * cols:(li + 1) * cols]
            corridas, c = set(), 0
            while c < cols:
                if linha[c]:
                    c0 = c
                    while c < cols and linha[c]:
                        c += 1
                    corridas.add((c0, c))
                else:
                    c += 1
            for chave in [k for k in abertos if k not in corridas]:
                fechados.append((chave, abertos.pop(chave)))
            for chave in corridas:
                if chave in abertos:
                    abertos[chave][1] = li + 1
                else:
                    abertos[chave] = [li, li + 1]
        fechados += list(abertos.items())
        if len(fechados) > MAX_RETANGULOS:  # muitos pedaços: um retângulo só, em volta de tudo
            c0 = min(k[0] for k, _ in fechados)
            c1 = max(k[1] for k, _ in fechados)
            l0 = min(v[0] for _, v in fechados)
            l1 = max(v[1] for _, v in fechados)
            fechados = [((c0, c1), [l0, l1])]
        rets = []
        for (c0, c1), (l0, l1) in fechados:
            x, y = c0 * BLOCO, l0 * BLOCO
            rets.append((x, y, min(c1 * BLOCO, w) - x, min(l1 * BLOCO, h) - y))
        return rets

    def codificar(self, img: Image.Image, preset: str, q_mov: int):
        """Devolve (completo, largura, altura, pedaços) ou None se nada mudou."""
        p = PRESETS.get(preset, PRESETS["equilibrada"])
        red = self._reduzir(img, preset)
        w, h = red.size
        completo = self.ant is None or self.ant.size != red.size
        if completo:
            self.cols, self.lins = math.ceil(w / BLOCO), math.ceil(h / BLOCO)
            mascara = bytearray([1]) * (self.cols * self.lins)
            self.baixa = bytearray(self.cols * self.lins)
        else:
            dif = ImageChops.difference(red, self.ant)
            if dif.getbbox() is None:
                return None
            mascara = self._mascara(dif)
            if not any(mascara):
                return None
        self.ant = red
        fracao = sum(mascara) / len(mascara)
        fino = not completo and fracao <= FRACAO_FINA
        q, sub = (p["q_fina"], 0) if fino else (q_mov, 2)
        pedacos = [(x, y, cw, ch, _jpeg(red.crop((x, y, x + cw, y + ch)), q, sub))
                   for x, y, cw, ch in self._retangulos(mascara, w, h)]
        marca = 0 if fino else 1
        for i, v in enumerate(mascara):
            if v:
                self.baixa[i] = marca
        return completo, w, h, pedacos

    def refinar(self, preset: str, rebaixe: int = 0):
        """Reenvia nítido o que foi em qualidade baixa. None se não há nada para refinar.
        rebaixe > 0 quando a rede está apertada: o refino também fica mais leve."""
        if self.ant is None or not any(self.baixa):
            return None
        p = PRESETS.get(preset, PRESETS["equilibrada"])
        q, sub = max(70, p["q_fina"] - rebaixe), (0 if rebaixe < 10 else 2)
        w, h = self.ant.size
        pedacos = [(x, y, cw, ch, _jpeg(self.ant.crop((x, y, x + cw, y + ch)), q, sub))
                   for x, y, cw, ch in self._retangulos(self.baixa, w, h)]
        self.baixa = bytearray(len(self.baixa))
        return False, w, h, pedacos


def montar_quadro(ident: int, flags: int, w: int, h: int, pedacos: list) -> bytes:
    """Formato (little-endian): tipo u8=1, flags u8, largura u16, altura u16, id u32, n u16,
    e para cada pedaço: x u16, y u16, w u16, h u16, tamanho u32, JPEG."""
    partes = [struct.pack("<BBHHIH", 1, flags, w, h, ident, len(pedacos))]
    for x, y, pw, ph, dados in pedacos:
        partes.append(struct.pack("<HHHHI", x, y, pw, ph, len(dados)))
        partes.append(dados)
    return b"".join(partes)


# ---------------------------------------------------------------- tela simulada (testes)

class _CapturaSimulada:
    """Área de trabalho falsa que mostra o que o tablet mandou (só para testar fora do Windows)."""

    def __init__(self):
        import controle_sim
        self.est = controle_sim.estado
        self.lock = controle_sim._lock
        base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent)) / "interface" / "fontes"
        try:
            self.f_txt = ImageFont.truetype(str(base / "SpaceGrotesk.ttf"), 26)
            self.f_tit = ImageFont.truetype(str(base / "SpaceGrotesk.ttf"), 22)
            self.f_mono = ImageFont.truetype(str(base / "JetBrainsMono.ttf"), 22)
        except OSError:
            self.f_txt = self.f_tit = self.f_mono = ImageFont.load_default()
        self._fundos = {}

    def _fundo(self, w, h, tom):
        chave = (w, h, tom)
        if chave not in self._fundos:
            topo = Image.new("RGB", (1, 2))
            topo.putpixel((0, 0), (38, 70, 92) if tom == 0 else (70, 52, 92))
            topo.putpixel((0, 1), (120, 170, 160) if tom == 0 else (190, 140, 120))
            self._fundos[chave] = topo.resize((w, h), Image.BILINEAR)
        return self._fundos[chave].copy()

    def desenhar(self, mon: dict) -> Image.Image:
        w, h = mon["w"], mon["h"]
        segunda = mon["x"] != 0
        img = self._fundo(w, h, 1 if segunda else 0)
        d = ImageDraw.Draw(img)
        with self.lock:
            texto = self.est["texto"]
            rolagem = self.est["rolagem"]
            cliques = list(self.est["cliques"])
            teclas = list(self.est["teclas"])
            energia = list(self.est["energia"])
            area = self.est["area"]
        # janela
        jx, jy, jw, jh = (120, 120, 1000, 640) if not segunda else (80, 80, 900, 560)
        d.rectangle((jx, jy, jx + jw, jy + jh), fill=(250, 248, 242), outline=(60, 60, 60))
        d.rectangle((jx, jy, jx + jw, jy + 44), fill=(34, 39, 45))
        d.text((jx + 16, jy + 10), "Bloco de Notas — Ponte Remota (simulado)" if not segunda else "Segunda tela",
               font=self.f_tit, fill=(217, 221, 215))
        linhas, atual = [], ""
        for ch in texto + "|":
            if ch == "\n" or d.textlength(atual + ch, font=self.f_txt) > jw - 40:
                linhas.append(atual)
                atual = "" if ch == "\n" else ch
            else:
                atual += ch
        linhas.append(atual)
        for i, linha in enumerate(linhas[-16:]):
            d.text((jx + 20, jy + 64 + i * 34), linha, font=self.f_txt, fill=(30, 33, 36))
        d.text((jx + 20, jy + jh - 40), f"rolagem: {rolagem}   área de transferência: {area[:40]}",
               font=self.f_mono, fill=(110, 110, 110))
        # animação contínua (para testar movimento)
        t = time.monotonic()
        bx = int(jx + 40 + (math.sin(t * 1.3) * 0.5 + 0.5) * (jw - 200))
        d.rounded_rectangle((bx, jy + jh + 30, bx + 120, jy + jh + 70), radius=12, fill=(140, 199, 181))
        # cliques recentes
        for quando, (cx, cy), b in cliques:
            idade = t - quando
            if idade < 1.2 and mon["x"] <= cx < mon["x"] + w:
                r = int(14 + idade * 40)
                cor = {0: (140, 199, 181), 2: (223, 184, 119), 1: (227, 159, 147)}.get(b, (255, 255, 255))
                px, py = cx - mon["x"], cy - mon["y"]
                d.ellipse((px - r, py - r, px + r, py + r), outline=cor, width=4)
        # barra de tarefas com relógio
        d.rectangle((0, h - 48, w, h), fill=(28, 31, 36))
        d.text((w - 150, h - 38), time.strftime("%H:%M:%S"), font=self.f_mono, fill=(230, 230, 230))
        d.text((20, h - 38), "teclas: " + " ".join(str(k) for k in teclas[-6:]) +
               ("   energia: " + ",".join(energia[-3:]) if energia else ""), font=self.f_mono, fill=(160, 160, 160))
        return img
