import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

/// Motyw Table dopasowany do komputera: niższe przyciski o szerokości treści,
/// gęstsze pola formularzy i wyraźny kursor nad elementami klikalnymi.
abstract final class PanelTheme {
  static ThemeData build(AppPalette p) {
    final base = AppTheme.build(p);
    final dark = p.brightness == Brightness.dark;
    final shadow = dark ? const Color(0xFF000000) : const Color(0xFF0C2A22);
    const radius10 = BorderRadius.all(Radius.circular(10));
    const buttonText = TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    const padding = EdgeInsets.symmetric(horizontal: 16);
    const size = Size(0, 40);

    return base.copyWith(
      visualDensity: VisualDensity.standard,
      // Im większy napis, tym ciaśniejsze odstępy liter. Tekst zwykły zostaje.
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(letterSpacing: -1),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(letterSpacing: -0.6),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(letterSpacing: -0.4),
        titleLarge: base.textTheme.titleLarge?.copyWith(letterSpacing: -0.2),
      ),
      // Karty odrywają się od tła cieniem, a nie samym pierścieniem.
      cardTheme: base.cardTheme.copyWith(
        elevation: dark ? 14 : 16,
        shadowColor: shadow.withValues(alpha: dark ? 0.7 : 0.3),
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
          minimumSize: size,
          padding: padding,
          shape: const RoundedRectangleBorder(borderRadius: radius10),
          textStyle: buttonText,
          enabledMouseCursor: SystemMouseCursors.click,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          backgroundColor: dark ? p.surface : p.background,
          side: BorderSide(color: p.ringStrong),
          elevation: 2,
          shadowColor: shadow.withValues(alpha: dark ? 0.5 : 0.12),
          minimumSize: size,
          padding: padding,
          shape: const StadiumBorder(),
          textStyle: buttonText,
          enabledMouseCursor: SystemMouseCursors.click,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: const StadiumBorder(),
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.textMuted,
          backgroundColor: dark ? p.surface : p.background,
          minimumSize: const Size(36, 36),
          shape: RoundedRectangleBorder(
            borderRadius: radius10,
            side: BorderSide(color: dark ? p.ring : p.ringStrong),
          ),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        isDense: true,
        filled: true,
        fillColor: dark ? p.surface : p.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: const OutlineInputBorder(
          borderRadius: radius10,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius10,
          borderSide: BorderSide(color: p.ringStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius10,
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius10,
          borderSide: BorderSide(color: p.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius10,
          borderSide: BorderSide(color: p.error, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 28,
        shadowColor: shadow.withValues(alpha: dark ? 0.75 : 0.28),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: p.text,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 12,
          color: p.background,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onAccent : p.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accentFill : p.surfaceRaised,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(width: 420),
    );
  }
}

/// Warstwy panelu: menu najgłębiej, treść wyżej, karty na wierzchu.
abstract final class PanelDepth {
  static bool get _dark => AppColors.palette.brightness == Brightness.dark;

  static Color get _shadow =>
      _dark ? const Color(0xFF000000) : const Color(0xFF0C2A22);

  /// Tło menu: najgłębsza warstwa panelu.
  static Color get sidebar => _dark
      ? Color.lerp(AppColors.background, Colors.black, 0.6)!
      : Color.lerp(AppColors.background, Colors.black, 0.06)!;

  /// Tło treści: jednolite, ciemniejsze od kart.
  static Color get content => _dark
      ? Color.lerp(AppColors.background, Colors.black, 0.4)!
      : AppColors.background;

  /// Cień rzucany przez menu na treść.
  static List<BoxShadow> get sidebarEdge => [
    BoxShadow(
      color: _shadow.withValues(alpha: _dark ? 0.55 : 0.12),
      blurRadius: 18,
      offset: const Offset(2, 0),
    ),
  ];

  /// Cień pod wyróżnionym elementem, na przykład wybraną sekcją menu.
  static List<BoxShadow> get raised => [
    BoxShadow(
      color: _shadow.withValues(alpha: _dark ? 0.5 : 0.14),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];
}
