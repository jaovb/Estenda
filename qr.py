"""Gerador de QR Code (modelo 2, modo byte, correção M, versões 1 a 10), sem bibliotecas.
Usado no painel para parear o tablet apontando a câmera. Segue a norma ISO/IEC 18004."""
from __future__ import annotations

# por versão: (codewords de correção por bloco, [(blocos, codewords de dados por bloco), ...]) — nível M
_BLOCOS_M = {
    1: (10, [(1, 16)]), 2: (16, [(1, 28)]), 3: (26, [(1, 44)]), 4: (18, [(2, 32)]),
    5: (24, [(2, 43)]), 6: (16, [(4, 27)]), 7: (18, [(4, 31)]), 8: (22, [(2, 38), (2, 39)]),
    9: (22, [(3, 36), (2, 37)]), 10: (26, [(4, 43), (1, 44)]),
}
_ALINHAMENTO = {1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30], 6: [6, 34],
                7: [6, 22, 38], 8: [6, 24, 42], 9: [6, 26, 46], 10: [6, 28, 50]}


def _gf_mul(x: int, y: int) -> int:
    z = 0
    for i in range(7, -1, -1):
        z = (z << 1) ^ ((z >> 7) * 0x11D)
        z ^= ((y >> i) & 1) * x
    return z & 0xFF


def _rs_divisor(grau: int) -> list:
    res = [0] * (grau - 1) + [1]
    raiz = 1
    for _ in range(grau):
        for j in range(grau):
            res[j] = _gf_mul(res[j], raiz)
            if j + 1 < grau:
                res[j] ^= res[j + 1]
        raiz = _gf_mul(raiz, 0x02)
    return res


def _rs_resto(dados: list, divisor: list) -> list:
    res = [0] * len(divisor)
    for b in dados:
        fator = b ^ res.pop(0)
        res.append(0)
        for i, coef in enumerate(divisor):
            res[i] ^= _gf_mul(coef, fator)
    return res


def _codewords(dados: bytes, versao: int) -> list:
    ec, grupos = _BLOCOS_M[versao]
    capacidade = sum(n * k for n, k in grupos)
    bits = []

    def por(valor, n):
        bits.extend((valor >> i) & 1 for i in range(n - 1, -1, -1))

    por(0b0100, 4)
    por(len(dados), 8 if versao < 10 else 16)
    for b in dados:
        por(b, 8)
    por(0, min(4, capacidade * 8 - len(bits)))
    por(0, (-len(bits)) % 8)
    cw = [int("".join(map(str, bits[i:i + 8])), 2) for i in range(0, len(bits), 8)]
    pad = 0xEC
    while len(cw) < capacidade:
        cw.append(pad)
        pad ^= 0xEC ^ 0x11
    # separa em blocos, calcula a correção de cada um e intercala
    blocos, i = [], 0
    divisor = _rs_divisor(ec)
    for n, k in grupos:
        for _ in range(n):
            bloco = cw[i:i + k]
            i += k
            blocos.append((bloco, _rs_resto(bloco, divisor)))
    saida = []
    for j in range(max(len(b) for b, _ in blocos)):
        saida += [b[j] for b, _ in blocos if j < len(b)]
    for j in range(ec):
        saida += [e[j] for _, e in blocos]
    return saida


class _Matriz:
    def __init__(self, versao: int):
        self.v = versao
        self.n = versao * 4 + 17
        self.mod = [[False] * self.n for _ in range(self.n)]
        self.fixo = [[False] * self.n for _ in range(self.n)]

    def por(self, x: int, y: int, escuro: bool) -> None:
        self.mod[y][x] = escuro
        self.fixo[y][x] = True

    def padroes(self) -> None:
        n = self.n
        for i in range(n):
            self.por(6, i, i % 2 == 0)
            self.por(i, 6, i % 2 == 0)
        for cx, cy in ((3, 3), (n - 4, 3), (3, n - 4)):
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    x, y = cx + dx, cy + dy
                    if 0 <= x < n and 0 <= y < n:
                        self.por(x, y, max(abs(dx), abs(dy)) not in (2, 4))
        pos = _ALINHAMENTO[self.v]
        ultimo = len(pos) - 1
        for i, a in enumerate(pos):
            for j, b in enumerate(pos):
                if (i, j) in ((0, 0), (0, ultimo), (ultimo, 0)):
                    continue
                for dy in range(-2, 3):
                    for dx in range(-2, 3):
                        self.por(a + dx, b + dy, max(abs(dx), abs(dy)) != 1)
        self.formato(0)
        if self.v >= 7:
            resto = self.v
            for _ in range(12):
                resto = (resto << 1) ^ ((resto >> 11) * 0x1F25)
            bits = self.v << 12 | resto
            for i in range(18):
                bit = (bits >> i) & 1 == 1
                a, b = n - 11 + i % 3, i // 3
                self.por(a, b, bit)
                self.por(b, a, bit)

    def formato(self, mascara: int) -> None:
        dado = 0b00 << 3 | mascara  # nível M = 00
        resto = dado
        for _ in range(10):
            resto = (resto << 1) ^ ((resto >> 9) * 0x537)
        bits = (dado << 10 | resto) ^ 0x5412
        bit = lambda i: (bits >> i) & 1 == 1
        n = self.n
        for i in range(6):
            self.por(8, i, bit(i))
        self.por(8, 7, bit(6))
        self.por(8, 8, bit(7))
        self.por(7, 8, bit(8))
        for i in range(9, 15):
            self.por(14 - i, 8, bit(i))
        for i in range(8):
            self.por(n - 1 - i, 8, bit(i))
        for i in range(8, 15):
            self.por(8, n - 15 + i, bit(i))
        self.por(8, n - 8, True)

    def dados(self, cw: list) -> None:
        n, i, total = self.n, 0, len(cw) * 8
        direita = n - 1
        while direita >= 1:
            if direita == 6:
                direita = 5
            for vert in range(n):
                for j in range(2):
                    x = direita - j
                    subindo = ((direita + 1) & 2) == 0
                    y = n - 1 - vert if subindo else vert
                    if not self.fixo[y][x] and i < total:
                        self.mod[y][x] = (cw[i >> 3] >> (7 - (i & 7))) & 1 == 1
                        i += 1
            direita -= 2

    def mascarar(self, m: int) -> None:
        f = [lambda x, y: (x + y) % 2 == 0, lambda x, y: y % 2 == 0, lambda x, y: x % 3 == 0,
             lambda x, y: (x + y) % 3 == 0, lambda x, y: (x // 3 + y // 2) % 2 == 0,
             lambda x, y: x * y % 2 + x * y % 3 == 0, lambda x, y: (x * y % 2 + x * y % 3) % 2 == 0,
             lambda x, y: ((x + y) % 2 + x * y % 3) % 2 == 0][m]
        for y in range(self.n):
            for x in range(self.n):
                if not self.fixo[y][x] and f(x, y):
                    self.mod[y][x] = not self.mod[y][x]

    def penalidade(self) -> int:
        n, m, p = self.n, self.mod, 0
        linhas = [m[y] for y in range(n)] + [[m[y][x] for y in range(n)] for x in range(n)]
        padrao_a = [True, False, True, True, True, False, True, False, False, False, False]
        padrao_b = padrao_a[::-1]
        for linha in linhas:
            corrida, cor = 0, None
            for v in linha + [None]:
                if v == cor:
                    corrida += 1
                else:
                    if corrida >= 5:
                        p += 3 + corrida - 5
                    corrida, cor = 1, v
            for i in range(n - 10):
                trecho = linha[i:i + 11]
                if trecho == padrao_a or trecho == padrao_b:
                    p += 40
        for y in range(n - 1):
            for x in range(n - 1):
                if m[y][x] == m[y][x + 1] == m[y + 1][x] == m[y + 1][x + 1]:
                    p += 3
        escuros = sum(map(sum, m))
        k = abs(escuros * 20 - n * n * 10) // (n * n)
        return p + k * 10


def gerar(texto: str) -> list:
    """Matriz de booleanos (True = escuro)."""
    dados = texto.encode("utf-8")
    versao = next((v for v in range(1, 11)
                   if 4 + (8 if v < 10 else 16) + 8 * len(dados) <= 8 * sum(n * k for n, k in _BLOCOS_M[v][1])),
                  None)
    if versao is None:
        raise ValueError("texto grande demais para o QR")
    cw = _codewords(dados, versao)
    melhor = None
    for mascara in range(8):
        m = _Matriz(versao)
        m.padroes()
        m.dados(cw)
        m.mascarar(mascara)
        m.formato(mascara)
        pen = m.penalidade()
        if melhor is None or pen < melhor[0]:
            melhor = (pen, m)
    return melhor[1].mod


def svg(texto: str, cor: str = "#1b1f24", fundo: str = "#ffffff", margem: int = 4) -> str:
    mod = gerar(texto)
    n = len(mod)
    t = n + 2 * margem
    caminho = "".join(f"M{x + margem},{y + margem}h1v1h-1z" for y in range(n) for x in range(n) if mod[y][x])
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {t} {t}" shape-rendering="crispEdges">'
            f'<rect width="{t}" height="{t}" fill="{fundo}"/><path d="{caminho}" fill="{cor}"/></svg>')
