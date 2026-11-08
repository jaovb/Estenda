import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart' show ultimoErro;
import 'package:flutter/services.dart';

import '../conexao.dart';
import '../estado.dart';
import '../tema.dart';
import '../widgets/comuns.dart';
import 'folhas.dart';
import 'teclado.dart';
import 'tela_remota.dart';

/// A tela de um modo (espelhamento ou segundo monitor): conecta, pede a senha se preciso,
/// e mostra o PC com a barra de ferramentas.
class SessaoPagina extends StatefulWidget {
  const SessaoPagina({super.key, required this.app, required this.pc, required this.segundoMonitor});
  final Estado app;
  final PcSalvo pc;
  final bool segundoMonitor;

  @override
  State<SessaoPagina> createState() => _SessaoPaginaState();
}

class _SessaoPaginaState extends State<SessaoPagina> {
  late final Conexao con = Conexao(app: widget.app, pc: widget.pc, segundoMonitor: widget.segundoMonitor)..iniciar();
  late final Modificadores mods = Modificadores(con);
  final vista = Vista();
  final _focoTeclado = FocusNode(debugLabel: 'teclado');
  final _senha = TextEditingController();
  bool _lembrar = true;
  bool _barra = true;
  bool _folhaAberta = false;
  Timer? _esconder;
  StreamSubscription<String>? _avisos;
  final _teclasFisicas = <LogicalKeyboardKey, int>{};
  DateTime? _abertaDesde; // para o "Uso na semana" da tela inicial

  bool get _direto => widget.segundoMonitor || widget.app.modoToque == 'toque';
  Color get _cor => widget.segundoMonitor ? Pastel.azul : Pastel.menta;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    HardwareKeyboard.instance.addHandler(_teclaFisica);
    _focoTeclado.addListener(() => setState(() {}));
    _avisos = con.avisos.listen((t) {
      if (mounted) mostrarAviso(context, t);
    });
    con.addListener(_mudou);
    _agendarEsconder();
  }

  void _mudou() {
    if (con.fase != Fase.aberta) mods.soltarTudo();
    if (con.fase == Fase.aberta) {
      _abertaDesde ??= DateTime.now();
    } else {
      _contarUso();
    }
  }

  void _contarUso() {
    final desde = _abertaDesde;
    if (desde == null) return;
    _abertaDesde = null;
    final s = DateTime.now().difference(desde).inSeconds;
    final app = widget.app;
    Future.microtask(() => app.somarUso(s)); // fora do ciclo de desenho
  }

  @override
  void dispose() {
    _esconder?.cancel();
    _avisos?.cancel();
    HardwareKeyboard.instance.removeHandler(_teclaFisica);
    for (final vk in _teclasFisicas.values) {
      con.tecla(vk, false);
    }
    mods.soltarTudo();
    _contarUso();
    con.removeListener(_mudou);
    con.dispose();
    mods.dispose();
    vista.dispose();
    _focoTeclado.dispose();
    _senha.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _agendarEsconder([int ms = 6000]) {
    _esconder?.cancel();
    _esconder = Timer(Duration(milliseconds: ms), () {
      if (mounted && !_folhaAberta) setState(() => _barra = false);
    });
  }

  void _mostrarBarra() {
    setState(() => _barra = true);
    _agendarEsconder();
  }

  void _alternarTeclado() {
    if (_focoTeclado.hasFocus) {
      _focoTeclado.unfocus();
    } else {
      _focoTeclado.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
  }

  /// Teclado físico (Bluetooth/USB) ligado no tablet.
  bool _teclaFisica(KeyEvent e) {
    if (!mounted || con.fase != Fase.aberta || _folhaAberta) return false;
    if (e is KeyUpEvent) {
      final vk = _teclasFisicas.remove(e.logicalKey);
      if (vk == null) return false;
      con.tecla(vk, false, estendida: e.logicalKey == LogicalKeyboardKey.numpadEnter);
      return true;
    }
    final teclado = HardwareKeyboard.instance;
    final comMods = teclado.isControlPressed || teclado.isMetaPressed || (teclado.isAltPressed && !teclado.isControlPressed);
    final ch = e.character;
    if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 0x20 && !comMods) {
      con.texto(ch);
      return true;
    }
    final vk = vkDaTecla(e.logicalKey);
    if (vk == null) return false;
    _teclasFisicas[e.logicalKey] = vk;
    con.tecla(vk, true, estendida: e.logicalKey == LogicalKeyboardKey.numpadEnter);
    return true;
  }

  Future<void> _folha(Widget Function(BuildContext) construtor) async {
    _focoTeclado.unfocus();
    setState(() {
      _folhaAberta = true;
      _barra = true;
    });
    await abrirFolha(context, construtor);
    if (!mounted) return;
    setState(() => _folhaAberta = false);
    _agendarEsconder();
  }

  void _sair() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final c = Cores.of(context);
    return Scaffold(
      backgroundColor: c.tela,
      resizeToAvoidBottomInset: true,
      body: ListenableBuilder(
        listenable: Listenable.merge([con, widget.app]),
        builder: (context, _) {
          final aberta = con.fase == Fase.aberta && !con.semSegundoMonitor;
          return Column(children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(
                  child: TelaRemota(
                    con: con,
                    vista: vista,
                    direto: _direto,
                    velocidade: widget.app.velocidade,
                    aoTresDedos: _alternarTeclado,
                    aoTocar: () {
                      if (_barra) _agendarEsconder(2500);
                    },
                  ),
                ),
                Positioned(left: 0, bottom: 0, child: CampoTeclado(foco: _focoTeclado, mods: mods)),
                if (aberta) _barraFerramentas(c),
                if (aberta && !_barra) _puxador(c),
                if (aberta) _faixa(c),
                if (aberta) Positioned(left: 8, bottom: 8, right: 8, child: IgnorePointer(child: _diagnostico())),
                if (!aberta) Positioned.fill(child: _cobertura(c)),
              ]),
            ),
            if (_focoTeclado.hasFocus && aberta)
              BarraTeclas(mods: mods, aoFechar: () => _focoTeclado.unfocus()),
          ]);
        },
      ),
    );
  }

  // ------------------------------------------------------------ barra

  Widget _barraFerramentas(Cores c) {
    final ms = con.rtt == null ? '—' : '${con.rtt!.round()} ms';
    final corPonto = con.rtt != null && con.rtt! > 160 ? Pastel.pessego : Pastel.menta;
    Widget botao(IconData i, String dica, VoidCallback f, {bool ativo = false}) => Tooltip(
          message: dica,
          child: Material(
            color: ativo ? c.preenchimento(_cor) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                HapticFeedback.selectionClick();
                _agendarEsconder();
                f();
              },
              child: SizedBox(width: 46, height: 42, child: Icon(i, size: 22, color: ativo ? c.tinta(_cor) : c.suave)),
            ),
          ),
        );
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      top: _barra ? MediaQuery.of(context).padding.top + 10 : -80,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: _barra ? 1 : 0,
          child: Container(
            padding: const EdgeInsets.all(5),
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 16),
            decoration: BoxDecoration(
              color: alfa(c.cartao, 0.94),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.borda),
              boxShadow: sombraSuave(c),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: () => _folha((ctx) => folhaTela(ctx, con, widget.app, vista.reiniciar)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: corPonto, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(ms, style: TextStyle(color: c.suave, fontSize: 13, fontFeatures: const [])),
                    ]),
                  ),
                ),
                Container(width: 1, height: 22, color: c.borda, margin: const EdgeInsets.symmetric(horizontal: 4)),
                botao(Icons.keyboard_rounded, 'Teclado', _alternarTeclado, ativo: _focoTeclado.hasFocus),
                if (!widget.segundoMonitor)
                  botao(_direto ? Icons.touch_app_rounded : Icons.mouse_rounded, _direto ? 'Toque direto' : 'Touchpad', () {
                    widget.app.mudar(() => widget.app.modoToque = _direto ? 'touchpad' : 'toque');
                    mostrarAviso(context, _direto ? 'Toque direto: toque onde quer clicar.' : 'Touchpad: arraste para mover, toque para clicar.');
                  }),
                botao(Icons.keyboard_command_key_rounded, 'Teclas e atalhos', () => _folha((ctx) => folhaTeclas(ctx, con, mods))),
                botao(Icons.content_paste_rounded, 'Copiar e colar', () => _folha((ctx) => FolhaCopiar(con: con))),
                botao(Icons.tune_rounded, 'Tela e qualidade', () => _folha((ctx) => folhaTela(ctx, con, widget.app, vista.reiniciar))),
                botao(Icons.power_settings_new_rounded, 'Energia', () => _folha((ctx) => FolhaEnergia(con: con))),
                botao(Icons.help_outline_rounded, 'Gestos', () => _folha((ctx) => folhaGestos(ctx, widget.segundoMonitor))),
                Container(width: 1, height: 22, color: c.borda, margin: const EdgeInsets.symmetric(horizontal: 4)),
                botao(Icons.logout_rounded, 'Sair', _sair),
                botao(Icons.expand_less_rounded, 'Esconder', () => setState(() => _barra = false)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _puxador(Cores c) => Positioned(
        top: MediaQuery.of(context).padding.top + 6,
        left: 0,
        right: 0,
        child: Center(
          child: GestureDetector(
            onTap: _mostrarBarra,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: alfa(c.cartao, 0.85),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.borda),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: _cor, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Icon(Icons.expand_more_rounded, size: 18, color: c.suave),
              ]),
            ),
          ),
        ),
      );

  /// Linha de diagnóstico (temporária): mostra por que a imagem não aparece.
  Widget _diagnostico() => ValueListenableBuilder<int>(
        valueListenable: con.tique,
        builder: (context, _, __) => ValueListenableBuilder<String?>(
          valueListenable: ultimoErro,
          builder: (context, erro, __) {
            final img = con.quadro;
            final t = 'chegaram ${con.diagRecebidos} · aplicadas ${con.diagAplicados} · inteiras ${con.diagInteiros} · '
                'base ${img == null ? "nenhuma" : "${img.width}×${img.height}"} · camadas ${con.camadas.length} · '
                'pinturas ${con.diagPinturas} · ${con.diagPintura} · monitor ${con.monW.round()}×${con.monH.round()}'
                '${con.diagErro != null ? " · erro: ${con.diagErro}" : ""}${erro != null ? " · flutter: $erro" : ""}';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(8)),
              child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11)),
            );
          },
        ),
      );

  /// Aviso de tela bloqueada ou de desligamento pedido.
  Widget _faixa(Cores c) {
    String? texto;
    Widget? acao;
    if (con.energiaAcao != null && con.energiaFim != null) {
      final s = con.energiaFim!.difference(DateTime.now()).inSeconds.clamp(0, 999);
      texto = 'O PC vai ${con.energiaAcao} em $s s.';
      acao = TextButton(onPressed: () => con.enviar({'t': 'energia', 'acao': 'cancelar'}), child: const Text('Cancelar'));
    } else if (con.avisoTela != null) {
      texto = con.avisoTela == 'segura'
          ? 'O PC está na tela de bloqueio ou num aviso do administrador. Isso só se resolve no próprio PC.'
          : 'Não consegui ver a tela do PC. Tentando de novo…';
    }
    if (texto == null) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.of(context).padding.top + 66,
      left: 16,
      right: 16,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          decoration: BoxDecoration(
            color: c.preenchimento(Pastel.pessego),
            borderRadius: BorderRadius.circular(16),
            boxShadow: sombraSuave(c, forca: 0.6),
          ),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, color: c.tinta(Pastel.pessego)),
            const SizedBox(width: 10),
            Expanded(child: Text(texto, style: TextStyle(color: c.texto))),
            if (acao != null) acao,
          ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ conectando, senha, reconectando, encerrada

  Widget _cobertura(Cores c) {
    final texto = Theme.of(context).textTheme;
    final icone = Hero(
      tag: widget.segundoMonitor ? 'modo-segundo' : 'modo-espelho',
      child: widget.segundoMonitor ? IconeSegundoMonitor(cor: c.tinta(_cor)) : IconeEspelho(cor: c.tinta(_cor)),
    );
    final nome = con.nomePc.isNotEmpty ? con.nomePc : widget.pc.nome;
    late final Widget conteudo;
    if (con.semSegundoMonitor && con.fase == Fase.aberta) {
      conteudo = Column(mainAxisSize: MainAxisSize.min, children: [
        Text('O PC ainda não tem um segundo monitor', style: texto.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text(
          'Instale uma vez o "Virtual Display Driver" (gratuito) no PC e, em Configurações > Sistema > Tela, '
          'escolha "Estender estas telas". Depois é só abrir este modo de novo.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Wrap(spacing: 10, children: [
          FilledButton(onPressed: con.usarTelaPrincipal, child: const Text('Mostrar a tela principal')),
          TextButton(onPressed: _sair, child: const Text('Voltar')),
        ]),
      ]);
    } else if (con.fase == Fase.senha) {
      conteudo = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Senha do $nome', style: texto.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        const Text('Ela aparece no Ponte Remota do PC, no passo "Abra no tablet".', textAlign: TextAlign.center),
        const SizedBox(height: 18),
        TextField(
          controller: _senha,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(hintText: 'abcd-efgh-jkmn', prefixIcon: Icon(Icons.key_rounded)),
          onSubmitted: (_) => _entrar(),
        ),
        CheckboxListTile(
          value: _lembrar,
          onChanged: (v) => setState(() => _lembrar = v ?? true),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Lembrar este tablet (não pede a senha de novo)'),
        ),
        if (con.erro != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(con.erro!, style: TextStyle(color: c.tinta(Pastel.pessego)))),
        FilledButton(
          onPressed: _entrar,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: const Text('Entrar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        TextButton(onPressed: _sair, child: const Text('Voltar')),
      ]);
    } else if (con.fase == Fase.encerrada) {
      conteudo = Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Sessão encerrada', style: texto.titleLarge),
        const SizedBox(height: 6),
        Text(con.motivoFim ?? '', textAlign: TextAlign.center),
        const SizedBox(height: 18),
        Wrap(spacing: 10, children: [
          FilledButton(onPressed: con.reconectarAgora, child: const Text('Conectar de novo')),
          TextButton(onPressed: _sair, child: const Text('Voltar')),
        ]),
      ]);
    } else {
      final reconectando = con.fase == Fase.reconectando;
      conteudo = Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 160,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(color: c.tinta(_cor), backgroundColor: c.preenchimento(_cor)),
          ),
        ),
        const SizedBox(height: 18),
        Text(reconectando ? 'Reconectando…' : (con.fase == Fase.entrando ? 'Entrando no $nome…' : 'Conectando ao $nome…'),
            style: texto.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(con.erro ?? (reconectando ? 'A conexão caiu. Tentando de novo sozinho.' : '${widget.pc.host}:${widget.pc.porta}'),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        TextButton(onPressed: _sair, child: const Text('Voltar')),
      ]);
    }
    return Container(
      color: c.fundo,
      child: FundoPastel(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  icone,
                  const SizedBox(height: 22),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: KeyedSubtree(key: ValueKey('${con.fase}${con.semSegundoMonitor}'), child: conteudo),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _entrar() {
    final s = _senha.text.trim();
    if (normalizarSenha(s).length < 6) {
      mostrarAviso(context, 'Digite a senha que aparece no PC.');
      return;
    }
    FocusScope.of(context).unfocus();
    con.entrarComSenha(s, _lembrar);
  }
}
