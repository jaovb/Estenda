import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../conexao.dart';
import '../estado.dart';
import '../tema.dart';
import '../widgets/comuns.dart';
import 'teclado.dart';

Widget _folha(BuildContext context, String titulo, String? sub, List<Widget> filhos) {
  return SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(titulo, style: Theme.of(context).textTheme.titleLarge),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(sub)),
          ...filhos,
        ]),
      ),
    ),
  );
}

Future<void> abrirFolha(BuildContext context, Widget Function(BuildContext) construtor) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: construtor,
    );

// ------------------------------------------------------------ teclas e atalhos

const _atalhos = [
  ('Copiar', [0x11, 0x43], 'Ctrl C'), ('Colar', [0x11, 0x56], 'Ctrl V'), ('Recortar', [0x11, 0x58], 'Ctrl X'),
  ('Desfazer', [0x11, 0x5A], 'Ctrl Z'), ('Refazer', [0x11, 0x59], 'Ctrl Y'), ('Selecionar tudo', [0x11, 0x41], 'Ctrl A'),
  ('Salvar', [0x11, 0x53], 'Ctrl S'), ('Procurar', [0x11, 0x46], 'Ctrl F'), ('Trocar de janela', [0x12, 0x09], 'Alt Tab'),
  ('Fechar janela', [0x12, 0x73], 'Alt F4'), ('Área de trabalho', [0x5B, 0x44], 'Win D'), ('Menu Iniciar', [0x5B], 'Win'),
  ('Explorador', [0x5B, 0x45], 'Win E'), ('Executar', [0x5B, 0x52], 'Win R'), ('Configurações', [0x5B, 0x49], 'Win I'),
  ('Recorte de tela', [0x5B, 0x10, 0x53], 'Win Shift S'), ('Gerenciador de tarefas', [0x11, 0x10, 0x1B], 'Ctrl Shift Esc'),
  ('Emojis', [0x5B, 0xBE], 'Win .'),
];

Widget folhaTeclas(BuildContext context, Conexao con, Modificadores mods) {
  final c = Cores.of(context);
  return ListenableBuilder(
    listenable: mods,
    builder: (context, _) => _folha(context, 'Teclas e atalhos',
        'Ctrl, Alt, Shift e Win: um toque vale para a próxima tecla; dois toques deixam apertada.', [
      const RotuloSecao('Modificadores'),
      Wrap(children: [
        for (final m in Modificadores.lista)
          BotaoTecla(rotulo: m.$1, largura: 72, nivel: mods.estado[m.$2] ?? 0, aoTocar: () => mods.alternar(m.$2)),
      ]),
      const RotuloSecao('Navegação'),
      Wrap(children: [for (final t in teclasNavegacao) BotaoTecla(rotulo: t.$1, largura: 64, aoTocar: () => mods.especial(t.$2))]),
      const RotuloSecao('Funções'),
      Wrap(children: [for (final t in teclasF) BotaoTecla(rotulo: t.$1, largura: 64, aoTocar: () => mods.especial(t.$2))]),
      const RotuloSecao('Atalhos do Windows'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in _atalhos)
          ActionChip(
            avatar: Icon(Icons.keyboard_command_key_rounded, size: 16, color: c.tinta(Pastel.lavanda)),
            label: Text('${a.$1}  ·  ${a.$3}'),
            backgroundColor: c.cartao2,
            side: BorderSide(color: c.borda),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onPressed: () {
              HapticFeedback.selectionClick();
              con.atalho(a.$2);
            },
          ),
      ]),
      const SizedBox(height: 10),
      const Text('Ctrl+Alt+Del não passa por nenhum programa; use Ctrl+Shift+Esc para o Gerenciador de Tarefas.'),
    ]),
  );
}

// ------------------------------------------------------------ copiar e colar

class FolhaCopiar extends StatefulWidget {
  const FolhaCopiar({super.key, required this.con});
  final Conexao con;
  @override
  State<FolhaCopiar> createState() => _FolhaCopiarState();
}

class _FolhaCopiarState extends State<FolhaCopiar> {
  final _txt = TextEditingController();
  String _status = '';
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.con.clip.listen((m) {
      if (!mounted) return;
      setState(() {
        if (m['t'] == 'clip') {
          _txt.text = '${m['s'] ?? ''}';
          _status = _txt.text.isEmpty ? 'A área de transferência do PC está vazia.' : 'Texto do PC carregado.';
        } else {
          _status = m['ok'] == true
              ? (m['colou'] == true ? 'Enviado e colado no PC.' : 'Enviado. No PC, é só colar.')
              : 'O PC não deixou mexer na área de transferência agora.';
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _txt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final con = widget.con;
    return _folha(context, 'Copiar e colar', 'Leve texto entre o tablet e a área de transferência do PC.', [
      const SizedBox(height: 14),
      TextField(controller: _txt, minLines: 4, maxLines: 8, decoration: const InputDecoration(hintText: 'Texto para mandar ao PC…')),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton.icon(
          onPressed: () {
            setState(() => _status = 'Pegando…');
            con.enviar({'t': 'clip_get'});
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('Pegar do PC'),
        ),
        OutlinedButton.icon(
          onPressed: () => con.enviar({'t': 'clip_set', 's': _txt.text}),
          icon: const Icon(Icons.upload_rounded),
          label: const Text('Enviar ao PC'),
        ),
        FilledButton.icon(
          onPressed: () => con.enviar({'t': 'clip_set', 's': _txt.text, 'colar': true}),
          icon: const Icon(Icons.content_paste_go_rounded),
          label: const Text('Enviar e colar'),
        ),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 4, children: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _txt.text));
            setState(() => _status = 'Copiado no tablet.');
          },
          child: const Text('Copiar no tablet'),
        ),
        TextButton(
          onPressed: () async {
            final d = await Clipboard.getData(Clipboard.kTextPlain);
            setState(() => _txt.text = d?.text ?? '');
          },
          child: const Text('Colar do tablet'),
        ),
      ]),
      if (_status.isNotEmpty) Text(_status),
    ]);
  }
}

// ------------------------------------------------------------ tela e qualidade

Widget folhaTela(BuildContext context, Conexao con, Estado est, VoidCallback ajustar) {
  return ListenableBuilder(
    listenable: Listenable.merge([con, est]),
    builder: (context, _) {
      final via = {'tailscale': 'via Tailscale', 'local': 'rede de casa', 'loopback': 'este PC'}[con.via] ?? con.via;
      final estat = [
        via,
        if (con.fbW > 0) '${con.fbW}×${con.fbH}',
        '${con.fps} fps',
        if (con.rtt != null) '${con.rtt!.round()} ms',
        '${con.kbps} kB/s',
      ].join(' · ');
      return _folha(context, 'Tela e qualidade', null, [
        if (con.monitores.length > 1) ...[
          const RotuloSecao('Monitor'),
          Segmentado<int>(
            opcoes: [for (final m in con.monitores) (m.i, '${m.nome.replaceAll(' (principal)', '')} · ${m.w}×${m.h}')],
            valor: con.monitor,
            cor: Pastel.azul,
            aoEscolher: con.trocarMonitor,
          ),
        ],
        const RotuloSecao('Qualidade'),
        Segmentado<String>(
          opcoes: const [('nitida', 'Nítida'), ('equilibrada', 'Equilibrada'), ('leve', 'Leve')],
          valor: est.qualidade,
          cor: Pastel.azul,
          aoEscolher: (q) {
            est.mudar(() => est.qualidade = q);
            con.enviar({'t': 'cfg', 'qualidade': q});
          },
        ),
        const RotuloSecao('Fluidez'),
        Segmentado<int>(
          opcoes: const [(15, '15 fps'), (30, '30 fps'), (60, '60 fps')],
          valor: est.fps,
          cor: Pastel.pessego,
          aoEscolher: (f) {
            est.mudar(() => est.fps = f);
            con.enviar({'t': 'cfg', 'fps': f});
          },
        ),
        const SizedBox(height: 16),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () {
              ajustar();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.fit_screen_rounded),
            label: const Text('Ajustar à tela'),
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Cores.of(context).cartao2, borderRadius: BorderRadius.circular(14)),
          child: Text(estat, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontSize: 13)),
        ),
      ]);
    },
  );
}

// ------------------------------------------------------------ energia

class FolhaEnergia extends StatefulWidget {
  const FolhaEnergia({super.key, required this.con});
  final Conexao con;
  @override
  State<FolhaEnergia> createState() => _FolhaEnergiaState();
}

class _FolhaEnergiaState extends State<FolhaEnergia> {
  String? _pedido;
  static const _opcoes = [
    ('bloquear', Icons.lock_outline_rounded, 'Bloquear', 'Volta à tela de senha. Daqui você perde o acesso até alguém entrar no PC.', Pastel.azul),
    ('suspender', Icons.bedtime_outlined, 'Suspender', 'Gasta pouca energia, mas daqui não dá para acordar o PC.', Pastel.lavanda),
    ('reiniciar', Icons.restart_alt_rounded, 'Reiniciar', 'Desliga e liga de novo. O acesso volta se o app iniciar com o Windows.', Pastel.menta),
    ('desligar', Icons.power_settings_new_rounded, 'Desligar', 'Desliga de vez. Para ligar de novo, só no PC.', Pastel.pessego),
  ];

  @override
  Widget build(BuildContext context) {
    final c = Cores.of(context);
    if (!widget.con.energiaPermitida) {
      return _folha(context, 'Energia do PC', 'Desligar e reiniciar pelo tablet estão desativados no PC (Ponte Remota → Opções).', []);
    }
    final escolhido = _opcoes.where((o) => o.$1 == _pedido).firstOrNull;
    return _folha(context, 'Energia do PC', 'Ligar o PC de longe ainda não dá: pense antes de desligar.', [
      const SizedBox(height: 14),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        child: escolhido == null
            ? Column(key: const ValueKey('lista'), children: [
                for (final o in _opcoes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Pressionavel(
                      onTap: () => setState(() => _pedido = o.$1),
                      raio: 20,
                      sombra: false,
                      cor: c.cartao2,
                      borda: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(color: c.preenchimento(o.$5), borderRadius: BorderRadius.circular(13)),
                            child: Icon(o.$2, color: c.tinta(o.$5)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(o.$3, style: Theme.of(context).textTheme.titleMedium),
                              Text(o.$4, style: TextStyle(color: c.suave, fontSize: 13)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ])
            : Container(
                key: const ValueKey('confirmar'),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: c.preenchimento(Pastel.pessego), borderRadius: BorderRadius.circular(20)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${escolhido.$3} o PC?', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(escolhido.$4),
                  const SizedBox(height: 14),
                  Row(children: [
                    FilledButton(
                      onPressed: () {
                        widget.con.enviar({'t': 'energia', 'acao': escolhido.$1});
                        Navigator.pop(context);
                      },
                      child: Text('Sim, ${escolhido.$3.toLowerCase()}'),
                    ),
                    const SizedBox(width: 10),
                    TextButton(onPressed: () => setState(() => _pedido = null), child: const Text('Cancelar')),
                  ]),
                ]),
              ),
      ),
    ]);
  }
}

// ------------------------------------------------------------ gestos

Widget folhaGestos(BuildContext context, bool segundo) {
  final linhas = segundo
      ? const [
          ('Clicar', 'toque onde quer'),
          ('Clique direito', 'segure até vibrar'),
          ('Arrastar janelas', 'arraste um dedo'),
          ('Rolar', 'arraste dois dedos'),
          ('Zoom', 'pinça'),
          ('Teclado', 'toque com três dedos'),
        ]
      : const [
          ('Mover o cursor', 'arraste um dedo (touchpad)'),
          ('Clicar', 'toque'),
          ('Clique direito', 'toque com dois dedos'),
          ('Arrastar', 'segure até vibrar e arraste'),
          ('Rolar', 'arraste dois dedos'),
          ('Zoom', 'pinça'),
          ('Teclado', 'toque com três dedos'),
        ];
  final c = Cores.of(context);
  return _folha(context, 'Gestos', segundo ? 'No segundo monitor o toque é direto.' : null, [
    const SizedBox(height: 10),
    for (final l in linhas)
      Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.borda))),
        child: Row(children: [
          SizedBox(width: 150, child: Text(l.$1, style: TextStyle(color: c.suave))),
          Expanded(child: Text(l.$2, style: TextStyle(color: c.texto))),
        ]),
      ),
    const SizedBox(height: 12),
    const Text('Mouse e teclado Bluetooth ligados no tablet funcionam direto.'),
  ]);
}
