import 'package:flutter/material.dart';

/// Colours shared by both themes. Status colours keep the same meaning everywhere in the app.
class AppColors {
  static const brand = Color(0xFF1D4ED8);
  static const danger = Color(0xFFDC2626);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
}

class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand, brightness: brightness);
    final isLight = brightness == Brightness.light;
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
    return base.copyWith(
      scaffoldBackgroundColor: isLight ? const Color(0xFFF4F6FB) : const Color(0xFF0E1116),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isLight ? Colors.white : const Color(0xFF181C23),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: isLight ? 0.5 : 0.3)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : const Color(0xFF181C23),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: isLight ? Colors.white : const Color(0xFF14181F),
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
