import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// Entrega, só dentro do próprio tablet (127.0.0.1), a tela remota que vem embutida no app.
/// Assim a tela abre na hora, funciona de longe mesmo sem o PC alcançável pela rede de casa, e o
/// endereço é sempre o mesmo (o WebView guarda as preferências por endereço).
class ServidorLocal {
  ServidorLocal._();
  static HttpServer? _srv;
  static const porta = 24862;

  static const _tipos = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'png': 'image/png',
    'webmanifest': 'application/manifest+json',
  };

  /// Endereço da tela remota (sobe o servidor na primeira vez).
  static Future<String> endereco() async {
    _srv ??= await _subir();
    return 'http://127.0.0.1:${_srv!.port}/remoto.html';
  }

  static Future<HttpServer> _subir() async {
    HttpServer s;
    try {
      s = await HttpServer.bind(InternetAddress.loopbackIPv4, porta);
    } on SocketException {
      s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0); // porta ocupada: qualquer outra
    }
    s.listen((req) async {
      final r = req.response;
      try {
        var nome = req.uri.path.replaceFirst(RegExp(r'^/+'), '');
        if (nome.isEmpty) nome = 'remoto.html';
        if (nome.contains('..') || req.method != 'GET') {
          r.statusCode = HttpStatus.notFound;
        } else {
          final dados = await rootBundle.load('assets/web/$nome');
          r.headers.set('Content-Type', _tipos[nome.split('.').last] ?? 'application/octet-stream');
          r.headers.set('Cache-Control', 'no-store');
          r.add(dados.buffer.asUint8List(dados.offsetInBytes, dados.lengthInBytes));
        }
      } catch (_) {
        r.statusCode = HttpStatus.notFound;
      }
      await r.close();
    });
    return s;
  }
}
