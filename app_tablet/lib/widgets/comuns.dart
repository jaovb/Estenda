import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema.dart';

/// Qualquer coisa tocável que afunda um pouco ao apertar e sobe a sombra ao passar o mouse.
class Pressionavel extends StatefulWidget {
  const Pressionavel({
    super.key,
    required this.child,
    required this.onTap,
    this.raio = 24,
    this.cor,
    this.borda,
    this.sombra = true,
    this.escala = 0.965,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double raio;
  final Color? cor;
  final Color? borda;
  final bool sombra;
  final double escala;

  @override
  State<Pressionavel> createState() => _PressionavelState();
}

class _PressionavelState extends State<Pressionavel> {
  bool _apertado = false;
  bool _sobre = false;

  @override
  Widget build(BuildContext context) {
    final c = Cores.of(context);
    final raio = BorderRadius.circular(widget.raio);
    return MouseRegion(
      onEnter: (_) => setState(() => _sobre = true),
      onExit: (_) => setState(() => _sobre = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _apertado = true),
        onTapCancel: () => setState(() => _apertado = false),
        onTapUp: (_) => setState(() => _apertado = false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _apertado ? widget.escala : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: widget.cor ?? c.cartao,
              borderRadius: raio,
              border: Border.all(color: widget.borda ?? c.borda, width: 1),
              boxShadow: widget.sombra ? sombraSuave(c, forca: _apertado ? 0.5 : (_sobre ? 1.5 : 1)) : null,
            ),
            child: ClipRRect(borderRadius: raio, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Opções lado a lado com um destaque que desliza até a escolhida.
class Segmentado<T> extends StatelessWidget {
  const Segmentado({super.key, required this.opcoes, required this.valor, required this.aoEscolher, this.cor});

  final List<(T, String)> opcoes;
  final T valor;
  final ValueChanged<T> aoEscolher;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = Cores.of(context);
    final destaque = cor ?? Pastel.lavanda;
    final i = math.max(0, opcoes.indexWhere((o) => o.$1 == valor));
    return LayoutBuilder(builder: (context, caixa) {
      return Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: c.cartao2, borderRadius: BorderRadius.circular(16)),
        child: Stack(children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment(opcoes.length == 1 ? 0.0 : -1.0 + 2.0 * i / (opcoes.length - 1), 0.0),
            child: FractionallySizedBox(
              widthFactor: 1 / opcoes.length,
              heightFactor: 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                decoration: BoxDecoration(
                  color: c.preenchimento(destaque),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: sombraSuave(c, forca: 0.35),
                ),
              ),
            ),
          ),
          Row(children: [
            for (final o in opcoes)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    aoEscolher(o.$1);
                  },
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: o.$1 == valor ? FontWeight.w700 : FontWeight.w500,
                        color: o.$1 == valor ? c.tinta(destaque) : c.suave,
                      ),
                      child: Text(o.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      );
    });
  }
}

/// Fundo com manchas pastel que flutuam devagar (calmo, sem chamar atenção).
class FundoPastel extends StatefulWidget {
  const FundoPastel({super.key, required this.child});
  final Widget child;

  @override
  State<FundoPastel> createState() => _FundoPastelState();
}

class _FundoPastelState extends State<FundoPastel> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(seconds: 24))
    ..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Cores.of(context);
    return Stack(children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: CustomPaint(painter: _Manchas(_a, c)),
        ),
      ),
      widget.child,
    ]);
  }
}

class _Manchas extends CustomPainter {
  _Manchas(this.a, this.c) : super(repaint: a);
  final Animation<double> a;
  final Cores c;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = c.fundo);
    final t = a.value * 2 * math.pi;
    final forca = c.escuro ? 0.16 : 0.42;
    final manchas = [
      (Pastel.lavanda, 0.15 + 0.05 * math.sin(t), 0.12 + 0.04 * math.cos(t), 0.55),
      (Pastel.menta, 0.88 + 0.04 * math.cos(t * 1.3), 0.30 + 0.05 * math.sin(t), 0.45),
      (Pastel.azul, 0.70 + 0.05 * math.sin(t * 0.8), 0.92 + 0.03 * math.cos(t), 0.55),
      (Pastel.pessego, 0.12 + 0.04 * math.cos(t * 0.7), 0.85 + 0.04 * math.sin(t * 1.1), 0.40),
    ];
    for (final m in manchas) {
      final centro = Offset(m.$2 * s.width, m.$3 * s.height);
      final r = m.$4 * s.shortestSide;
      final p = Paint()
        ..shader = RadialGradient(colors: [alfa(m.$1, forca), alfa(m.$1, 0)])
            .createShader(Rect.fromCircle(center: centro, radius: r));
      canvas.drawCircle(centro, r, p);
    }
  }

  @override
  bool shouldRepaint(_Manchas old) => old.c != c;
}

/// Ícone do modo "Segundo Monitor": um monitor e o tablet ao lado, a área de trabalho continuando.
class IconeSegundoMonitor extends StatelessWidget {
  const IconeSegundoMonitor({super.key, required this.cor, this.tamanho = 96});
  final Color cor;
  final double tamanho;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(tamanho * 1.4, tamanho), painter: _IconeTelas(cor, espelho: false));
}

/// Ícone do modo "Espelhamento": duas telas iguais com setas de sincronia.
class IconeEspelho extends StatelessWidget {
  const IconeEspelho({super.key, required this.cor, this.tamanho = 96});
  final Color cor;
  final double tamanho;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(tamanho * 1.4, tamanho), painter: _IconeTelas(cor, espelho: true));
}

class _IconeTelas extends CustomPainter {
  _IconeTelas(this.cor, {required this.espelho});
  final Color cor;
  final bool espelho;

  @override
  void paint(Canvas canvas, Size s) {
    final u = s.height / 10;
    final traco = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.55
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cheio = Paint()..color = alfa(cor, 0.22);
    final linha = Paint()
      ..color = alfa(cor, 0.55)
      ..strokeWidth = u * 0.45
      ..strokeCap = StrokeCap.round;

    // monitor à esquerda
    final mon = RRect.fromRectAndRadius(Rect.fromLTWH(u * 0.5, u * 1.5, u * 7, u * 5), Radius.circular(u * 0.8));
    canvas.drawRRect(mon, cheio);
    canvas.drawRRect(mon, traco);
    canvas.drawLine(Offset(u * 4, u * 6.5), Offset(u * 4, u * 8), traco);
    canvas.drawLine(Offset(u * 2.6, u * 8.3), Offset(u * 5.4, u * 8.3), traco);
    // "janelas" dentro do monitor
    canvas.drawLine(Offset(u * 1.7, u * 3), Offset(u * 4.6, u * 3), linha);
    canvas.drawLine(Offset(u * 1.7, u * 4.2), Offset(u * 3.6, u * 4.2), linha);

    // tablet à direita
    final tab = RRect.fromRectAndRadius(Rect.fromLTWH(u * 8.4, u * 2.4, u * 5.2, u * 3.8), Radius.circular(u * 0.7));
    canvas.drawRRect(tab, cheio);
    canvas.drawRRect(tab, traco);

    if (espelho) {
      // as mesmas "janelas" no tablet + setas de sincronia
      canvas.drawLine(Offset(u * 9.4, u * 3.5), Offset(u * 11.5, u * 3.5), linha);
      canvas.drawLine(Offset(u * 9.4, u * 4.5), Offset(u * 10.8, u * 4.5), linha);
      final seta = Paint()
        ..color = cor
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.45
        ..strokeCap = StrokeCap.round;
      final centro = Offset(u * 11, u * 8.4);
      final r = u * 1.05;
      canvas.drawArc(Rect.fromCircle(center: centro, radius: r), -2.6, 2.2, false, seta);
      canvas.drawArc(Rect.fromCircle(center: centro, radius: r), 0.55, 2.2, false, seta);
      final p1 = centro + Offset(math.cos(-0.4) * r, math.sin(-0.4) * r);
      canvas.drawLine(p1, p1 + Offset(-u * 0.55, -u * 0.15), seta);
      canvas.drawLine(p1, p1 + Offset(u * 0.05, -u * 0.6), seta);
      final p2 = centro + Offset(math.cos(2.75) * r, math.sin(2.75) * r);
      canvas.drawLine(p2, p2 + Offset(u * 0.55, u * 0.15), seta);
      canvas.drawLine(p2, p2 + Offset(-u * 0.05, u * 0.6), seta);
    } else {
      // a janela "atravessa" do monitor para o tablet
      final jan = RRect.fromRectAndRadius(Rect.fromLTWH(u * 5.6, u * 3.3, u * 4.6, u * 2.2), Radius.circular(u * 0.4));
      canvas.drawRRect(jan, Paint()..color = alfa(cor, 0.45));
      canvas.drawRRect(jan, traco..strokeWidth = u * 0.4);
      // seta de "estender" embaixo
      final seta = Paint()
        ..color = cor
        ..strokeWidth = u * 0.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(u * 9, u * 8.3), Offset(u * 12.6, u * 8.3), seta);
      canvas.drawLine(Offset(u * 12.6, u * 8.3), Offset(u * 11.7, u * 7.5), seta);
      canvas.drawLine(Offset(u * 12.6, u * 8.3), Offset(u * 11.7, u * 9.1), seta);
    }
  }

  @override
  bool shouldRepaint(_IconeTelas old) => old.cor != cor || old.espelho != espelho;
}

/// Título de seção pequeno, em caixa alta.
class RotuloSecao extends StatelessWidget {
  const RotuloSecao(this.texto, {super.key});
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(texto.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w700, color: Cores.of(context).suave)),
      );
}

void mostrarAviso(BuildContext context, String texto) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(texto), duration: const Duration(seconds: 3)));
}
