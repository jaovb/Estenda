import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'estado.dart';

/// Em que pé está a conexão com o PC.
enum Fase { conectando, senha, entrando, aberta, reconectando, encerrada }

class Monitor {
  Monitor.de(Map m)
      : i = (m['i'] as num).toInt(),
        w = (m['w'] as num).toInt(),
        h = (m['h'] as num).toInt(),
        principal = m['principal'] == true,
        nome = '${m['nome']}';
  final int i, w, h;
  final bool principal;
  final String nome;
}

class CursorRemoto {
  double x = 0, y = 0;
  String forma = 'seta';
  bool visivel = false;
}

String normalizarSenha(String s) => s.replaceAll(RegExp(r'\s+'), '').replaceAll('-', '').toLowerCase();

String nomeAparelho() {
  final views = ui.PlatformDispatcher.instance.views;
  if (views.isEmpty) return 'App Ponte Remota';
  final v = views.first;
  final lado = v.physicalSize.shortestSide / v.devicePixelRatio;
  final tipo = lado >= 600 ? 'Tablet' : 'Celular';
  return Platform.isIOS ? (lado >= 600 ? 'iPad (app)' : 'iPhone (app)') : '$tipo Android (app)';
}

/// Conversa com o Ponte Remota do PC: o mesmo protocolo da página do tablet (remoto.html).
/// - login: o PC manda um número (nonce) e o app devolve HMAC-SHA256 dele com a senha ou a chave do aparelho;
/// - imagem: quadros binários com pedaços JPEG, aplicados em ordem e confirmados ("a");
/// - entradas: m (mover), b (botão), w (roda), k (tecla), txt (texto), atalho.
class Conexao extends ChangeNotifier {
  Conexao({required this.app, required this.pc, required this.segundoMonitor});

  final Estado app;
  final PcSalvo pc;
  final bool segundoMonitor;

  Fase fase = Fase.conectando;
  String? erro;
  String? motivoFim;
  String nomePc = '';
  List<Monitor> monitores = [];
  int monitor = 0;
  bool energiaPermitida = true;
  String via = '';
  bool semSegundoMonitor = false;

  /// A tela do PC: uma imagem base e, por cima, os pedaços que mudaram depois dela (em ordem).
  /// De tempos em tempos os pedaços são "achatados" na base. Não usamos Picture.toImageSync a cada
  /// quadro: no Impeller (Android) ela às vezes devolve imagem transparente e a tela "some".
  ui.Image? quadro;
  final List<(int, int, ui.Image)> camadas = [];
  bool _achatando = false;
  int fbW = 0, fbH = 0;
  final cursor = CursorRemoto();
  int cursorLocalAte = 0; // ms: até quando vale a posição prevista no tablet (touchpad)
  double? rtt;
  int fps = 0, kbps = 0;
  String? avisoTela; // "segura" (bloqueio/UAC) ou "falhou"
  String? energiaAcao;
  DateTime? energiaFim;

  /// Redesenhar a tela remota (quadro novo, cursor) sem reconstruir os widgets.
  final tique = ValueNotifier<int>(0);
  final _avisos = StreamController<String>.broadcast();
  final _clip = StreamController<Map<String, dynamic>>.broadcast();
  Stream<String> get avisos => _avisos.stream;
  Stream<Map<String, dynamic>> get clip => _clip.stream;

  final relogio = Stopwatch()..start();
  WebSocket? _ws;
  Uint8List? _nonce;
  bool _nonceUsado = true;
  String? _senha;
  bool _lembrar = true;
  bool _fechado = false;
  bool _ativo = false;
  bool _negadoAgora = false;
  int _tentativas = 0;
  Timer? _timer, _ping, _stats, _mov;
  Future<void> _cadeia = Future.value();
  int _bytes = 0, _quadros = 0;
  Map<String, dynamic>? _movPendente;

  bool get ativa => _ativo;
  Monitor? get mon => monitor < monitores.length ? monitores[monitor] : null;
  double get monW => (mon?.w ?? (fbW == 0 ? 1920 : fbW)).toDouble();
  double get monH => (mon?.h ?? (fbH == 0 ? 1080 : fbH)).toDouble();

  void iniciar() {
    _stats = Timer.periodic(const Duration(seconds: 1), (_) {
      fps = _quadros;
      kbps = _bytes ~/ 1024;
      _quadros = 0;
      _bytes = 0;
      if (!_fechado) notifyListeners();
    });
    _conectar();
  }

  void _notificar() {
    if (!_fechado) notifyListeners();
  }

  Future<void> _conectar() async {
    if (_fechado) return;
    _timer?.cancel();
    _nonce = null;
    _nonceUsado = true;
    if (fase != Fase.reconectando && fase != Fase.senha) fase = Fase.conectando;
    _notificar();
    try {
      final ws = await WebSocket.connect('ws://${pc.hostUrl}:${pc.porta}/ws').timeout(const Duration(seconds: 6));
      if (_fechado) {
        ws.close();
        return;
      }
      _ws = ws;
      ws.pingInterval = const Duration(seconds: 10);
      ws.listen(_receber, onDone: () => _caiu(ws), onError: (_) => _caiu(ws), cancelOnError: true);
    } catch (_) {
      if (fase != Fase.senha) {
        erro = 'Não encontrei ${pc.nome}. O acesso está ligado no Ponte Remota do PC?';
      }
      _agendar();
    }
  }

  void _agendar() {
    if (_fechado) return;
    final s = math.min(10, 1 << math.min(_tentativas++, 3));
    _timer?.cancel();
    _timer = Timer(Duration(seconds: s), _conectar);
    _notificar();
  }

  void _caiu(WebSocket ws) {
    if (!identical(ws, _ws)) return;
    _ws = null;
    _ping?.cancel();
    final estava = _ativo;
    _ativo = false;
    if (_fechado) return;
    if (motivoFim != null) {
      fase = Fase.encerrada;
      _notificar();
      return;
    }
    if (_negadoAgora) {
      _negadoAgora = false;
      _timer = Timer(const Duration(milliseconds: 400), _conectar);
      return;
    }
    if (estava || fase == Fase.reconectando || fase == Fase.aberta) fase = Fase.reconectando;
    _agendar();
  }

  void _receber(dynamic d) {
    if (d is String) {
      Map<String, dynamic> m;
      try {
        m = Map<String, dynamic>.from(jsonDecode(d) as Map);
      } catch (_) {
        return;
      }
      _mensagem(m);
    } else if (d is List<int>) {
      _quadro(d is Uint8List ? d : Uint8List.fromList(d));
    }
  }

  void _mensagem(Map<String, dynamic> m) {
    if (_fechado) return;
    switch (m['t']) {
      case 'ola':
        nomePc = '${m['pc']}';
        _nonce = base64Decode('${m['nonce']}');
        _nonceUsado = false;
        app.renomearPc(pc, nomePc);
        _tentarEntrar();
      case 'bem_vindo':
        _entrou(m);
      case 'negado':
        _negado(m);
      case 'c':
        cursor.forma = '${m['f']}';
        cursor.visivel = m['v'] == true;
        final localAinda = app.modoToque == 'touchpad' && relogio.elapsedMilliseconds < cursorLocalAte;
        if (!localAinda) {
          cursor.x = (m['x'] as num).toDouble();
          cursor.y = (m['y'] as num).toDouble();
        }
        tique.value++;
      case 'pong':
        final ts = m['ts'];
        if (ts is num) {
          final r = relogio.elapsedMilliseconds - ts.toDouble();
          rtt = rtt == null ? r : rtt! * 0.7 + r * 0.3;
        }
      case 'monitores':
        monitores = (m['monitores'] as List).map((e) => Monitor.de(e as Map)).toList();
        monitor = (m['monitor'] as num?)?.toInt() ?? 0;
        _avisos.add('Os monitores do PC mudaram.');
        _notificar();
      case 'aviso':
        avisoTela = m['tipo'] as String?;
        _notificar();
      case 'energia':
        final acao = m['acao'] as String?;
        if (acao == null) {
          energiaAcao = null;
          _avisos.add('Cancelado.');
        } else if (acao == 'bloquear' || acao == 'suspender') {
          energiaAcao = null;
          _avisos.add(acao == 'bloquear' ? 'Bloqueando o PC…' : 'Suspendendo o PC…');
        } else {
          energiaAcao = acao;
          energiaFim = DateTime.now().add(Duration(seconds: (m['em'] as num?)?.toInt() ?? 0));
        }
        _notificar();
      case 'energia_negada':
        _avisos.add('Desligar e reiniciar estão desativados no PC.');
      case 'clip':
      case 'clip_ok':
        _clip.add(m);
      case 'tchau':
        motivoFim = '${m['motivo'] ?? 'O PC encerrou a sessão.'}';
    }
  }

  void _tentarEntrar() {
    final nonce = _nonce;
    if (nonce == null || _nonceUsado || _fechado) return;
    Map<String, dynamic> campos;
    String chave;
    if (pc.lembrado) {
      campos = {'modo': 'aparelho', 'id': pc.aparelhoId};
      chave = pc.aparelhoToken!;
    } else if (_senha != null) {
      campos = {'modo': 'senha', 'lembrar': _lembrar};
      chave = normalizarSenha(_senha!);
    } else {
      fase = Fase.senha;
      _notificar();
      return;
    }
    _nonceUsado = true;
    final mac = Hmac(sha256, utf8.encode(chave)).convert(nonce).toString();
    if (fase != Fase.reconectando) fase = Fase.entrando;
    _notificar();
    _cru({'t': 'auth', 'nome': nomeAparelho(), ...campos, 'mac': mac});
  }

  /// Chamado pela tela de senha.
  void entrarComSenha(String senha, bool lembrar) {
    _senha = senha;
    _lembrar = lembrar;
    erro = null;
    fase = Fase.entrando;
    _notificar();
    if (_ws != null && _nonce != null && !_nonceUsado) {
      _tentarEntrar();
    } else if (_ws == null) {
      _timer?.cancel();
      _conectar();
    }
  }

  void _entrou(Map<String, dynamic> m) {
    _ativo = true;
    _tentativas = 0;
    erro = null;
    final ap = m['aparelho'];
    if (ap is Map) app.guardarAparelho(pc, '${ap['id']}', '${ap['token']}');
    monitores = ((m['monitores'] as List?) ?? []).map((e) => Monitor.de(e as Map)).toList();
    monitor = (m['monitor'] as num?)?.toInt() ?? 0;
    energiaPermitida = m['energia'] == true;
    via = '${m['via'] ?? ''}';
    if (segundoMonitor) {
      final i = monitores.indexWhere((x) => !x.principal);
      semSegundoMonitor = i < 0;
      if (i >= 0 && i != monitor) {
        monitor = i;
        enviar({'t': 'mon', 'i': i});
      }
    }
    fase = Fase.aberta;
    enviar({'t': 'cfg', 'qualidade': app.qualidade, 'fps': app.fps});
    _ping?.cancel();
    void ping() => enviar({'t': 'ping', 'ts': relogio.elapsedMilliseconds, 'rtt': rtt?.round()});
    ping();
    _ping = Timer.periodic(const Duration(seconds: 2), (_) => ping());
    _notificar();
  }

  void _negado(Map<String, dynamic> m) {
    _negadoAgora = true;
    switch (m['motivo']) {
      case 'aparelho':
        app.esquecerAparelho(pc);
        erro = 'Este tablet foi esquecido no PC. Entre com a senha.';
      case 'bloqueado':
        _senha = null;
        erro = 'Muitas tentativas erradas. Espere ${m['espera'] ?? 30} s e tente de novo.';
      default:
        _senha = null;
        erro = 'Senha errada. Confira no PC (maiúsculas, espaços e hífens não importam).';
    }
    fase = Fase.senha;
    _notificar();
  }

  /// Usa a tela principal mesmo no modo segundo monitor (quando o PC não tem um).
  void usarTelaPrincipal() {
    semSegundoMonitor = false;
    _notificar();
  }

  void trocarMonitor(int i) {
    if (i == monitor || i < 0 || i >= monitores.length) return;
    monitor = i;
    enviar({'t': 'mon', 'i': i});
    _notificar();
  }

  void reconectarAgora() {
    motivoFim = null;
    fase = Fase.reconectando;
    _tentativas = 0;
    _conectar();
  }

  // ------------------------------------------------------------ imagem

  static Future<ui.Image> _decodificar(Uint8List jpeg) async {
    final codec = await ui.instantiateImageCodec(jpeg);
    final f = await codec.getNextFrame();
    codec.dispose();
    return f.image;
  }

  void _quadro(Uint8List b) {
    _bytes += b.length;
    if (b.length < 12 || b[0] != 1) return;
    final bd = ByteData.sublistView(b);
    final w = bd.getUint16(2, Endian.little);
    final h = bd.getUint16(4, Endian.little);
    final id = bd.getUint32(6, Endian.little);
    final n = bd.getUint16(10, Endian.little);
    var o = 12;
    final pedacos = <(int, int, Future<ui.Image>)>[];
    try {
      for (var i = 0; i < n; i++) {
        final x = bd.getUint16(o, Endian.little);
        final y = bd.getUint16(o + 2, Endian.little);
        final tam = bd.getUint32(o + 8, Endian.little);
        o += 12;
        pedacos.add((x, y, _decodificar(Uint8List.sublistView(b, o, o + tam))));
        o += tam;
      }
    } catch (_) {
      enviar({'t': 'a', 'id': id});
      enviar({'t': 'completo'});
      return;
    }
    // decodifica em paralelo, mas aplica na ordem de chegada
    _cadeia = _cadeia.then((_) => _aplicar(id, w, h, pedacos)).catchError((Object _) {}); // um erro não trava os próximos
  }

  Future<void> _aplicar(int id, int w, int h, List<(int, int, Future<ui.Image>)> pedacos) async {
    var ok = true;
    final imgs = <(int, int, ui.Image)>[];
    for (final p in pedacos) {
      try {
        imgs.add((p.$1, p.$2, await p.$3));
      } catch (_) {
        ok = false;
      }
    }
    if (_fechado) {
      for (final i in imgs) {
        i.$3.dispose();
      }
      return;
    }
    try {
      final base = quadro;
      final cobreTudo = imgs.any((i) => i.$1 == 0 && i.$2 == 0 && i.$3.width >= w && i.$3.height >= h);
      if (cobreTudo) {
        // quadro inteiro: vira a base nova, sem precisar montar nada
        final inteiro = imgs.lastWhere((i) => i.$1 == 0 && i.$2 == 0 && i.$3.width >= w && i.$3.height >= h);
        final depois = imgs.sublist(imgs.indexOf(inteiro) + 1);
        for (final i in imgs.sublist(0, imgs.indexOf(inteiro))) {
          i.$3.dispose();
        }
        _limparCamadas();
        quadro = inteiro.$3;
        base?.dispose();
        camadas.addAll(depois);
      } else if (base == null || base.width != w || base.height != h) {
        // pedaços sem uma base do mesmo tamanho: guarda, mas pede a tela inteira
        if (base != null) {
          _limparCamadas();
        }
        camadas.addAll(imgs);
        ok = false;
      } else {
        camadas.addAll(imgs);
      }
      fbW = w;
      fbH = h;
      _quadros++;
      if (camadas.length > 24 && !_achatando) _achatar(w, h);
    } catch (_) {
      ok = false;
    }
    enviar({'t': 'a', 'id': id});
    if (!ok) enviar({'t': 'completo'});
    tique.value++;
  }

  void _limparCamadas() {
    for (final c in camadas) {
      c.$3.dispose();
    }
    camadas.clear();
  }

  /// Junta a base e as camadas atuais numa imagem só (assíncrono, sem travar a tela).
  Future<void> _achatar(int w, int h) async {
    final base = quadro;
    if (base == null) return;
    _achatando = true;
    final n = camadas.length;
    final usadas = camadas.sublist(0, n);
    ui.Image? nova;
    try {
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      final tinta = ui.Paint();
      c.drawImage(base, ui.Offset.zero, tinta);
      for (final i in usadas) {
        c.drawImage(i.$3, ui.Offset(i.$1.toDouble(), i.$2.toDouble()), tinta);
      }
      final pic = rec.endRecording();
      nova = await pic.toImage(w, h);
      pic.dispose();
    } catch (_) {
      nova = null;
    }
    _achatando = false;
    // só troca se nada mudou a base nesse meio-tempo (um quadro inteiro, por exemplo)
    if (nova == null || _fechado || !identical(quadro, base) || camadas.length < n ||
        !identical(camadas[n - 1].$3, usadas[n - 1].$3)) {
      nova?.dispose();
      return;
    }
    quadro = nova;
    camadas.removeRange(0, n);
    base.dispose();
    for (final i in usadas) {
      i.$3.dispose();
    }
    tique.value++;
  }

  // ------------------------------------------------------------ envio

  void enviar(Map<String, dynamic> m) {
    if (_ativo) _cru(m);
  }

  void _cru(Map<String, dynamic> m) {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) ws.add(jsonEncode(m));
  }

  /// Movimentos chegam a 120 por segundo: junta e manda no máximo a cada 12 ms.
  void mover(double x, double y) {
    _movPendente = {'t': 'm', 'x': x.round(), 'y': y.round()};
    _mov ??= Timer(const Duration(milliseconds: 12), _soltarMov);
  }

  void _soltarMov() {
    _mov = null;
    final m = _movPendente;
    _movPendente = null;
    if (m != null) enviar(m);
  }

  void botao(int b, bool desce, double x, double y) {
    _mov?.cancel();
    _mov = null;
    _movPendente = null;
    enviar({'t': 'b', 'b': b, 'd': desce, 'x': x.round(), 'y': y.round()});
  }

  void clique(int b, double x, double y) {
    botao(b, true, x, y);
    botao(b, false, x, y);
  }

  void roda(int dy, int dx) {
    if (dy != 0 || dx != 0) enviar({'t': 'w', 'dy': dy, 'dx': dx});
  }

  void tecla(int vk, bool desce, {bool estendida = false}) => enviar({'t': 'k', 'vk': vk, 'd': desce, 'e': estendida});
  void atalho(List<int> vks) => enviar({'t': 'atalho', 'vks': vks});
  void texto(String s) {
    if (s.isNotEmpty) enviar({'t': 'txt', 's': s});
  }

  void fechar() {
    if (_fechado) return;
    _fechado = true;
    _timer?.cancel();
    _ping?.cancel();
    _stats?.cancel();
    _mov?.cancel();
    _ws?.close(1000);
    _ws = null;
  }

  @override
  void dispose() {
    fechar();
    quadro?.dispose();
    quadro = null;
    _limparCamadas();
    _avisos.close();
    _clip.close();
    tique.dispose();
    super.dispose();
  }
}
