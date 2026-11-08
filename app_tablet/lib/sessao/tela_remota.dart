import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../conexao.dart';
import '../tema.dart';

/// Zoom e posição da imagem do PC na tela do tablet. Tudo em "pixels do monitor do PC".
class Vista extends ChangeNotifier {
  double z = 1, k0 = 1, k = 1, ox = 0, oy = 0;
  Size tam = Size.zero;
  double w = 0, h = 0;

  /// Chamado no layout: tamanho da área e do monitor. Mantém o centro ao girar o tablet.
  void definir(Size s, double mw, double mh) {
    if (s == tam && mw == w && mh == h) return;
    final trocouMonitor = mw != w || mh != h;
    final centro = (tam == Size.zero || trocouMonitor || k == 0)
        ? Offset(mw / 2, mh / 2)
        : Offset((tam.width / 2 - ox) / k, (tam.height / 2 - oy) / k);
    if (trocouMonitor) z = 1;
    tam = s;
    w = mw;
    h = mh;
    k0 = math.min(s.width / mw, s.height / mh);
    k = k0 * z;
    ox = s.width / 2 - centro.dx * k;
    oy = s.height / 2 - centro.dy * k;
    _limitar();
  }

  void _limitar() {
    final lw = w * k, lh = h * k;
    ox = lw <= tam.width ? (tam.width - lw) / 2 : ox.clamp(tam.width - lw, 0.0).toDouble();
    oy = lh <= tam.height ? (tam.height - lh) / 2 : oy.clamp(tam.height - lh, 0.0).toDouble();
  }

  Offset paraMonitor(Offset p) => Offset(((p.dx - ox) / k).clamp(0.0, w - 1).toDouble(), ((p.dy - oy) / k).clamp(0.0, h - 1).toDouble());
  Offset paraTela(double x, double y) => Offset(ox + x * k, oy + y * k);

  void zoomEm(double nz, Offset centro) {
    final mx = (centro.dx - ox) / k, my = (centro.dy - oy) / k;
    z = nz.clamp(1.0, 6.0).toDouble();
    k = k0 * z;
    ox = centro.dx - mx * k;
    oy = centro.dy - my * k;
    _limitar();
    notifyListeners();
  }

  void arrastar(Offset d) {
    ox += d.dx;
    oy += d.dy;
    _limitar();
    notifyListeners();
  }

  /// Com zoom, a vista acompanha o cursor.
  void seguir(double x, double y) {
    if (z <= 1.001) return;
    final p = paraTela(x, y);
    const m = 70.0;
    if (p.dx < m) ox += m - p.dx;
    if (p.dx > tam.width - m) ox -= p.dx - (tam.width - m);
    if (p.dy < m) oy += m - p.dy;
    if (p.dy > tam.height - m) oy -= p.dy - (tam.height - m);
    _limitar();
    notifyListeners();
  }

  void reiniciar() {
    z = 1;
    k = k0;
    ox = tam.width / 2 - w / 2 * k;
    oy = tam.height / 2 - h / 2 * k;
    _limitar();
    notifyListeners();
  }
}

/// A tela do PC, com os gestos. Toque direto no modo segundo monitor ou se escolhido.
class TelaRemota extends StatefulWidget {
  const TelaRemota({
    super.key,
    required this.con,
    required this.vista,
    required this.direto,
    required this.velocidade,
    required this.aoTresDedos,
    required this.aoTocar,
  });

  final Conexao con;
  final Vista vista;
  final bool direto;
  final double velocidade;
  final VoidCallback aoTresDedos;
  final VoidCallback aoTocar;

  @override
  State<TelaRemota> createState() => _TelaRemotaState();
}

class _Gesto {
  _Gesto(this.n, this.t0);
  final int n; // 1, 2, 3 dedos; 0 = sobra de um gesto já resolvido
  final int t0;
  Offset ini = Offset.zero, ult = Offset.zero;
  int ultT = 0;
  bool moveu = false, arrastando = false, consumido = false, direto = false, trouxe = false;
  Timer? timer;
  Offset c0 = Offset.zero, ca = Offset.zero;
  double d0 = 0, da = 0;
  String? modo; // rolar | zoom
  double rolX = 0, rolY = 0;
  final hist = <(int, Offset)>[];
}

class _TelaRemotaState extends State<TelaRemota> {
  static const _kRolagem = 2.4; // 1 px de dedo ≈ 1 px de conteúdo (120 = 3 linhas no Windows)
  final _dedos = <int, Offset>{};
  _Gesto? _g;
  int _inercia = 0;
  final Set<int> _botoesMouse = {};

  Conexao get con => widget.con;
  Vista get v => widget.vista;
  int get _agora => con.relogio.elapsedMilliseconds;

  Offset _centro() {
    var x = 0.0, y = 0.0;
    for (final d in _dedos.values) {
      x += d.dx;
      y += d.dy;
    }
    return Offset(x / _dedos.length, y / _dedos.length);
  }

  double _distancia() {
    if (_dedos.length < 2) return 0;
    final l = _dedos.values.toList();
    return (l[0] - l[1]).distance;
  }

  void _posicionar(Offset p) {
    con.cursor.x = p.dx;
    con.cursor.y = p.dy;
    con.cursor.visivel = true;
    con.cursorLocalAte = _agora + 300;
    con.tique.value++;
  }

  void _rolar(_Gesto g, Offset d) {
    g.rolX += d.dx * _kRolagem;
    g.rolY += d.dy * _kRolagem;
    final iy = g.rolY.truncate(), ix = g.rolX.truncate();
    if (iy != 0 || ix != 0) {
      con.roda(iy, -ix);
      g.rolY -= iy;
      g.rolX -= ix;
    }
  }

  /// Continua rolando um pouco depois de soltar, como no celular.
  void _soltarInercia(double vx, double vy) {
    if (math.sqrt(vx * vx + vy * vy) < 0.35) return;
    final meu = ++_inercia;
    var ax = 0.0, ay = 0.0;
    Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (meu != _inercia || !mounted) {
        t.cancel();
        return;
      }
      final f = math.pow(0.004, 16 / 1000).toDouble();
      vx *= f;
      vy *= f;
      ay += vy * 16 * _kRolagem;
      ax += vx * 16 * _kRolagem;
      final iy = ay.truncate(), ix = ax.truncate();
      if (iy != 0 || ix != 0) {
        con.roda(iy, -ix);
        ay -= iy;
        ax -= ix;
      }
      if (math.sqrt(vx * vx + vy * vy) < 0.04) t.cancel();
    });
  }

  // ------------------------------------------------------------ um dedo

  void _inicioUm(PointerDownEvent e) {
    final g = _Gesto(1, _agora)
      ..ini = e.localPosition
      ..ult = e.localPosition
      ..ultT = _agora
      ..direto = widget.direto || e.kind == PointerDeviceKind.stylus;
    _g = g;
    g.timer = Timer(Duration(milliseconds: g.direto ? 520 : 420), () {
      if (_g != g || g.moveu) return;
      if (g.direto) {
        final p = v.paraMonitor(g.ini);
        _posicionar(p);
        con.clique(2, p.dx, p.dy);
        g.consumido = true;
      } else {
        g.arrastando = true;
        con.botao(0, true, con.cursor.x, con.cursor.y);
      }
      HapticFeedback.mediumImpact();
    });
  }

  void _moverUm(_Gesto g, Offset d) {
    final dist = (d - g.ini).distance;
    if (g.direto) {
      if (!g.moveu && dist > 9) {
        g.moveu = true;
        g.timer?.cancel();
        if (!g.consumido) {
          final p0 = v.paraMonitor(g.ini);
          _posicionar(p0);
          con.botao(0, true, p0.dx, p0.dy);
          g.arrastando = true;
        }
      }
      if (g.arrastando) {
        final p = v.paraMonitor(d);
        _posicionar(p);
        con.mover(p.dx, p.dy);
      }
    } else {
      if (!g.moveu && dist > 3) {
        g.moveu = true;
        if (!g.arrastando) g.timer?.cancel();
      }
      if (g.moveu) {
        if (!con.cursor.visivel && !g.trouxe) {
          con.cursor.x = v.w / 2;
          con.cursor.y = v.h / 2;
          g.trouxe = true;
        }
        final t = _agora;
        final delta = d - g.ult;
        final dt = math.max(1, t - g.ultT);
        final vel = delta.distance / dt;
        final ganho = widget.velocidade * (1 + 1.6 * ((vel - 0.25) / 1.4).clamp(0.0, 1.0).toDouble()) / v.k;
        con.cursor.x = (con.cursor.x + delta.dx * ganho).clamp(0.0, v.w - 1).toDouble();
        con.cursor.y = (con.cursor.y + delta.dy * ganho).clamp(0.0, v.h - 1).toDouble();
        con.cursor.visivel = true;
        con.cursorLocalAte = t + 300;
        v.seguir(con.cursor.x, con.cursor.y);
        con.mover(con.cursor.x, con.cursor.y);
        con.tique.value++;
        g.ultT = t;
      }
    }
    g.ult = d;
  }

  void _fimUm(_Gesto g) {
    g.timer?.cancel();
    final rapido = _agora - g.t0 < 320;
    final perto = (g.ult - g.ini).distance < 12;
    if (g.arrastando) {
      final p = g.direto ? v.paraMonitor(g.ult) : Offset(con.cursor.x, con.cursor.y);
      con.botao(0, false, p.dx, p.dy);
    } else if (!g.consumido && rapido && perto) {
      if (g.direto) {
        final p = v.paraMonitor(g.ini);
        _posicionar(p);
        con.clique(0, p.dx, p.dy);
      } else {
        con.clique(0, con.cursor.x, con.cursor.y);
      }
    }
  }

  // ------------------------------------------------------------ dois dedos

  void _inicioDois() {
    final g0 = _g;
    if (g0 != null && g0.n == 1) {
      g0.timer?.cancel();
      if (g0.arrastando) con.botao(0, false, con.cursor.x, con.cursor.y);
    }
    final c = _centro(), d = _distancia();
    _g = _Gesto(2, _agora)
      ..c0 = c
      ..ca = c
      ..d0 = d
      ..da = d;
  }

  void _moverDois(_Gesto g) {
    final c = _centro(), d = _distancia();
    if (g.modo == null) {
      if ((d - g.d0).abs() > 30) {
        g.modo = 'zoom';
      } else if ((c - g.c0).distance > 10) {
        g.modo = 'rolar';
      }
    }
    if (g.modo == 'rolar') {
      _rolar(g, c - g.ca);
      final t = _agora;
      g.hist.add((t, c));
      while (g.hist.length > 2 && t - g.hist.first.$1 > 90) {
        g.hist.removeAt(0);
      }
    } else if (g.modo == 'zoom' && g.da > 0) {
      v.zoomEm(v.z * d / g.da, c);
      v.arrastar(c - g.ca);
    }
    g.ca = c;
    g.da = d;
  }

  void _fimDois(_Gesto g) {
    if (g.modo == null && _agora - g.t0 < 300) {
      if (widget.direto) {
        final p = v.paraMonitor(g.c0);
        _posicionar(p);
        con.clique(2, p.dx, p.dy);
      } else {
        con.clique(2, con.cursor.x, con.cursor.y);
      }
    } else if (g.modo == 'rolar' && g.hist.length >= 2) {
      final a = g.hist.first, b = g.hist.last;
      final dt = b.$1 - a.$1;
      if (dt > 0 && _agora - b.$1 < 60) _soltarInercia((b.$2.dx - a.$2.dx) / dt, (b.$2.dy - a.$2.dy) / dt);
    } else if (g.modo == 'zoom' && v.z < 1.06) {
      v.reiniciar();
    }
  }

  // ------------------------------------------------------------ eventos

  void _baixou(PointerDownEvent e) {
    widget.aoTocar();
    if (e.kind == PointerDeviceKind.mouse) {
      final p = v.paraMonitor(e.localPosition);
      _posicionar(p);
      final b = e.buttons & kSecondaryMouseButton != 0 ? 2 : (e.buttons & kMiddleMouseButton != 0 ? 1 : 0);
      _botoesMouse.add(b);
      con.botao(b, true, p.dx, p.dy);
      return;
    }
    _inercia++;
    _dedos[e.pointer] = e.localPosition;
    if (_dedos.length == 1) {
      _inicioUm(e);
    } else if (_dedos.length == 2) {
      _inicioDois();
    } else if (_dedos.length == 3) {
      final g = _g;
      if (g != null && g.n == 2 && g.modo != null) return;
      _g = _Gesto(3, _agora)..c0 = _centro();
    }
  }

  void _moveu(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.mouse) {
      final p = v.paraMonitor(e.localPosition);
      _posicionar(p);
      con.mover(p.dx, p.dy);
      return;
    }
    if (!_dedos.containsKey(e.pointer)) return;
    _dedos[e.pointer] = e.localPosition;
    final g = _g;
    if (g == null) return;
    if (g.n == 1 && _dedos.length == 1) {
      _moverUm(g, e.localPosition);
    } else if (g.n == 2 && _dedos.length == 2) {
      _moverDois(g);
    } else if (g.n == 3 && (_centro() - g.c0).distance > 14) {
      g.moveu = true;
    }
  }

  void _subiu(PointerEvent e) {
    if (e.kind == PointerDeviceKind.mouse) {
      final p = v.paraMonitor(e.localPosition);
      for (final b in _botoesMouse) {
        con.botao(b, false, p.dx, p.dy);
      }
      _botoesMouse.clear();
      return;
    }
    if (_dedos.remove(e.pointer) == null) return;
    final g = _g;
    if (g != null) {
      if (g.n == 1 && _dedos.isEmpty) {
        _fimUm(g);
        _g = null;
      } else if (g.n == 2 && _dedos.length == 1) {
        _fimDois(g);
        _g = _Gesto(0, _agora);
      } else if (g.n == 3 && _dedos.length == 2) {
        if (!g.moveu && _agora - g.t0 < 350) widget.aoTresDedos();
        _g = _Gesto(0, _agora);
      }
    }
    if (_dedos.isEmpty) _g = null;
  }

  void _hover(PointerHoverEvent e) {
    if (e.kind != PointerDeviceKind.mouse) return;
    final p = v.paraMonitor(e.localPosition);
    _posicionar(p);
    con.mover(p.dx, p.dy);
  }

  void _sinal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      con.roda((-e.scrollDelta.dy * 1.2).round(), (e.scrollDelta.dx * 1.2).round());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Cores.of(context);
    return LayoutBuilder(builder: (context, caixa) {
      v.definir(caixa.biggest, con.monW, con.monH);
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _baixou,
        onPointerMove: _moveu,
        onPointerUp: _subiu,
        onPointerCancel: _subiu,
        onPointerHover: _hover,
        onPointerSignal: _sinal,
        // a imagem base vai num RawImage (o jeito padrão do Flutter de mostrar imagens); os pedaços
        // que mudaram e o cursor vão por cima. Tudo é reconstruído a cada quadro.
        child: ListenableBuilder(
          listenable: Listenable.merge([con.tique, v]),
          builder: (context, _) {
            v.definir(caixa.biggest, con.monW, con.monH);
            final dst = Rect.fromLTWH(v.ox, v.oy, v.w * v.k, v.h * v.k);
            final img = con.quadro;
            return Stack(children: [
              Positioned.fill(child: ColoredBox(color: c.tela)),
              if (img != null)
                Positioned.fromRect(
                  rect: dst,
                  child: RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                ),
              Positioned.fill(child: CustomPaint(painter: _Pintor(con, v, con.tique.value))),
            ]);
          },
        ),
      );
    });
  }
}

class _Pintor extends CustomPainter {
  _Pintor(this.con, this.v, this.geracao);
  final Conexao con;
  final Vista v;
  final int geracao;

  @override
  void paint(Canvas canvas, Size s) {
    con.diagPinturas++;
    final dst = Rect.fromLTWH(v.ox, v.oy, v.w * v.k, v.h * v.k);
    con.diagPintura = '${s.width.round()}×${s.height.round()} → ${dst.left.round()},${dst.top.round()} '
        '${dst.width.round()}×${dst.height.round()}';
    try {
      final fw = (con.fbW > 0 ? con.fbW : (con.quadro?.width ?? 1)).toDouble();
      final fh = (con.fbH > 0 ? con.fbH : (con.quadro?.height ?? 1)).toDouble();
      if (con.camadas.isNotEmpty) {
        final tinta = Paint()..filterQuality = FilterQuality.medium;
        canvas.save();
        canvas.clipRect(dst);
        canvas.translate(dst.left, dst.top);
        canvas.scale(dst.width / fw, dst.height / fh);
        for (final c in con.camadas) {
          canvas.drawImage(c.$3, Offset(c.$1.toDouble(), c.$2.toDouble()), tinta);
        }
        canvas.restore();
      }
      if (con.cursor.visivel) {
        final p = v.paraTela(con.cursor.x, con.cursor.y);
        desenharCursor(canvas, p, con.cursor.forma, (v.k * 1.3).clamp(0.85, 1.6).toDouble());
      }
    } catch (e) {
      con.diagErro = 'pintura: $e'.split('\n').first;
    }
  }

  @override
  bool shouldRepaint(_Pintor old) => true;
}

/// O cursor do Windows, desenhado no tablet (a captura da tela não inclui o cursor).
void desenharCursor(Canvas canvas, Offset p, String forma, double esc) {
  canvas.save();
  canvas.translate(p.dx.roundToDouble(), p.dy.roundToDouble());
  canvas.scale(esc);
  final preto = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final branco = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  void contorno(Path path, double larg) {
    canvas.drawPath(path, preto..strokeWidth = larg + 2.2);
    canvas.drawPath(path, branco..strokeWidth = larg);
  }

  final dupla = Path()
    ..moveTo(-9, 0)
    ..lineTo(9, 0)
    ..moveTo(-9, 0)
    ..lineTo(-5.4, -3.6)
    ..moveTo(-9, 0)
    ..lineTo(-5.4, 3.6)
    ..moveTo(9, 0)
    ..lineTo(5.4, -3.6)
    ..moveTo(9, 0)
    ..lineTo(5.4, 3.6);
  switch (forma) {
    case 'texto':
      contorno(
          Path()
            ..moveTo(-3.5, -9.5)
            ..lineTo(3.5, -9.5)
            ..moveTo(-3.5, 9.5)
            ..lineTo(3.5, 9.5)
            ..moveTo(0, -9.5)
            ..lineTo(0, 9.5),
          1.4);
    case 'we':
    case 'ns':
    case 'nwse':
    case 'nesw':
      canvas.rotate({'we': 0.0, 'ns': math.pi / 2, 'nwse': math.pi / 4, 'nesw': -math.pi / 4}[forma]!);
      contorno(dupla, 1.6);
    case 'mover':
      contorno(dupla, 1.6);
      canvas.rotate(math.pi / 2);
      contorno(dupla, 1.6);
    case 'cruz':
      contorno(
          Path()
            ..moveTo(-9, 0)
            ..lineTo(9, 0)
            ..moveTo(0, -9)
            ..lineTo(0, 9),
          1.4);
    case 'proibido':
      contorno(
          Path()
            ..addOval(Rect.fromCircle(center: Offset.zero, radius: 8))
            ..moveTo(-5.6, 5.6)
            ..lineTo(5.6, -5.6),
          2);
    case 'espera':
      contorno(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 8)), 2.4);
      canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: 8), -math.pi / 2, math.pi * 0.8, false,
          Paint()
            ..color = Pastel.menta
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4);
    default:
      // seta (e "mão": a seta basta para apontar)
      final seta = Path()
        ..moveTo(0, 0)
        ..lineTo(0, 15.5)
        ..lineTo(4.2, 11.5)
        ..lineTo(7.1, 18.1)
        ..lineTo(9.7, 17.0)
        ..lineTo(6.8, 10.5)
        ..lineTo(12.5, 10.5)
        ..close();
      canvas.drawPath(seta, Paint()..color = Colors.white);
      canvas.drawPath(seta, preto..strokeWidth = 1.2);
      if (forma == 'mao' || forma == 'progresso') {
        canvas.drawCircle(const Offset(15, 16), 3.2, Paint()..color = Pastel.menta);
      }
  }
  canvas.restore();
}
