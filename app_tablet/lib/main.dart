import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'estado.dart';
import 'paginas/inicio.dart';
import 'tema.dart';

/// Último erro interno (aparece no diagnóstico da tela remota).
final ultimoErro = ValueNotifier<String?>(null);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) {
    ultimoErro.value = d.exceptionAsString().split('\n').first;
    anterior?.call(d);
  };
  PlatformDispatcher.instance.onError = (e, st) {
    ultimoErro.value = '$e'.split('\n').first;
    return true;
  };
  final estado = Estado();
  await estado.carregar();
  runApp(PonteApp(estado: estado));
}

class PonteApp extends StatelessWidget {
  const PonteApp({super.key, required this.estado});
  final Estado estado;

  @override
  Widget build(BuildContext context) {
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
          home: const InicioPagina(),
        ),
      ),
    );
  }
}
