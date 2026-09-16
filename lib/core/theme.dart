import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../shared/app_icons.dart';

/// Paleta jednego motywu. Kontrasty tekstu sprawdzone względem tła i kart.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.outline,
    required this.text,
    required this.textMuted,
    required this.textDisabled,
    required this.accent,
    required this.accentFill,
    required this.onAccent,
    required this.onAccentStrong,
    required this.accentTint,
    required this.warning,
    required this.error,
    required this.ring,
    required this.ringStrong,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color outline;
  final Color text;
  final Color textMuted;
  final Color textDisabled;

  /// Akcent do tekstu, ikon i obramowań. W jasnym motywie ciemniejsza mięta,
  /// bo #00F8B9 na białym ma kontrast tylko 1,4:1.
  final Color accent;

  /// Mięta z logo do wypełnień: przycisków, zaznaczonych godzin i odznak.
  final Color accentFill;

  /// Tekst na wypełnieniu [accentFill].
  final Color onAccent;

  /// Tekst i znaczniki na kolorze [accent], na przykład ptaszek w polu wyboru.
  final Color onAccentStrong;
  final Color accentTint;
  final Color warning;
  final Color error;

  /// Pierścień zamiast twardego obramowania. Przezroczystość pasuje do każdej powierzchni.
  final Color ring;
  final Color ringStrong;

  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF161616),
    surface: Color(0xFF222222),
    surfaceRaised: Color(0xFF2A2A2A),
    outline: Color(0xFF333333),
    text: Color(0xFFF2F2F2),
    textMuted: Color(0xFFA3A3A3),
    textDisabled: Color(0xFF6B6B6B),
    accent: Color(0xFF00F8B9),
    accentFill: Color(0xFF00F8B9),
    onAccent: Color(0xFF161616),
    onAccentStrong: Color(0xFF161616),
    accentTint: Color(0x1A00F8B9),
    warning: Color(0xFFFFB547),
    error: Color(0xFFFF6B6B),
    ring: Color(0x14FFFFFF),
    ringStrong: Color(0x21FFFFFF),
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF4F5F4),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEEF0EF),
    outline: Color(0xFFDADDDB),
    text: Color(0xFF161616),
    textMuted: Color(0xFF5B5F5D),
    textDisabled: Color(0xFF9A9E9C),
    accent: Color(0xFF007A5C),
    accentFill: Color(0xFF00F8B9),
    onAccent: Color(0xFF161616),
    onAccentStrong: Color(0xFFFFFFFF),
    accentTint: Color(0x1A007A5C),
    warning: Color(0xFF9A5B00),
    error: Color(0xFFC62828),
    ring: Color(0x1A000000),
    ringStrong: Color(0x29000000),
  );
}

/// Kolory bieżącego motywu.
/// Aplikacja wybiera paletę przy starcie i przy każdej zmianie motywu, a potem
/// odbudowuje całe drzewo widżetów, więc każdy odczyt w build zwraca aktualny kolor.
abstract final class AppColors {
  static AppPalette _palette = AppPalette.dark;

  static AppPalette get palette => _palette;
  static void use(AppPalette palette) => _palette = palette;

  static Color get background => _palette.background;
  static Color get surface => _palette.surface;
  static Color get surfaceRaised => _palette.surfaceRaised;
  static Color get outline => _palette.outline;
  static Color get text => _palette.text;
  static Color get textMuted => _palette.textMuted;
  static Color get textDisabled => _palette.textDisabled;
  static Color get accent => _palette.accent;
  static Color get accentFill => _palette.accentFill;
  static Color get onAccent => _palette.onAccent;
  static Color get onAccentStrong => _palette.onAccentStrong;
  static Color get accentTint => _palette.accentTint;
  static Color get warning => _palette.warning;
  static Color get error => _palette.error;
  static Color get ring => _palette.ring;
  static Color get ringStrong => _palette.ringStrong;
}

/// Krzywe ruchu. Mocny ease-out dla wejść, standardowa krzywa dla zmian stanu.
abstract final class AppMotion {
  static const easeOut = Cubic(0.23, 1, 0.32, 1);
  static const standard = Cubic(0.2, 0, 0, 1);
}

abstract final class AppTheme {
  static const fontFamily = 'Geist';

  static TextStyle? _type(
    TextStyle? base,
    double size,
    double height,
    double tracking,
    FontWeight weight,
  ) {
    return base?.copyWith(
      fontSize: size,
      height: height,
      letterSpacing: tracking,
      fontWeight: weight,
    );
  }

  static ThemeData build(AppPalette p) {
    final isDark = p.brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: p.onAccentStrong,
      secondary: p.accent,
      onSecondary: p.onAccentStrong,
      error: p.error,
      onError: isDark ? p.onAccent : Colors.white,
      surface: p.background,
      onSurface: p.text,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceRaised,
      onSurfaceVariant: p.textMuted,
      outline: p.outline,
      outlineVariant: p.outline,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: p.background,
      splashFactory: NoSplash.splashFactory,
    );

    final text = base.textTheme.apply(
      bodyColor: p.text,
      displayColor: p.text,
      fontFamily: fontFamily,
    );

    const radius14 = BorderRadius.all(Radius.circular(14));
    const buttonText = TextStyle(
      fontFamily: fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );

    return base.copyWith(
      // Skala typografii Geist: rozmiar, wysokość linii, odstęp liter i grubość.
      textTheme: text.copyWith(
        displayMedium: _type(
          text.displayMedium,
          48,
          1.1,
          -2.4,
          FontWeight.w600,
        ),
        displaySmall: _type(text.displaySmall, 36, 1.11, -0.9, FontWeight.w600),
        headlineLarge: _type(
          text.headlineLarge,
          30,
          1.2,
          -0.75,
          FontWeight.w600,
        ),
        headlineMedium: _type(
          text.headlineMedium,
          24,
          1.33,
          -0.6,
          FontWeight.w600,
        ),
        headlineSmall: _type(
          text.headlineSmall,
          24,
          1.33,
          -0.6,
          FontWeight.w600,
        ),
        titleLarge: _type(text.titleLarge, 18, 1.56, 0, FontWeight.w600),
        titleMedium: _type(text.titleMedium, 16, 1.5, 0, FontWeight.w600),
        titleSmall: _type(text.titleSmall, 14, 1.43, 0, FontWeight.w500),
        bodyLarge: _type(text.bodyLarge, 16, 1.5, 0, FontWeight.w400),
        bodyMedium: _type(text.bodyMedium, 14, 1.43, 0, FontWeight.w400),
        bodySmall: _type(text.bodySmall, 12, 1.33, 0, FontWeight.w400),
        labelLarge: _type(text.labelLarge, 14, 1.43, 0, FontWeight.w600),
        labelMedium: _type(text.labelMedium, 12, 1.33, 0, FontWeight.w500),
        labelSmall: _type(text.labelSmall, 12, 1.33, 0.6, FontWeight.w500),
      ),
      // Strzałka wstecz z tego samego zestawu ikon co reszta aplikacji.
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Glyph(AppIcons.arrowLeft),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      // Promień 22 = promień elementu w rogu (8) + wewnętrzny odstęp karty (14).
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          side: BorderSide(color: p.ring),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accentFill,
          foregroundColor: p.onAccent,
          disabledBackgroundColor: p.surfaceRaised,
          disabledForegroundColor: p.textDisabled,
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: radius14),
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          side: BorderSide(color: p.outline),
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: radius14),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hintStyle: TextStyle(color: p.textDisabled),
        labelStyle: TextStyle(color: p.textMuted),
        border: const OutlineInputBorder(
          borderRadius: radius14,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: BorderSide(color: p.ring),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: BorderSide(color: p.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.accentFill,
        labelStyle: TextStyle(fontFamily: fontFamily, color: p.text),
        secondaryLabelStyle: TextStyle(
          fontFamily: fontFamily,
          color: p.onAccent,
        ),
        side: BorderSide(color: p.ring),
        shape: const StadiumBorder(),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.background,
        indicatorColor: p.surfaceRaised,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected) ? p.text : p.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? p.accent
                : p.textMuted,
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
      dividerTheme: DividerThemeData(color: p.ring, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? p.surfaceRaised : p.text,
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: isDark ? p.text : p.background,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
