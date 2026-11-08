import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PcAchado {
  PcAchado(this.nome, this.host, this.porta);
  final String nome, host;
  final int porta;
}

/// Pergunta na rede "tem algum Ponte Remota aí?" (UDP 24861) e junta as respostas.
Future<List<PcAchado>> procurarPcs({Duration tempo = const Duration(milliseconds: 1800)}) async {
  final achados = <String, PcAchado>{};
  RawDatagramSocket? s;
  try {
    s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    s.broadcastEnabled = true;
    final socket = s;
    socket.listen((ev) {
      if (ev != RawSocketEvent.read) return;
      final d = socket.receive();
      if (d == null) return;
      try {
        final j = jsonDecode(utf8.decode(d.data)) as Map;
        if (j['ponte'] != null) {
          achados[d.address.address] =
              PcAchado('${j['pc']}', d.address.address, (j['porta'] as num?)?.toInt() ?? 24860);
        }
      } catch (_) {}
    });
    final msg = utf8.encode('PONTE-REMOTA?');
    for (var i = 0; i < 3; i++) {
      socket.send(msg, InternetAddress('255.255.255.255'), 24861);
      await Future.delayed(Duration(milliseconds: tempo.inMilliseconds ~/ 3));
    }
  } catch (_) {
    // sem Wi-Fi ou rede que bloqueia broadcast: volta o que achou
  } finally {
    s?.close();
  }
  return achados.values.toList();
}
