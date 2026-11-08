import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../conexao.dart';
import '../tema.dart';

/// Códigos de tecla do Windows (virtual-key) para as teclas que não são texto.
final Map<LogicalKeyboardKey, int> _vkEspeciais = {
  LogicalKeyboardKey.backspace: 0x08,
  LogicalKeyboardKey.tab: 0x09,
  LogicalKeyboardKey.enter: 0x0D,
  LogicalKeyboardKey.numpadEnter: 0x0D,
  LogicalKeyboardKey.shiftLeft: 0xA0,
  LogicalKeyboardKey.shiftRight: 0xA1,
  LogicalKeyboardKey.controlLeft: 0xA2,
  LogicalKeyboardKey.controlRight: 0xA3,
  LogicalKeyboardKey.altLeft: 0xA4,
  LogicalKeyboardKey.altRight: 0xA5,
  LogicalKeyboardKey.metaLeft: 0x5B,
  LogicalKeyboardKey.metaRight: 0x5C,
  LogicalKeyboardKey.capsLock: 0x14,
  LogicalKeyboardKey.escape: 0x1B,
  LogicalKeyboardKey.space: 0x20,
  LogicalKeyboardKey.pageUp: 0x21,
  LogicalKeyboardKey.pageDown: 0x22,
  LogicalKeyboardKey.end: 0x23,
  LogicalKeyboardKey.home: 0x24,
  LogicalKeyboardKey.arrowLeft: 0x25,
  LogicalKeyboardKey.arrowUp: 0x26,
  LogicalKeyboardKey.arrowRight: 0x27,
  LogicalKeyboardKey.arrowDown: 0x28,
  LogicalKeyboardKey.printScreen: 0x2C,
  LogicalKeyboardKey.insert: 0x2D,
  LogicalKeyboardKey.delete: 0x2E,
  LogicalKeyboardKey.contextMenu: 0x5D,
  LogicalKeyboardKey.numLock: 0x90,
  LogicalKeyboardKey.f1: 0x70,
  LogicalKeyboardKey.f2: 0x71,
  LogicalKeyboardKey.f3: 0x72,
  LogicalKeyboardKey.f4: 0x73,
  LogicalKeyboardKey.f5: 0x74,
  LogicalKeyboardKey.f6: 0x75,
  LogicalKeyboardKey.f7: 0x76,
  LogicalKeyboardKey.f8: 0x77,
  LogicalKeyboardKey.f9: 0x78,
  LogicalKeyboardKey.f10: 0x79,
  LogicalKeyboardKey.f11: 0x7A,
  LogicalKeyboardKey.f12: 0x7B,
};

/// VK de uma tecla física: as especiais pela tabela; letras e números pelo rótulo (A–Z, 0–9).
int? vkDaTecla(LogicalKeyboardKey k) {
  final v = _vkEspeciais[k];
  if (v != null) return v;
  final r = k.keyLabel.toUpperCase();
  if (r.length == 1 && RegExp(r'[A-Z0-9]').hasMatch(r)) return r.codeUnitAt(0);
  return null;
}

int vkDoCaractere(String ch) {
  final r = ch.toUpperCase();
  if (r.length == 1 && RegExp(r'[A-Z0-9]').hasMatch(r)) return r.codeUnitAt(0);
  if (ch == ' ') return 0x20;
  if (ch == '\n') return 0x0D;
  return 0;
}

/// Ctrl, Alt, Shift e Win "pegajosos": 1 toque = vale para a próxima tecla; 2 = travado (fica apertado no PC).
class Modificadores extends ChangeNotifier {
  Modificadores(this.con);
  final Conexao con;
  static const lista = [('Ctrl', 0x11), ('Alt', 0x12), ('Shift', 0x10), ('Win', 0x5B)];
  final Map<int, int> estado = {0x11: 0, 0x12: 0, 0x10: 0, 0x5B: 0};

  List<int> get umaVez => [for (final m in lista) if (estado[m.$2] == 1) m.$2];

  void alternar(int vk) {
    final antes = estado[vk] ?? 0;
    final depois = (antes + 1) % 3;
    estado[vk] = depois;
    if (depois == 2) con.tecla(vk, true);
    if (antes == 2) con.tecla(vk, false);
    notifyListeners();
  }

  void gastar() {
    var mudou = false;
    for (final vk in umaVez) {
      estado[vk] = 0;
      mudou = true;
    }
    if (mudou) notifyListeners();
  }

  void soltarTudo() {
    for (final m in lista) {
      if (estado[m.$2] == 2) con.tecla(m.$2, false);
      estado[m.$2] = 0;
    }
    notifyListeners();
  }

  /// Tecla especial (da barra ou da folha), levando os modificadores de "uma vez".
  void especial(int vk) {
    final ativos = umaVez;
    if (ativos.isNotEmpty) {
      con.atalho([...ativos, vk]);
      gastar();
    } else {
      con.tecla(vk, true);
      con.tecla(vk, false);
    }
  }

  /// Texto do teclado do tablet: com Ctrl/Alt/Win de "uma vez", vira atalho (Ctrl+C...).
  void escrever(int apagar, String inserir) {
    final ativos = umaVez;
    if (ativos.isNotEmpty && apagar == 0 && inserir.length == 1 && vkDoCaractere(inserir) != 0) {
      con.atalho([...ativos, vkDoCaractere(inserir)]);
      gastar();
      return;
    }
    con.texto('\b' * apagar + inserir);
  }
}

const teclasNavegacao = [
  ('Esc', 0x1B), ('Tab', 0x09), ('Enter', 0x0D), ('⌫', 0x08), ('←', 0x25), ('↑', 0x26), ('↓', 0x28), ('→', 0x27),
  ('Home', 0x24), ('End', 0x23), ('PgUp', 0x21), ('PgDn', 0x22), ('Ins', 0x2D), ('Del', 0x2E), ('PrtSc', 0x2C),
];
final teclasF = [for (var i = 0; i < 12; i++) ('F${i + 1}', 0x70 + i)];

/// Um botão de tecla. Não rouba o foco (senão o teclado do tablet fecharia).
class BotaoTecla extends StatelessWidget {
  const BotaoTecla({super.key, required this.rotulo, required this.aoTocar, this.nivel = 0, this.largura});
  final String rotulo;
  final VoidCallback aoTocar;
  final int nivel; // 0 normal, 1 "uma vez", 2 travado
  final double? largura;

  @override
  Widget build(BuildContext context) {
    final c = Cores.of(context);
    final destaque = Pastel.lavanda;
    final fundo = nivel == 2 ? c.tinta(destaque) : (nivel == 1 ? c.preenchimento(destaque) : c.cartao2);
    final cor = nivel == 2 ? c.cartao : (nivel == 1 ? c.tinta(destaque) : c.texto);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: fundo,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            aoTocar();
          },
          child: Container(
            constraints: BoxConstraints(minWidth: largura ?? 50, minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(rotulo, style: TextStyle(fontWeight: FontWeight.w600, color: cor, fontSize: 14)),
          ),
        ),
      ),
    );
  }
}

/// Barra que fica em cima do teclado do tablet.
class BarraTeclas extends StatelessWidget {
  const BarraTeclas({super.key, required this.mods, required this.aoFechar});
  final Modificadores mods;
  final VoidCallback aoFechar;

  @override
  Widget build(BuildContext context) {
    final c = Cores.of(context);
    return ListenableBuilder(
      listenable: mods,
      builder: (context, _) => Container(
        height: 56,
        decoration: BoxDecoration(color: c.cartao, border: Border(top: BorderSide(color: c.borda))),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          children: [
            for (final m in Modificadores.lista)
              BotaoTecla(rotulo: m.$1, nivel: mods.estado[m.$2] ?? 0, aoTocar: () => mods.alternar(m.$2)),
            const SizedBox(width: 8),
            for (final t in teclasNavegacao.where((t) => !['Ins', 'PrtSc', 'Enter'].contains(t.$1)))
              BotaoTecla(rotulo: t.$1, aoTocar: () => mods.especial(t.$2)),
            const SizedBox(width: 8),
            for (final t in teclasF) BotaoTecla(rotulo: t.$1, aoTocar: () => mods.especial(t.$2)),
            const SizedBox(width: 8),
            BotaoTecla(rotulo: '⌨ ✕', aoTocar: aoFechar),
          ],
        ),
      ),
    );
  }
}

/// Campo invisível que recebe o teclado do tablet. O teclado do Android quase não manda
/// teclas, só muda o texto: compara com o texto anterior e manda ao PC o que foi apagado
/// (Backspace) e o que foi escrito.
class CampoTeclado extends StatefulWidget {
  const CampoTeclado({super.key, required this.foco, required this.mods});
  final FocusNode foco;
  final Modificadores mods;

  @override
  State<CampoTeclado> createState() => _CampoTecladoState();
}

class _CampoTecladoState extends State<CampoTeclado> {
  static final _base = ' ' * 16;
  late final _ctrl = TextEditingController(text: _base);
  String _anterior = _base;

  void _zerar() {
    _anterior = _base;
    _ctrl.value = TextEditingValue(text: _base, selection: TextSelection.collapsed(offset: _base.length));
  }

  void _mudou(String atual) {
    var p = 0;
    final lim = atual.length < _anterior.length ? atual.length : _anterior.length;
    while (p < lim && atual.codeUnitAt(p) == _anterior.codeUnitAt(p)) {
      p++;
    }
    final apagar = _anterior.length - p;
    final inserir = atual.substring(p);
    _anterior = atual;
    if (apagar > 0 || inserir.isNotEmpty) widget.mods.escrever(apagar, inserir);
    final compondo = _ctrl.value.composing.isValid && !_ctrl.value.composing.isCollapsed;
    if (!compondo && (atual.length < 4 || atual.length > 300)) _zerar();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0,
      child: SizedBox(
        width: 2,
        height: 2,
        child: TextField(
          controller: _ctrl,
          focusNode: widget.foco,
          onChanged: _mudou,
          autocorrect: false,
          enableSuggestions: false,
          enableInteractiveSelection: false,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          maxLines: null,
          showCursor: false,
          style: const TextStyle(fontSize: 1, color: Colors.transparent),
          decoration: const InputDecoration(border: InputBorder.none, filled: false, isCollapsed: true),
        ),
      ),
    );
  }
}
