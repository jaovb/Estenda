import 'package:flutter/material.dart';

import '../descoberta.dart';
import '../estado.dart';
import '../tema.dart';
import '../widgets/comuns.dart';

/// Folha para escolher, procurar na rede ou adicionar um computador.
Future<void> escolherPc(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FolhaPcs(),
    );

class _FolhaPcs extends StatefulWidget {
  const _FolhaPcs();
  @override
  State<_FolhaPcs> createState() => _FolhaPcsState();
}

class _FolhaPcsState extends State<_FolhaPcs> {
  bool _procurando = false;
  List<PcAchado> _achados = [];

  @override
  void initState() {
    super.initState();
    _procurar();
  }

  Future<void> _procurar() async {
    setState(() => _procurando = true);
    final r = await procurarPcs();
    if (!mounted) return;
    setState(() {
      _procurando = false;
      _achados = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final est = EstadoScope.of(context);
    final c = Cores.of(context);
    final salvos = est.pcs;
    final novos = _achados.where((a) => !salvos.any((p) => p.host == a.host && p.porta == a.porta)).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Computadores', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('No PC, abra o Ponte Remota e ligue o acesso. Ele aparece aqui sozinho quando está no mesmo Wi-Fi.'),
            if (salvos.isNotEmpty) const RotuloSecao('Salvos'),
            for (final pc in salvos)
              _LinhaPc(
                titulo: pc.nome,
                sub: '${pc.host}:${pc.porta}${pc.lembrado ? ' · entra sem senha' : ''}',
                cor: Pastel.lavanda,
                escolhido: est.pcAtual == pc,
                icone: Icons.computer_rounded,
                aoTocar: () {
                  est.escolherPc(pc);
                  Navigator.pop(context);
                },
                aoRemover: () => est.removerPc(pc),
              ),
            Row(children: [
              const Expanded(child: RotuloSecao('Na rede')),
              if (_procurando)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
                TextButton.icon(onPressed: _procurar, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Procurar')),
            ]),
            if (!_procurando && novos.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _achados.isEmpty ? 'Nenhum PC novo encontrado.' : 'Os PCs da rede já estão salvos.',
                  style: TextStyle(color: c.suave),
                ),
              ),
            for (final a in novos)
              _LinhaPc(
                titulo: a.nome,
                sub: '${a.host}:${a.porta}',
                cor: Pastel.menta,
                icone: Icons.wifi_rounded,
                aoTocar: () {
                  est.adicionarPc(a.nome, a.host, a.porta);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _adicionar(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar pelo endereço'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                side: BorderSide(color: c.borda),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _adicionar(BuildContext context) async {
    final est = EstadoScope.ler(context);
    final host = TextEditingController();
    final porta = TextEditingController(text: '24860');
    final nome = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('Adicionar computador'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: host, decoration: const InputDecoration(hintText: 'Endereço (ex.: 192.168.0.10)'), keyboardType: TextInputType.url, autofocus: true),
          const SizedBox(height: 10),
          TextField(controller: porta, decoration: const InputDecoration(hintText: 'Porta'), keyboardType: TextInputType.number),
          const SizedBox(height: 10),
          TextField(controller: nome, decoration: const InputDecoration(hintText: 'Nome (opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Adicionar')),
        ],
      ),
    );
    final h = host.text.trim().replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'[/\s]'), '');
    if (ok == true && h.isNotEmpty) {
      est.adicionarPc(nome.text.trim(), h, int.tryParse(porta.text.trim()) ?? 24860);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _LinhaPc extends StatelessWidget {
  const _LinhaPc({
    required this.titulo,
    required this.sub,
    required this.cor,
    required this.icone,
    required this.aoTocar,
    this.escolhido = false,
    this.aoRemover,
  });

  final String titulo, sub;
  final Color cor;
  final IconData icone;
  final VoidCallback aoTocar;
  final bool escolhido;
  final VoidCallback? aoRemover;

  @override
  Widget build(BuildContext context) {
    final c = Cores.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Pressionavel(
        onTap: aoTocar,
        raio: 18,
        sombra: false,
        cor: escolhido ? c.preenchimento(cor) : c.cartao2,
        borda: escolhido ? c.tinta(cor) : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.preenchimento(cor), borderRadius: BorderRadius.circular(12)),
              child: Icon(icone, color: c.tinta(cor), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: Theme.of(context).textTheme.titleMedium),
                Text(sub, style: TextStyle(color: c.suave, fontSize: 13)),
              ]),
            ),
            if (escolhido) Icon(Icons.check_circle_rounded, color: c.tinta(cor)),
            if (aoRemover != null)
              IconButton(onPressed: aoRemover, icon: Icon(Icons.delete_outline_rounded, color: c.suave), tooltip: 'Remover'),
          ]),
        ),
      ),
    );
  }
}
