import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

/// Motyw Table na telefon, w tym samym duchu co panel restauracji:
/// tło głębsze od kart, karty na cieniu, przyciski jako pigułki.
abstract final class GuestTheme {
  static ThemeData build(AppPalette p) {
    final base = AppTheme.build(p);
    final dark = p.brightness == Brightness.dark;
    final shadow = dark ? const Color(0xFF000000) : const Color(0xFF0C2A22);
    // Tło schodzi niżej niż karty, więc treść wychodzi do przodu.
    final background = dark
        ? Color.lerp(p.background, Colors.black, 0.35)!
        : p.background;

    return base.copyWith(
      scaffoldBackgroundColor: background,
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: background),
      cardTheme: base.cardTheme.copyWith(
        elevation: dark ? 12 : 10,
        shadowColor: shadow.withValues(alpha: dark ? 0.6 : 0.22),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          side: BorderSide(color: p.ringStrong),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accentFill,
          foregroundColor: p.onAccent,
          disabledBackgroundColor: p.surfaceRaised,
          disabledForegroundColor: p.textDisabled,
          elevation: 3,
          shadowColor: p.accentFill.withValues(alpha: 0.5),
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          backgroundColor: p.surface,
          side: BorderSide(color: p.ringStrong),
          elevation: 2,
          shadowColor: shadow.withValues(alpha: dark ? 0.5 : 0.14),
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: p.ringStrong),
        ),
      ),
      // Dolne menu leży na tle, a wybrana zakładka dostaje akcent.
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: p.surface,
        indicatorColor: p.accentTint,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        elevation: 24,
        shadowColor: shadow.withValues(alpha: dark ? 0.7 : 0.26),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        elevation: 24,
        shadowColor: shadow.withValues(alpha: dark ? 0.7 : 0.26),
      ),
    );
  }
}
