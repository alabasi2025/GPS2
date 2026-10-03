import 'package:flutter/material.dart';

/// سمة داكنة عالية التباين — مناسبة للاستخدام تحت الشمس وفي الليل.
abstract final class AppTheme {
  static const Color bg = Color(0xFF0B1E3F);
  static const Color surface = Color(0xFF12294F);
  static const Color surfaceHi = Color(0xFF1B3764);
  static const Color accent = Color(0xFF22D3EE);
  static const Color accentDeep = Color(0xFF0EA5B7);
  static const Color good = Color(0xFF34D399);
  static const Color warn = Color(0xFFFBBF24);
  static const Color bad = Color(0xFFF87171);
  static const Color textHi = Color(0xFFF1F5F9);
  static const Color textLo = Color(0xFF94A3B8);

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: bg,
      secondary: good,
      surface: surface,
      onSurface: textHi,
      error: bad,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Tajawal',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontWeight: FontWeight.w700, color: textHi),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, color: textHi),
        titleMedium: TextStyle(fontWeight: FontWeight.w700, color: textHi),
        bodyMedium: TextStyle(color: textHi),
        bodySmall: TextStyle(color: textLo),
        labelSmall: TextStyle(color: textLo),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: bg,
          textStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textHi,
          side: const BorderSide(color: surfaceHi),
          textStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: textHi, backgroundColor: surfaceHi),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceHi,
        contentTextStyle: TextStyle(fontFamily: 'Tajawal', color: textHi),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: const DialogThemeData(backgroundColor: surface),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }

  /// لون حسب جودة الدقة (σ بالمتر).
  static Color accuracyColor(double sigmaM) {
    if (sigmaM <= 1.0) return good;
    if (sigmaM <= 3.0) return accent;
    if (sigmaM <= 8.0) return warn;
    return bad;
  }

  /// لون حسب قوة إشارة C/N0 (dB-Hz).
  static Color cn0Color(double cn0) {
    if (cn0 >= 40) return good;
    if (cn0 >= 30) return accent;
    if (cn0 >= 20) return warn;
    return bad;
  }
}
