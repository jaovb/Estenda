"""Escolhe o controle certo: o do Windows de verdade ou o simulado (para testes)."""
from __future__ import annotations

import sys

import comum

if comum.SIMULAR or sys.platform != "win32":
    import controle_sim as _b
    SIMULADO = True
else:
    import controle_win as _b
    SIMULADO = False

preparar_dpi = _b.preparar_dpi
tela_virtual = _b.tela_virtual
monitores = _b.monitores
area_de_trabalho = _b.area_de_trabalho
mover = _b.mover
botao = _b.botao
roda = _b.roda
tecla = _b.tecla
atalho = _b.atalho
texto = _b.texto
cursor = _b.cursor
area_ler = _b.area_ler
area_escrever = _b.area_escrever
energia = _b.energia
manter_acordado = _b.manter_acordado
iniciar_com_windows = _b.iniciar_com_windows
inicia_com_windows = _b.inicia_com_windows


def nomes_monitores(lista: list) -> list:
    """Lista enxuta para o tablet: Tela 1 (principal), Tela 2..."""
    return [{"i": i, "w": m["w"], "h": m["h"], "principal": m["principal"],
             "nome": f"Tela {i + 1}" + (" (principal)" if m["principal"] else "")}
            for i, m in enumerate(lista)]
