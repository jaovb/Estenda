import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../estado.dart';
import '../tema.dart';

/// Tela remota usando, por dentro do app, o mesmo motor da versão do navegador (que já
/// funciona no tablet). O app continua cuidando de achar o PC, guardar os PCs e o modo.
class SessaoWebPagina extends StatefulWidget {
  const SessaoWebPagina({super.key, required this.app, required this.pc, required this.segundoMonitor});
  final Estado app;
  final PcSalvo pc;
  final bool segundoMonitor;

  @override
  State<SessaoWebPagina> createState() => _SessaoWebPaginaState();
}

class _SessaoWebPaginaState extends State<SessaoWebPagina> {
  late final WebViewController _web;
  bool _carregando = true;
  String? _erro;
  final _desde = DateTime.now();

  String get _endereco {
    final pc = widget.pc;
    final partes = <String>['modo=${widget.segundoMonitor ? 'segundo' : 'espelho'}'];
    if (pc.aparelhoId != null && pc.aparelhoToken != null) {
      partes.add('api=${Uri.encodeComponent(pc.aparelhoId!)}');
      partes.add('apt=${Uri.encodeComponent(pc.aparelhoToken!)}');
    }
    return 'http://${pc.hostUrl}:${pc.porta}/#${partes.join('&')}';
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF121222))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _carregando = false);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == false) return;
          if (mounted) {
            setState(() {
              _carregando = false;
              _erro = 'Não consegui abrir o ${widget.pc.nome}. Confira se o Estenda está aberto no PC, '
                  'com o acesso ligado, e se o tablet está no mesmo Wi-Fi.';
            });
          }
        },
        // links de fora (se houver) não abrem dentro da tela remota
        onNavigationRequest: (r) {
          final u = Uri.tryParse(r.url);
          final mesmoPc = u != null && u.host == Uri.parse(_endereco).host && u.port == widget.pc.porta;
          return mesmoPc ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(_endereco));
  }

  void _tentarDeNovo() {
    setState(() {
      _erro = null;
      _carregando = true;
    });
    _web.loadRequest(Uri.parse(_endereco));
  }

  @override
  void dispose() {
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
      backgroundColor: const Color(0xFF121222),
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Positioned.fill(child: WebViewWidget(controller: _web)),
        if (_carregando && _erro == null)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xFF121222),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (_erro != null)
          Positioned.fill(
            child: ColoredBox(
              color: c.fundo,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wifi_off_rounded, size: 44, color: c.tinta(Pastel.pessego)),
                      const SizedBox(height: 14),
                      Text(_erro!, textAlign: TextAlign.center, style: TextStyle(color: c.texto, fontSize: 16)),
                      const SizedBox(height: 20),
                      Wrap(spacing: 10, children: [
                        FilledButton(onPressed: _tentarDeNovo, child: const Text('Tentar de novo')),
                        TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Voltar')),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
