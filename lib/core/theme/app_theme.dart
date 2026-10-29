import 'package:flutter/material.dart';

/// Chittilata palette: festive night-time indigo with marigold, kumkum and
/// leaf accents, and warm cream "paper" for the slips themselves.
@immutable
class GameColors extends ThemeExtension<GameColors> {
  const GameColors({
    required this.bgTop,
    required this.bgBottom,
    required this.surface,
    required this.surfaceHigh,
    required this.onSurface,
    required this.muted,
    required this.paper,
    required this.paperEdge,
    required this.ink,
    required this.marigold,
    required this.kumkum,
    required this.leaf,
    required this.teal,
    required this.outline,
  });

  final Color bgTop;
  final Color bgBottom;
  final Color surface;
  final Color surfaceHigh;
  final Color onSurface;
  final Color muted;
  final Color paper;
  final Color paperEdge;
  final Color ink;
  final Color marigold;
  final Color kumkum;
  final Color leaf;
  final Color teal;
  final Color outline;

  static const dark = GameColors(
    bgTop: Color(0xFF241347),
    bgBottom: Color(0xFF120A26),
    surface: Color(0xFF2C1C55),
    surfaceHigh: Color(0xFF3A2770),
    onSurface: Color(0xFFF7F0FF),
    muted: Color(0xFFB9A9D9),
    paper: Color(0xFFFFF6E3),
    paperEdge: Color(0xFFE9D6AE),
    ink: Color(0xFF2B1B3D),
    marigold: Color(0xFFFFB627),
    kumkum: Color(0xFFEF4A62),
    leaf: Color(0xFF58D68D),
    teal: Color(0xFF3CC9C0),
    outline: Color(0x33FFFFFF),
  );

  static const light = GameColors(
    bgTop: Color(0xFFFFF4DF),
    bgBottom: Color(0xFFF6E2C2),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF3E7FF),
    onSurface: Color(0xFF241347),
    muted: Color(0xFF6E5A8F),
    paper: Color(0xFFFFFBF2),
    paperEdge: Color(0xFFE2CB9C),
    ink: Color(0xFF2B1B3D),
    marigold: Color(0xFFE59A00),
    kumkum: Color(0xFFD12F4A),
    leaf: Color(0xFF1E9E57),
    teal: Color(0xFF14918A),
    outline: Color(0x22241347),
  );

  @override
  GameColors copyWith() => this;

  @override
  GameColors lerp(ThemeExtension<GameColors>? other, double t) {
    if (other is! GameColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return GameColors(
      bgTop: l(bgTop, other.bgTop),
      bgBottom: l(bgBottom, other.bgBottom),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      onSurface: l(onSurface, other.onSurface),
      muted: l(muted, other.muted),
      paper: l(paper, other.paper),
      paperEdge: l(paperEdge, other.paperEdge),
      ink: l(ink, other.ink),
      marigold: l(marigold, other.marigold),
      kumkum: l(kumkum, other.kumkum),
      leaf: l(leaf, other.leaf),
      teal: l(teal, other.teal),
      outline: l(outline, other.outline),
    );
  }
}

abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 600);
  static const curve = Curves.easeOutCubic;

  /// Shortens or removes animation when the system asks for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : d;
}

extension GameThemeX on BuildContext {
  GameColors get colors => Theme.of(this).extension<GameColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? GameColors.dark : GameColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: c.marigold,
    brightness: brightness,
    primary: c.marigold,
    onPrimary: const Color(0xFF2B1B3D),
    secondary: c.kumkum,
    surface: c.surface,
    onSurface: c.onSurface,
    error: c.kumkum,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final text = base.textTheme.apply(
    bodyColor: c.onSurface,
    displayColor: c.onSurface,
  );
  return base.copyWith(
    scaffoldBackgroundColor: c.bgBottom,
    extensions: [c],
    textTheme: text.copyWith(
      displaySmall: text.displaySmall?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
      ),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: text.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: c.onSurface,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.marigold, width: 2),
      ),
      labelStyle: TextStyle(color: c.muted),
      hintStyle: TextStyle(color: c.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surfaceHigh,
      contentTextStyle: TextStyle(
        color: c.onSurface,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: c.surfaceHigh,
      selectedColor: c.marigold,
      labelStyle: TextStyle(color: c.onSurface, fontWeight: FontWeight.w700),
      side: BorderSide(color: c.outline),
      shape: const StadiumBorder(),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.ink : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.marigold : null,
      ),
    ),
  );
}
