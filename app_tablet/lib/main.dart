import 'package:flutter/material.dart';

import 'estado.dart';
import 'paginas/inicio.dart';
import 'sessao/sessao_web.dart';
import 'tema.dart';

// Modo de teste automático (no emulador do GitHub): o app já abre a tela remota sozinho.
//   flutter build apk --dart-define=ESTENDA_TESTE_PC=10.0.2.2:24860 --dart-define=ESTENDA_TESTE_SENHA=...
const _testePc = String.fromEnvironment('ESTENDA_TESTE_PC');
const _testeSenha = String.fromEnvironment('ESTENDA_TESTE_SENHA');
const _testeModo = String.fromEnvironment('ESTENDA_TESTE_MODO', defaultValue: 'espelho');
const _testeSo = String.fromEnvironment('ESTENDA_TESTE_SO');
const _testeSegredo = String.fromEnvironment('ESTENDA_TESTE_SEGREDO');
const _testePcId = String.fromEnvironment('ESTENDA_TESTE_PCID');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final estado = Estado();
  await estado.carregar();
  PcSalvo? teste;
  if (_testePc.isNotEmpty) {
    final partes = _testePc.split(':');
    teste = estado.adicionarPc('PC de teste', partes.first, int.tryParse(partes.last) ?? 24860);
    if (_testeSegredo.isNotEmpty) {
      estado.mudar(() {
        teste!.longeSegredo = _testeSegredo;
        if (_testePcId.isNotEmpty) teste.pcId = _testePcId;
      });
    }
  }
  runApp(PonteApp(estado: estado, teste: teste));
}

class PonteApp extends StatelessWidget {
  const PonteApp({super.key, required this.estado, this.teste});
  final Estado estado;
  final PcSalvo? teste;

  @override
  Widget build(BuildContext context) {
    final pcTeste = teste;
    return EstadoScope(
      estado: estado,
      child: ListenableBuilder(
        listenable: estado,
        builder: (context, _) => MaterialApp(
          title: 'Estenda',
          debugShowCheckedModeBanner: false,
          theme: Tema.claro(),
          darkTheme: Tema.escuro(),
          themeMode: estado.tema,
          // a troca de tema anima todas as cores (inclusive as do app, em Cores.lerp)
          themeAnimationDuration: const Duration(milliseconds: 450),
          themeAnimationCurve: Curves.easeOutCubic,
          home: pcTeste == null
              ? const InicioPagina()
              : SessaoWebPagina(
                  app: estado,
                  pc: pcTeste,
                  segundoMonitor: _testeModo == 'segundo',
                  senhaTeste: _testeSenha.isEmpty ? null : _testeSenha,
                  soTeste: _testeSo.isEmpty ? null : _testeSo,
                ),
        ),
      ),
    );
  }
}
