import 'package:flutter/material.dart';

/// Cor com transparência (sem depender de APIs que mudaram entre versões do Flutter).
Color alfa(Color c, double a) => c.withAlpha((a * 255).round().clamp(0, 255).toInt());

/// Os quatro pastéis do app.
class Pastel {
  static const azul = Color(0xFFA9C8EC);
  static const menta = Color(0xFFA8E6CF);
  static const lavanda = Color(0xFFC9B8E8);
  static const pessego = Color(0xFFFFCFAE);

  // versões fortes de cada pastel: ícones, botões e textos no modo claro (bom contraste)
  static const azulForte = Color(0xFF2F6EA5);
  static const mentaForte = Color(0xFF2E7D5B);
  static const lavandaForte = Color(0xFF6B5AA6);
  static const pessegoForte = Color(0xFFB4693C);

  static Color forte(Color pastel) {
    if (pastel == azul) return azulForte;
    if (pastel == menta) return mentaForte;
    if (pastel == lavanda) return lavandaForte;
    if (pastel == pessego) return pessegoForte;
    return Color.lerp(pastel, const Color(0xFF1E2133), 0.6)!;
  }
}

/// Cores do app além das do Material, com transição suave entre claro e escuro.
@immutable
class Cores extends ThemeExtension<Cores> {
  const Cores({
    required this.fundo,
    required this.cartao,
    required this.cartao2,
    required this.borda,
    required this.texto,
    required this.suave,
    required this.sombra,
    required this.tela,
    required this.escuro,
  });

  final Color fundo, cartao, cartao2, borda, texto, suave, sombra, tela;
  final bool escuro;

  /// Fundo de um destaque: no claro, o pastel clareado; no escuro, o pastel bem diluído.
  Color preenchimento(Color pastel) =>
      escuro ? Color.alphaBlend(alfa(pastel, 0.14), cartao) : Color.lerp(pastel, Colors.white, 0.5)!;

  /// Ícones e textos sobre o destaque: no claro, a versão forte; no escuro, o pastel puro.
  Color tinta(Color pastel) => escuro ? pastel : Pastel.forte(pastel);

  static Cores of(BuildContext context) => Theme.of(context).extension<Cores>()!;

  @override
  Cores copyWith() => this;

  @override
  Cores lerp(ThemeExtension<Cores>? outro, double t) {
    if (outro is! Cores) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Cores(
      fundo: l(fundo, outro.fundo),
      cartao: l(cartao, outro.cartao),
      cartao2: l(cartao2, outro.cartao2),
      borda: l(borda, outro.borda),
      texto: l(texto, outro.texto),
      suave: l(suave, outro.suave),
      sombra: l(sombra, outro.sombra),
      tela: l(tela, outro.tela),
      escuro: t < 0.5 ? escuro : outro.escuro,
    );
  }
}

class Tema {
  static const _claro = Cores(
    fundo: Color(0xFFF6F7FB),
    cartao: Color(0xFFFFFFFF),
    cartao2: Color(0xFFF0F1F7),
    borda: Color(0xFFE6E8F0),
    texto: Color(0xFF1F2330),
    suave: Color(0xFF5F6475),
    sombra: Color(0x1F3B4060),
    tela: Color(0xFFE6E3EC),
    escuro: false,
  );
  static const _escuro = Cores(
    fundo: Color(0xFF1A1A2E),
    cartao: Color(0xFF23233B),
    cartao2: Color(0xFF2C2C47),
    borda: Color(0xFF36365A),
    texto: Color(0xFFE9E8F2),
    suave: Color(0xFFA4A3C0),
    sombra: Color(0x73000000),
    tela: Color(0xFF121222),
    escuro: true,
  );

  static ThemeData claro() => _base(_claro, Brightness.light);
  static ThemeData escuro() => _base(_escuro, Brightness.dark);

  static ThemeData _base(Cores c, Brightness b) {
    final escuro = b == Brightness.dark;
    final primaria = escuro ? Pastel.lavanda : const Color(0xFF5E4E93);
    final esquema = ColorScheme.fromSeed(seedColor: Pastel.lavanda, brightness: b).copyWith(
      primary: primaria,
      onPrimary: escuro ? const Color(0xFF1A1A2E) : Colors.white,
      surface: c.cartao,
      onSurface: c.texto,
    );
    final base = ThemeData(useMaterial3: true, brightness: b, colorScheme: esquema);
    final texto = base.textTheme.apply(bodyColor: c.texto, displayColor: c.texto);
    return base.copyWith(
      scaffoldBackgroundColor: c.fundo,
      extensions: [c],
      textTheme: texto.copyWith(
        headlineLarge: texto.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
        headlineSmall: texto.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
        titleLarge: texto.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleMedium: texto.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: texto.bodyMedium?.copyWith(color: c.suave, height: 1.45),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.cartao,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.borda,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.cartao2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primaria, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: escuro ? const Color(0xFF34345A) : const Color(0xFF2E3147),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      sliderTheme: SliderThemeData(activeTrackColor: primaria, thumbColor: primaria, inactiveTrackColor: c.borda),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
      }),
    );
  }
}

/// Sombra leve e difusa, usada em cards e botões.
List<BoxShadow> sombraSuave(Cores c, {double forca = 1}) => [
      BoxShadow(color: c.sombra, blurRadius: 24 * forca, offset: Offset(0, 10 * forca), spreadRadius: -6),
      BoxShadow(color: alfa(c.sombra, 0.35), blurRadius: 6 * forca, offset: Offset(0, 2 * forca)),
    ];
