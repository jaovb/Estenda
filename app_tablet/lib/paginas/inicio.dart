import 'package:flutter/material.dart';

import '../estado.dart';
import '../sessao/sessao.dart';
import '../tema.dart';
import '../widgets/comuns.dart';
import 'configuracoes.dart';
import 'pcs.dart';

/// Tela principal: os dois modos em cards e, embaixo, dispositivos e uso na semana.
class InicioPagina extends StatefulWidget {
  const InicioPagina({super.key});
  @override
  State<InicioPagina> createState() => _InicioPaginaState();
}

class _InicioPaginaState extends State<InicioPagina> with SingleTickerProviderStateMixin {
  late final AnimationController _entrada =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  late final List<Animation<double>> _anims = List.generate(6, (ordem) {
    final ini = (ordem * 0.09).clamp(0.0, 0.5).toDouble();
    return CurvedAnimation(parent: _entrada, curve: Interval(ini, ini + 0.5, curve: Curves.easeOutCubic));
  });

  @override
  void dispose() {
    _entrada.dispose();
    super.dispose();
  }

  /// Cada bloco entra subindo e aparecendo, um pouco depois do anterior.
  Widget _surgir(int ordem, Widget filho) {
    final anim = _anims[ordem];
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(anim), child: filho),
    );
  }

  Future<void> _abrir(bool segundo) async {
    final est = EstadoScope.ler(context);
    var pc = est.pcAtual;
    if (pc == null) {
      await escolherPc(context);
      pc = est.pcAtual;
      if (pc == null || !mounted) return;
    }
    final escolhido = pc;
    await Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, __, ___) => SessaoPagina(app: est, pc: escolhido, segundoMonitor: segundo),
      transitionsBuilder: (_, a, __, filho) {
        final curva = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curva,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curva), child: filho),
        );
      },
    ));
  }

  static String _horas(int segundos) {
    final min = segundos ~/ 60;
    if (min < 60) return '$min min';
    final h = min ~/ 60, resto = min % 60;
    return h < 10 && resto > 0 ? '${h}h ${resto}min' : '${h}h';
  }

  @override
  Widget build(BuildContext context) {
    final est = EstadoScope.of(context);
    final c = Cores.of(context);
    final texto = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
              children: [
                _surgir(
                  0,
                  Row(children: [
                    Expanded(
                      child: Text('Estenda',
                          style: texto.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    ),
                    Tooltip(
                      message: 'Configurações',
                      child: Pressionavel(
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConfiguracoesPagina())),
                        raio: 999,
                        escala: 0.9,
                        borda: Colors.transparent,
                        child: SizedBox(width: 48, height: 48, child: Icon(Icons.settings_outlined, color: c.texto, size: 22)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 28),
                _surgir(
                  1,
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Olá! O que vamos fazer hoje?',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: c.texto)),
                    const SizedBox(height: 4),
                    Text('Escolha um modo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.suave)),
                  ]),
                ),
                const SizedBox(height: 16),
                _surgir(
                  2,
                  _CardModo(
                    heroTag: 'modo-segundo',
                    cor: Pastel.azul,
                    icone: Icons.devices_rounded,
                    titulo: 'Segundo monitor',
                    descricao: 'Ganhe mais espaço estendendo sua tela',
                    aoTocar: () => _abrir(true),
                  ),
                ),
                const SizedBox(height: 16),
                _surgir(
                  3,
                  _CardModo(
                    heroTag: 'modo-espelho',
                    cor: Pastel.menta,
                    icone: Icons.content_copy_rounded,
                    titulo: 'Espelhamento do computador',
                    descricao: 'Mostre a mesma tela no tablet e controle o PC',
                    aoTocar: () => _abrir(false),
                  ),
                ),
                const SizedBox(height: 16),
                _surgir(
                  4,
                  IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(
                        child: _CardNumero(
                          cor: Pastel.lavanda,
                          icone: Icons.link_rounded,
                          numero: '${est.pcs.length}',
                          rotulo: est.pcs.length == 1 ? 'Dispositivo' : 'Dispositivos',
                          detalhe: est.pcAtual?.nome,
                          aoTocar: () => escolherPc(context),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _CardNumero(
                          cor: Pastel.pessego,
                          icone: Icons.schedule_rounded,
                          numero: _horas(est.usoSemana),
                          rotulo: 'Uso na semana',
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 22),
                _surgir(
                  5,
                  Text(
                    est.pcs.isEmpty
                        ? 'No PC, abra o Ponte Remota e ligue o acesso. Depois toque em Dispositivos para encontrá-lo.'
                        : 'O PC e o tablet precisam estar no mesmo Wi-Fi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.suave, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Card de modo: ícone num quadrado pastel, título, descrição e um botão redondo com seta.
class _CardModo extends StatelessWidget {
  const _CardModo({
    required this.heroTag,
    required this.cor,
    required this.icone,
    required this.titulo,
    required this.descricao,
    required this.aoTocar,
  });

  final String heroTag, titulo, descricao;
  final Color cor;
  final IconData icone;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = Cores.of(context);
    return Pressionavel(
      onTap: aoTocar,
      raio: 26,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        child: Row(children: [
          Hero(
            tag: heroTag,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.preenchimento(cor), borderRadius: BorderRadius.circular(18)),
              child: Icon(icone, color: c.tinta(cor), size: 30),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.texto, height: 1.25)),
              const SizedBox(height: 4),
              Text(descricao, style: TextStyle(fontSize: 14, color: c.suave, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 12),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: c.escuro ? cor : Pastel.forte(cor), shape: BoxShape.circle),
            child: Icon(Icons.chevron_right_rounded, color: c.escuro ? const Color(0xFF1A1A2E) : Colors.white),
          ),
        ]),
      ),
    );
  }
}

/// Card pequeno com um número grande (dispositivos, uso na semana).
class _CardNumero extends StatelessWidget {
  const _CardNumero({
    required this.cor,
    required this.icone,
    required this.numero,
    required this.rotulo,
    this.detalhe,
    this.aoTocar,
  });

  final Color cor;
  final IconData icone;
  final String numero, rotulo;
  final String? detalhe;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = Cores.of(context);
    return Pressionavel(
      onTap: aoTocar,
      raio: 26,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: c.preenchimento(cor), shape: BoxShape.circle),
            child: Icon(icone, color: c.tinta(cor), size: 22),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(numero,
                key: ValueKey(numero),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c.texto, letterSpacing: -0.5)),
          ),
          const SizedBox(height: 2),
          Text(rotulo, style: TextStyle(fontSize: 14, color: c.suave)),
          if (detalhe != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('atual: $detalhe',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.suave)),
            ),
        ]),
      ),
    );
  }
}
