import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

/// Ciemna paleta panelu. Mniej poziomów szarości niż w aplikacji dla gości:
/// tło i menu mają jeden kolor, karty są o krok jaśniejsze, a elementy na kartach
/// o kolejny. Obrysy to biel z małą przezroczystością, bo cienie na czerni nie działają.
abstract final class PanelPalette {
  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF09090B),
    surface: Color(0xFF111113),
    surfaceRaised: Color(0xFF19191C),
    outline: Color(0xFF27272A),
    text: Color(0xFFEDEDEF),
    textMuted: Color(0xFF8F8F98),
    textDisabled: Color(0xFF55555D),
    accent: Color(0xFF00F8B9),
    accentFill: Color(0xFF00F8B9),
    onAccent: Color(0xFF09090B),
    onAccentStrong: Color(0xFF09090B),
    accentTint: Color(0x1A00F8B9),
    warning: Color(0xFFFFB547),
    error: Color(0xFFFF6B6B),
    ring: Color(0x12FFFFFF),
    ringStrong: Color(0x1FFFFFFF),
  );
}

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
      // Suwaki list mają odstęp od końców i boku, żeby nie wychodziły poza zaokrąglone rogi kart.
      scrollbarTheme: const ScrollbarThemeData(
        mainAxisMargin: 12,
        crossAxisMargin: 4,
        radius: Radius.circular(8),
      ),
      // Im większy napis, tym ciaśniejsze odstępy liter. Tekst zwykły zostaje.
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(letterSpacing: -1),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(letterSpacing: -0.6),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(letterSpacing: -0.4),
        titleLarge: base.textTheme.titleLarge?.copyWith(letterSpacing: -0.2),
      ),
      // W jasnym motywie karty odrywa cień. W ciemnym cień robi tylko brudną obwódkę,
      // więc kartę wyznacza jaśniejsze tło i cienki obrys.
      cardTheme: base.cardTheme.copyWith(
        elevation: dark ? 0 : 16,
        shadowColor: dark ? Colors.transparent : shadow.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          side: BorderSide(color: dark ? p.ring : p.ringStrong),
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
          elevation: dark ? 0 : 2,
          shadowColor: dark ? Colors.transparent : shadow.withValues(alpha: 0.12),
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

  /// Tło menu. W ciemnym motywie to samo co treść, a oddziela je cienka linia.
  static Color get sidebar => _dark
      ? AppColors.background
      : Color.lerp(AppColors.background, Colors.black, 0.06)!;

  /// Tło treści: jednolite, ciemniejsze od kart.
  static Color get content => AppColors.background;

  /// Cień rzucany przez menu na treść. W ciemnym motywie zamiast cienia jest linia.
  static List<BoxShadow> get sidebarEdge => _dark
      ? const []
      : [
          BoxShadow(
            color: _shadow.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(2, 0),
          ),
        ];

  /// Linia między menu a treścią w ciemnym motywie.
  static Border? get sidebarBorder => _dark
      ? Border(right: BorderSide(color: AppColors.ring))
      : null;

  /// Cień pod wyróżnionym elementem, na przykład wybraną sekcją menu.
  static List<BoxShadow> get raised => [
    BoxShadow(
      color: _shadow.withValues(alpha: _dark ? 0.5 : 0.14),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];
}
