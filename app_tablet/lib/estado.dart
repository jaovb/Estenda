import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Um computador salvo no app.
class PcSalvo {
  PcSalvo({required this.nome, required this.host, this.porta = 24860, this.aparelhoId, this.aparelhoToken});

  String nome;
  String host;
  int porta;
  String? aparelhoId; // depois da primeira entrada com senha, o PC dá uma chave própria a este tablet
  String? aparelhoToken;

  String get chave => '$host:$porta';
  String get hostUrl => host.contains(':') ? '[$host]' : host; // IPv6 vai entre colchetes
  bool get lembrado => aparelhoId != null && aparelhoToken != null;

  Map<String, dynamic> toJson() =>
      {'nome': nome, 'host': host, 'porta': porta, 'aparelhoId': aparelhoId, 'aparelhoToken': aparelhoToken};

  factory PcSalvo.fromJson(Map<String, dynamic> j) => PcSalvo(
        nome: '${j['nome'] ?? j['host']}',
        host: '${j['host']}',
        porta: (j['porta'] as num?)?.toInt() ?? 24860,
        aparelhoId: j['aparelhoId'] as String?,
        aparelhoToken: j['aparelhoToken'] as String?,
      );
}

/// Preferências e computadores salvos, guardados no próprio tablet.
class Estado extends ChangeNotifier {
  SharedPreferences? _p;
  ThemeMode tema = ThemeMode.system;
  List<PcSalvo> pcs = [];
  String? atual;
  String modoToque = 'toque'; // touchpad | toque
  String qualidade = 'equilibrada'; // nitida | equilibrada | leve
  int fps = 30;
  double velocidade = 1.2;
  Map<String, int> uso = {}; // dia (aaaa-mm-dd) -> segundos usando o app conectado

  static String _dia(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Segundos de uso nos últimos 7 dias (hoje incluído).
  int get usoSemana {
    final hoje = DateTime.now();
    var total = 0;
    for (var i = 0; i < 7; i++) {
      total += uso[_dia(hoje.subtract(Duration(days: i)))] ?? 0;
    }
    return total;
  }

  void somarUso(int segundos) {
    if (segundos <= 0) return;
    mudar(() {
      final hoje = _dia(DateTime.now());
      uso[hoje] = (uso[hoje] ?? 0) + segundos;
      final limite = _dia(DateTime.now().subtract(const Duration(days: 14)));
      uso.removeWhere((dia, _) => dia.compareTo(limite) < 0);
    });
  }

  PcSalvo? get pcAtual {
    for (final p in pcs) {
      if (p.chave == atual) return p;
    }
    return pcs.isEmpty ? null : pcs.first;
  }

  Future<void> carregar() async {
    final p = _p = await SharedPreferences.getInstance();
    tema = ThemeMode.values.firstWhere((t) => t.name == p.getString('tema'), orElse: () => ThemeMode.system);
    atual = p.getString('atual');
    modoToque = p.getString('modoToque') ?? modoToque;
    qualidade = p.getString('qualidade') ?? qualidade;
    fps = p.getInt('fps') ?? fps;
    velocidade = p.getDouble('velocidade') ?? velocidade;
    try {
      uso = Map<String, int>.from(jsonDecode(p.getString('uso') ?? '{}') as Map);
    } catch (_) {
      uso = {};
    }
    try {
      final lista = jsonDecode(p.getString('pcs') ?? '[]') as List;
      pcs = lista.map((e) => PcSalvo.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      pcs = [];
    }
  }

  void _salvar() {
    final p = _p;
    if (p == null) return;
    p.setString('tema', tema.name);
    if (atual != null) p.setString('atual', atual!);
    p.setString('modoToque', modoToque);
    p.setString('qualidade', qualidade);
    p.setInt('fps', fps);
    p.setDouble('velocidade', velocidade);
    p.setString('pcs', jsonEncode(pcs.map((e) => e.toJson()).toList()));
    p.setString('uso', jsonEncode(uso));
  }

  void mudar(VoidCallback f) {
    f();
    _salvar();
    notifyListeners();
  }

  void definirTema(ThemeMode t) => mudar(() => tema = t);

  PcSalvo adicionarPc(String nome, String host, int porta) {
    final chave = '$host:$porta';
    for (final p in pcs) {
      if (p.chave == chave) {
        mudar(() {
          if (nome.isNotEmpty) p.nome = nome;
          atual = chave;
        });
        return p;
      }
    }
    final novo = PcSalvo(nome: nome.isEmpty ? host : nome, host: host, porta: porta);
    mudar(() {
      pcs.add(novo);
      atual = chave;
    });
    return novo;
  }

  void removerPc(PcSalvo pc) => mudar(() {
        pcs.remove(pc);
        if (atual == pc.chave) atual = pcs.isEmpty ? null : pcs.first.chave;
      });

  void escolherPc(PcSalvo pc) => mudar(() => atual = pc.chave);

  void renomearPc(PcSalvo pc, String nome) {
    if (pc.nome != nome && nome.isNotEmpty) mudar(() => pc.nome = nome);
  }

  void guardarAparelho(PcSalvo pc, String id, String token) => mudar(() {
        pc.aparelhoId = id;
        pc.aparelhoToken = token;
      });

  void esquecerAparelho(PcSalvo pc) => mudar(() {
        pc.aparelhoId = null;
        pc.aparelhoToken = null;
      });
}

/// Dá acesso ao Estado em qualquer lugar da árvore de widgets.
class EstadoScope extends InheritedNotifier<Estado> {
  const EstadoScope({super.key, required Estado estado, required super.child}) : super(notifier: estado);

  /// Com dependência: o widget é redesenhado quando o estado muda.
  static Estado of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<EstadoScope>()!.notifier!;

  /// Sem dependência: para usar em callbacks.
  static Estado ler(BuildContext context) => context.getInheritedWidgetOfExactType<EstadoScope>()!.notifier!;
}
