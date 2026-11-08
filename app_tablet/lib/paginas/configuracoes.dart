import 'package:flutter/material.dart';

import '../estado.dart';
import '../tema.dart';
import '../widgets/comuns.dart';
import 'pcs.dart';

class ConfiguracoesPagina extends StatelessWidget {
  const ConfiguracoesPagina({super.key});

  @override
  Widget build(BuildContext context) {
    final est = EstadoScope.of(context);
    final c = Cores.of(context);
    final texto = Theme.of(context).textTheme;

    Widget cartao(List<Widget> filhos) => Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.cartao,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.borda),
            boxShadow: sombraSuave(c, forca: 0.6),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: filhos),
        );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                Row(children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Voltar',
                  ),
                  const SizedBox(width: 6),
                  Text('Configurações', style: texto.headlineSmall),
                ]),
                const RotuloSecao('Aparência'),
                cartao([
                  Text('Tema', style: texto.titleMedium),
                  const SizedBox(height: 10),
                  Segmentado<ThemeMode>(
                    opcoes: const [(ThemeMode.system, 'Sistema'), (ThemeMode.light, 'Claro'), (ThemeMode.dark, 'Escuro')],
                    valor: est.tema,
                    aoEscolher: est.definirTema,
                  ),
                ]),
                const RotuloSecao('Conexões'),
                cartao([
                  Row(children: [
                    Expanded(child: Text('Computadores salvos', style: texto.titleMedium)),
                    TextButton.icon(
                      onPressed: () => escolherPc(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Adicionar'),
                    ),
                  ]),
                  if (est.pcs.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 6), child: Text('Nenhum ainda. Toque em Adicionar para procurar na rede.')),
                  for (final pc in est.pcs)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(children: [
                        Icon(Icons.computer_rounded, color: c.tinta(Pastel.azul)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(pc.nome, style: texto.titleMedium),
                            Text('${pc.host}:${pc.porta}', style: TextStyle(color: c.suave, fontSize: 13)),
                          ]),
                        ),
                        if (pc.lembrado)
                          TextButton(
                            onPressed: () {
                              est.esquecerAparelho(pc);
                              mostrarAviso(context, 'Na próxima vez, ${pc.nome} vai pedir a senha.');
                            },
                            child: const Text('Pedir senha'),
                          ),
                        IconButton(
                          onPressed: () => est.removerPc(pc),
                          icon: Icon(Icons.delete_outline_rounded, color: c.suave),
                          tooltip: 'Remover',
                        ),
                      ]),
                    ),
                ]),
                const RotuloSecao('Controle'),
                cartao([
                  Text('Toque no modo espelhamento', style: texto.titleMedium),
                  const SizedBox(height: 10),
                  Segmentado<String>(
                    opcoes: const [('touchpad', 'Touchpad'), ('toque', 'Toque direto')],
                    valor: est.modoToque,
                    cor: Pastel.menta,
                    aoEscolher: (v) => est.mudar(() => est.modoToque = v),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    est.modoToque == 'touchpad'
                        ? 'Como num notebook: arraste para mover o cursor e toque para clicar.'
                        : 'Toque exatamente onde quer clicar.',
                  ),
                  const SizedBox(height: 18),
                  Text('Velocidade do touchpad', style: texto.titleMedium),
                  Slider(
                    value: est.velocidade.clamp(0.5, 2.5).toDouble(),
                    min: 0.5,
                    max: 2.5,
                    divisions: 20,
                    label: '${est.velocidade.toStringAsFixed(1)}×',
                    onChanged: (v) => est.mudar(() => est.velocidade = v),
                  ),
                  const Text('No modo Segundo Monitor o toque é sempre direto, como numa tela touch.'),
                ]),
                const RotuloSecao('Imagem'),
                cartao([
                  Text('Qualidade', style: texto.titleMedium),
                  const SizedBox(height: 10),
                  Segmentado<String>(
                    opcoes: const [('nitida', 'Nítida'), ('equilibrada', 'Equilibrada'), ('leve', 'Leve')],
                    valor: est.qualidade,
                    cor: Pastel.azul,
                    aoEscolher: (v) => est.mudar(() => est.qualidade = v),
                  ),
                  const SizedBox(height: 18),
                  Text('Fluidez', style: texto.titleMedium),
                  const SizedBox(height: 10),
                  Segmentado<int>(
                    opcoes: const [(15, '15 fps'), (30, '30 fps'), (60, '60 fps')],
                    valor: est.fps,
                    cor: Pastel.pessego,
                    aoEscolher: (v) => est.mudar(() => est.fps = v),
                  ),
                ]),
                const RotuloSecao('Segundo monitor'),
                cartao([
                  Text('Como o PC ganha uma tela a mais', style: texto.titleMedium),
                  const SizedBox(height: 6),
                  const Text(
                    'O Windows só cria um monitor novo com um driver de vídeo. Instale uma vez o "Virtual Display Driver" '
                    '(gratuito, código aberto) no PC. Ele aparece como um monitor de verdade em Configurações > Sistema > Tela; '
                    'escolha "Estender estas telas" e posicione ao lado do principal. O app usa esse monitor sozinho.',
                  ),
                ]),
                const SizedBox(height: 24),
                Center(child: Text('Ponte Remota 1.0', style: TextStyle(color: c.suave, fontSize: 12))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
