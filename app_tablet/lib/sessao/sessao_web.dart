import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../estado.dart';
import '../servidor_local.dart';
import '../tema.dart';

/// Tela remota. A imagem, os gestos e o teclado ficam numa página que vem embutida no app
/// (assets/web), a mesma que já funcionava no navegador. Ela fala com o PC:
///   - em casa: direto pelo Wi-Fi (WebSocket);
///   - de longe: WebRTC direto, com o aperto de mão pelos pontos de encontro (cifrado).
/// O app passa a ela qual PC usar e guarda o que ela devolve (a chave deste tablet e o segredo de longe).
class SessaoWebPagina extends StatefulWidget {
  const SessaoWebPagina({
    super.key,
    required this.app,
    required this.pc,
    required this.segundoMonitor,
    this.senhaTeste,
    this.soTeste,
  });
  final Estado app;
  final PcSalvo pc;
  final bool segundoMonitor;
  final String? senhaTeste; // só nos testes automáticos
  final String? soTeste; // "casa" ou "longe": só nos testes automáticos

  @override
  State<SessaoWebPagina> createState() => _SessaoWebPaginaState();
}

class _SessaoWebPaginaState extends State<SessaoWebPagina> {
  final _web = WebViewController();
  bool _carregou = false;
  String? _erro;
  final _desde = DateTime.now();
  Timer? _vigia;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _web
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1A1A2E))
      ..addJavaScriptChannel('EstendaApp', onMessageReceived: (m) => _recado(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _carregou = true);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == false || !mounted) return;
          setState(() => _erro = 'A tela remota não abriu (${e.description}).');
        },
        onNavigationRequest: (r) =>
            r.url.startsWith('http://127.0.0.1:') ? NavigationDecision.navigate : NavigationDecision.prevent,
      ));
    _abrir();
  }

  Future<void> _abrir() async {
    try {
      final base = await ServidorLocal.endereco();
      await _web.loadRequest(Uri.parse('$base#${_parametros()}'));
    } catch (e) {
      if (mounted) setState(() => _erro = 'A tela remota não abriu ($e).');
    }
  }

  String _parametros() {
    final pc = widget.pc, app = widget.app;
    final claro = app.tema == ThemeMode.light ||
        (app.tema == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.light);
    final p = <String, String>{
      'app': '1',
      'pc': '${pc.hostUrl}:${pc.porta}',
      'modo': widget.segundoMonitor ? 'segundo' : 'espelho',
      'tema': claro ? 'light' : 'dark',
      'toque': app.modoToque,
      'q': app.qualidade,
      'fps': '${app.fps}',
      'vel': app.velocidade.toStringAsFixed(1),
      if (pc.aparelhoId != null && pc.aparelhoToken != null) 'api': pc.aparelhoId!,
      if (pc.aparelhoId != null && pc.aparelhoToken != null) 'apt': pc.aparelhoToken!,
      if (pc.pcId != null) 'pcid': pc.pcId!,
      if (pc.deLonge) 'ls': pc.longeSegredo!,
      if (pc.deLonge && pc.longeEncontros.isNotEmpty) 'le': pc.longeEncontros.join(','),
      if (widget.senhaTeste != null) 'senha': widget.senhaTeste!,
      if (widget.soTeste != null) 'so': widget.soTeste!,
    };
    return p.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
  }

  /// O que a página conta ao app.
  void _recado(String texto) {
    Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(texto) as Map);
    } catch (_) {
      return;
    }
    final pc = widget.pc, app = widget.app;
    switch (m['t']) {
      case 'aparelho':
        app.mudar(() {
          pc.aparelhoId = '${m['id']}';
          pc.aparelhoToken = '${m['token']}';
        });
      case 'longe':
        app.mudar(() {
          final s = m['s'];
          pc.longeSegredo = s is String && s.isNotEmpty ? s : null;
          if (m['e'] is List) pc.longeEncontros = (m['e'] as List).map((e) => '$e').toList();
          if (m['pcid'] is String) pc.pcId = m['pcid'] as String;
        });
      case 'pc':
        final nome = '${m['nome'] ?? ''}';
        if (nome.isNotEmpty && pc.nome == pc.host) app.mudar(() => pc.nome = nome);
      case 'esquecido':
        app.esquecerAparelho(pc);
      case 'sair':
        if (mounted) Navigator.of(context).maybePop();
      case 'estado':
        // aparece no logcat: os testes automáticos no emulador leem esta linha
        debugPrint('ESTENDA_ESTADO $texto');
      case 'erro':
        debugPrint('ESTENDA_ERRO ${m['m']}');
    }
  }

  @override
  void dispose() {
    _vigia?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    final s = DateTime.now().difference(_desde).inSeconds;
    final app = widget.app;
    Future.microtask(() => app.somarUso(s)); // "Uso na semana" da tela inicial
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Cores.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Positioned.fill(child: WebViewWidget(controller: _web)),
        if (!_carregou && _erro == null)
          const Positioned.fill(
            child: ColoredBox(color: Color(0xFF1A1A2E), child: Center(child: CircularProgressIndicator())),
          ),
        if (_erro != null)
          Positioned.fill(
            child: ColoredBox(
              color: c.fundo,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.error_outline_rounded, size: 44, color: c.tinta(Pastel.pessego)),
                    const SizedBox(height: 14),
                    Text(_erro!, textAlign: TextAlign.center, style: TextStyle(color: c.texto, fontSize: 16)),
                    const SizedBox(height: 20),
                    TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Voltar')),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
