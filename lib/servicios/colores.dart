import 'package:material_ui/material_ui.dart';

/// Paleta de marca de TallerNeto — LA MISMA del panel web
/// («taller industrial premium»): grafito azulado casi negro
/// (#0d1526), ámbar de maquinaria en degradado (#f59e0b → #f97316),
/// fondo cálido claro (#f4f4f2) y tarjetas blancas. La app y el
/// panel son el mismo producto: se visten igual.
abstract final class ColoresMarca {
  static const grafito950 = Color(0xFF0A1120);
  static const grafito900 = Color(0xFF0D1526);
  static const grafito800 = Color(0xFF14213C);
  static const grafito = Color(0xFF22304F);
  static const ambar = Color(0xFFF59E0B);
  static const ambar2 = Color(0xFFF97316);
  static const ambarOscuro = Color(0xFFB45309);
  static const ambarSuave = Color(0xFFFDF3E0);
  static const fondoCalido = Color(0xFFF4F4F2);
  static const borde = Color(0xFFE4E1DA);
  static const textoFuerte = Color(0xFF131820);
  static const acero = Color(0xFF4A5568);
  static const verde = Color(0xFF15803D);
  static const rojo = Color(0xFFB91C1C);

  /// Degradado de marca (botones primarios, cabeceras).
  static const degradado = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ambar, ambar2],
  );

  /// Tema CLARO: fondo cálido, tarjetas blancas, grafito en la
  /// barra superior (como la barra lateral del panel) y ámbar
  /// como acción principal.
  static ThemeData temaClaro() {
    final base = ColorScheme.fromSeed(
      seedColor: ambar,
      brightness: Brightness.light,
    );
    final cs = base.copyWith(
      primary: ambarOscuro,
      onPrimary: Colors.white,
      primaryContainer: ambarSuave,
      onPrimaryContainer: grafito900,
      surface: Colors.white,
      onSurface: textoFuerte,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFFBFAF7),
      surfaceContainer: Color(0xFFF4F1EA),
      surfaceContainerHigh: Color(0xFFECE8DE),
      surfaceContainerHighest: Color(0xFFE4E1DA),
      outline: borde,
      outlineVariant: Color(0xFFEDEAE3),
    );
    return _conEstilo(cs, Brightness.light);
  }

  /// Tema OSCURO (modo noche): el grafito de la marca manda —
  /// fondo grafito-950, superficies grafito-800 y el ámbar vivo.
  static ThemeData temaOscuro() {
    final base = ColorScheme.fromSeed(
      seedColor: ambar,
      brightness: Brightness.dark,
    );
    final cs = base.copyWith(
      primary: ambar,
      onPrimary: grafito950,
      primaryContainer: grafito,
      onPrimaryContainer: Color(0xFFF5F7FA),
      surface: grafito800,
      onSurface: Color(0xFFE7ECF3),
      surfaceContainerLowest: grafito950,
      surfaceContainerLow: Color(0xFF101A30),
      surfaceContainer: grafito800,
      surfaceContainerHigh: Color(0xFF1B2A47),
      surfaceContainerHighest: Color(0xFF24365C),
      outline: Color(0xFF33456B),
      outlineVariant: Color(0xFF27395C),
    );
    return _conEstilo(cs, Brightness.dark);
  }

  static ThemeData _conEstilo(ColorScheme cs, Brightness brillo) {
    final oscuro = brillo == Brightness.dark;
    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      scaffoldBackgroundColor: oscuro ? grafito950 : fondoCalido,
      appBarTheme: AppBarTheme(
        backgroundColor: grafito900,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: Color(0xFFFBBF24)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: oscuro ? grafito900 : Colors.white,
        indicatorColor: ambarSuave.withValues(alpha: oscuro ? 0.18 : 1),
        labelTextStyle: WidgetStateProperty.resolveWith((estados) {
          final activa = estados.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: activa ? FontWeight.w700 : FontWeight.w500,
            color: activa
                ? (oscuro ? ambar : ambarOscuro)
                : (oscuro ? Color(0xFF9AA7BC) : acero),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((estados) {
          final activa = estados.contains(WidgetState.selected);
          return IconThemeData(
            color: activa
                ? (oscuro ? ambar : ambarOscuro)
                : (oscuro ? Color(0xFF9AA7BC) : acero),
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: oscuro ? grafito800 : Colors.white,
        elevation: oscuro ? 0 : 1.5,
        shadowColor: Colors.black.withValues(alpha: oscuro ? 0.35 : 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: oscuro ? Color(0xFF27395C) : borde,
            width: 1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ambarOscuro,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: oscuro ? Color(0xFF33456B) : borde),
      ),
    );
  }
}
