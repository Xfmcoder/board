import 'package:flutter/material.dart';

/// Palette — a dark "workflow canvas" look in the spirit of n8n.
class C {
  C._();

  static const Color bg = Color(0xFF0E0F13);
  static const Color surface = Color(0xFF191B22);
  static const Color surface2 = Color(0xFF212430);
  static const Color border = Color(0xFF2E323D);
  static const Color text = Color(0xFFF4F5F7);
  static const Color muted = Color(0xFF9BA3B2);
  static const Color accent = Color(0xFFFF6D5A);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color green = Color(0xFF3DDC97);
  static const Color amber = Color(0xFFFBBF24);
  static const Color blue = Color(0xFF5AA9FF);
}

/// Handwriting families. Caveat covers Latin, Atma covers Bengali — the
/// fallback chain makes a mixed Bangla/English line look uniformly handwritten.
const String kHand = 'Caveat';
const String kBn = 'Kalam';

TextStyle hand(
  double size, {
  Color color = C.text,
  double weight = 700,
  double? height,
  FontStyle? style,
  TextDecoration? decoration,
  List<Shadow>? shadows,
}) {
  // Caveat is a variable font (wght axis), Atma is static — set BOTH so the
  // Bengali fallback glyphs get the real bold face instead of synthesised 400.
  final int w = weight.round().clamp(100, 900);
  final FontWeight fw = FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];
  return TextStyle(
    fontFamily: kHand,
    fontFamilyFallback: const <String>[kBn],
    fontSize: size,
    fontWeight: fw,
    color: color,
    height: height,
    fontStyle: style,
    decoration: decoration,
    shadows: shadows,
    fontVariations: <FontVariation>[FontVariation('wght', w.toDouble())],
    leadingDistribution: TextLeadingDistribution.even,
  );
}

ThemeData boardTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    splashFactory: InkSparkle.splashFactory,
    colorScheme: base.colorScheme.copyWith(
      primary: C.accent,
      secondary: C.violet,
      surface: C.surface,
      onSurface: C.text,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: C.accent,
      selectionColor: Color(0x55FF6D5A),
      selectionHandleColor: C.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface2,
      hintStyle: hand(15, color: C.muted, weight: 500),
      labelStyle: hand(15, color: C.muted, weight: 500),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: C.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: C.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: C.accent, width: 1.6),
      ),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: C.surface),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: C.surface),
  );
}
