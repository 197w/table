import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart'
    show
        AdaptiveButton,
        AdaptiveButtonStyle,
        AdaptiveNavigationDestination,
        AdaptivePopupMenuButton,
        AdaptivePopupMenuDivider,
        AdaptivePopupMenuEntry,
        AdaptivePopupMenuItem,
        IOS26NativeTabBar,
        IOS26SegmentedControl,
        PlatformInfo,
        PopupButtonStyle,
        SFSymbol;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'app_icons.dart';
import 'theme.dart';
import 'widgets.dart';

// Liquid Glass w Table i Table for employees (10.2026). Prawdziwy, systemowy Liquid Glass jest tylko na iOS 26
// i nowszym (natywne kontrolki UIKit z adaptive_platform_ui). Starszy iOS i Android zostają przy przyciskach
// rysowanych przez Fluttera (Material), które każde miejsce podaje jako `fallback`.
//
// Wydajność (31.10.2026): każda klatka z natywnym widokiem na ekranie czeka na wątek główny iOS, a każdy napis
// Fluttera na natywnym szkle to osobna warstwa wielkości ekranu rysowana w każdej klatce. Kilkanaście pigułek
// i serc w przewijanej liście Odkrywaj zacinało obie aplikacje. Dlatego natywne zostały tylko kontrolki, które
// stoją w miejscu i nie mają nic z Fluttera na sobie: dolne menu, „Wstecz” i „Zamknij”, przyciski w pasku strony
// lokalu. Pigułki i serca na kartach to szkło rysowane przez Fluttera ([GlassSurface]) w tym samym stylu,
// tylko na iOS 26; serca z prawdziwym rozmyciem zdjęcia pod spodem.
//
// 8.11.2026 (prośba użytkownika: „ma wyglądać tak jak dolne menu”): natywne są też przyciski w pasku u góry
// z napisem ([GlassTextButton], np. „Dzisiaj”), przełącznik kart i listy ([GlassSegmentedIcons], natywny
// UISegmentedControl) i „Zamknij” w oknie od dołu. Zostają natywne także pod otwartym oknem, jak „Wstecz”
// (9.11.2026: podmiana na szkło Fluttera pod oknem wyglądała, jakby przyciski w tle „dziwnie się zmieniały”).
// Wyjątek: „Zamknij” w oknie przykrytym drugim oknem znika, jak dolne menu (natywny widok w przykrytym oknie psuł
// rysowanie drugiego okna, 1.11.2026).

/// Natywny Liquid Glass: iOS 26 i nowszy (też 27: `PlatformInfo` porównuje „co najmniej 26”).
bool get nativeLiquidGlass => !kIsWeb && Platform.isIOS && PlatformInfo.isIOS26OrHigher();

/// Zakładka dolnego menu: nazwa i symbol SF (zwykły i dla wybranej zakładki).
typedef GlassTab = ({String label, String symbol, String selectedSymbol});

/// Systemowy pasek zakładek iOS 26 (UITabBar z Liquid Glass). Treść przewija się pod nim
/// (`Scaffold.extendBody`). Gdy nad menu leży inna strona albo okno, pasek się chowa,
/// żeby natywny widok nie przebijał przez treść Fluttera.
class NativeGlassTabBar extends StatelessWidget {
  const NativeGlassTabBar({super.key, required this.tabs, required this.index, required this.onTap});

  final List<GlassTab> tabs;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final covered = !(ModalRoute.of(context)?.isCurrent ?? true);
    return IOS26NativeTabBar(
      destinations: [
        for (final t in tabs)
          AdaptiveNavigationDestination(icon: t.symbol, selectedIcon: t.selectedSymbol, label: t.label),
      ],
      selectedIndex: index,
      onTap: onTap,
      tint: AppColors.accent,
      hidden: covered,
    );
  }
}

/// Szkło rysowane przez Fluttera w stylu Liquid Glass: półprzezroczysta warstwa jaśniejsza u góry, jasna krawędź
/// łapiąca światło z lewego górnego rogu i miękki cień. Bez natywnego widoku i bez rozmycia (pigułki leżą zwykle
/// na jednolitym tle), więc kosztuje tyle co zwykły przycisk. [selected]: wypełnienie w kolorze akcentu.
/// [blur]: rozmycie tego, co pod spodem, dla szkła pływającego nad przewijaną treścią (np. przyciski na dole
/// strony lokalu), żeby napis był czytelny.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.circle = false,
    this.selected = false,
    this.tint,
    this.blur = false,
    bool? frosted,
  }) : frosted = frosted ?? blur;

  final Widget child;

  /// Koło zamiast pigułki.
  final bool circle;
  final bool selected;

  /// Kolor wybranego szkła. Domyślnie akcent.
  final Color? tint;
  final bool blur;

  /// Gęstsze szkło (czytelne na zdjęciu albo tekście). Domyślnie razem z [blur]; bez rozmycia np. serce na
  /// zdjęciu karty w przewijanej liście.
  final bool frosted;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.palette.brightness == Brightness.dark;
    final glass = CustomPaint(
      painter: _GlassPainter(
        circle: circle,
        dark: dark,
        tint: selected ? (tint ?? AppColors.accentFill) : null,
        frosted: frosted,
        clear: blur && !frosted,
      ),
      child: child,
    );
    if (!blur) return glass;
    // Jak systemowe szkło: to, co pod spodem, rozmyte i z mocniejszymi kolorami.
    const s = 1.5;
    const r = 0.2126 * (1 - s), g = 0.7152 * (1 - s), b = 0.0722 * (1 - s);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          inner: const ColorFilter.matrix([
            r + s, g, b, 0, 0, //
            r, g + s, b, 0, 0, //
            r, g, b + s, 0, 0, //
            0, 0, 0, 1, 0,
          ]),
        ),
        child: glass,
      ),
    );
  }
}

class _GlassPainter extends CustomPainter {
  _GlassPainter({required this.circle, required this.dark, required this.frosted, this.tint, this.clear = false});

  final bool circle;
  final bool dark;
  final Color? tint;

  /// Przejrzyste szkło nad rozmytym zdjęciem (serce na karcie): widać kolory zdjęcia.
  final bool clear;

  /// Nad rozmytą treścią: w ciemnym motywie gęstsze szkło, żeby napis był czytelny.
  final bool frosted;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = circle
        ? RRect.fromRectAndRadius(rect, Radius.circular(size.shortestSide / 2))
        : RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));
    final path = Path()..addRRect(shape);
    const white = Color(0xFFFFFFFF);

    // Cień pod szkłem (przy rozmyciu i tak przycięty).
    canvas.drawShadow(path.shift(const Offset(0, 1)), const Color(0xFF000000), dark ? 4 : 3, false);

    // Wypełnienie: jaśniejsze u góry, jak światło wpadające przez szkło.
    final t = tint;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: t != null
            ? [Color.alphaBlend(white.withValues(alpha: 0.22), t), t]
            : clear
            ? dark
                  ? [white.withValues(alpha: 0.22), white.withValues(alpha: 0.10)]
                  : [white.withValues(alpha: 0.62), white.withValues(alpha: 0.40)]
            : dark
            ? frosted
                  ? [const Color(0xCC3A3A3C), const Color(0xB82C2C2E)]
                  : [white.withValues(alpha: 0.16), white.withValues(alpha: 0.08)]
            : [white.withValues(alpha: frosted ? 0.86 : 0.94), white.withValues(alpha: frosted ? 0.7 : 0.78)],
      ).createShader(rect);
    canvas.drawRRect(shape, fill);

    // Odblask w górnej połowie.
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.5),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [white.withValues(alpha: dark || t != null ? 0.10 : 0.35), white.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.5)),
    );
    canvas.restore();

    // Krawędź: jasna z lewej u góry i prawej u dołu, prawie niewidoczna pośrodku.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          white.withValues(alpha: dark ? 0.42 : 1),
          white.withValues(alpha: dark ? 0.06 : 0.35),
          white.withValues(alpha: dark ? 0.24 : 0.85),
        ],
        stops: const [0, 0.5, 1],
      ).createShader(rect);
    canvas.drawRRect(shape.deflate(0.5), rim);

    // W jasnym motywie cienki obrys, żeby białe szkło nie znikało na jasnym tle.
    if (!dark && t == null && !clear) {
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = const Color(0x14000000),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassPainter old) =>
      old.circle != circle || old.dark != dark || old.tint != tint || old.frosted != frosted || old.clear != clear;
}

/// Okrągły przycisk na szkle. [native] (tylko w miejscach, które stoją w miejscu, np. „Wstecz” w pasku): natywny
/// Liquid Glass z symbolem SF; inaczej szkło rysowane przez Fluttera z ikoną [icon]. Poza iOS 26 [fallback].
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.symbol,
    required this.label,
    required this.onTap,
    required this.fallback,
    this.icon,
    this.native = false,
    this.color,
    this.selected = false,
    this.size = 44,
    this.iconScale = 1,
    this.frosted = false,
    this.blur = false,
  });

  /// Symbol SF dla natywnego przycisku.
  final String symbol;

  /// Ikona dla szkła rysowanego przez Fluttera. Null: [fallback].
  final AppIconData? icon;
  final String label;
  final VoidCallback onTap;
  final Widget fallback;

  /// Natywny przycisk UIKit. Tylko tam, gdzie nie przewija się z treścią i nic go nie przykrywa.
  final bool native;

  /// Kolor symbolu (np. czerwone serce). Null: kolor tekstu.
  final Color? color;

  /// Wybrana opcja przełącznika: szkło w kolorze akcentu.
  final bool selected;

  /// Średnica szkła. Pole dotyku zawsze co najmniej 48.
  final double size;

  /// Powiększenie ikony (np. „podskoczenie” serca przy polubieniu).
  final double iconScale;

  /// Gęstsze szkło na zdjęciu ([GlassSurface.frosted]).
  final bool frosted;

  /// Prawdziwe rozmycie tego, co pod spodem ([GlassSurface.blur]), np. zdjęcia pod sercem na karcie.
  final bool blur;

  @override
  Widget build(BuildContext context) {
    if (!nativeLiquidGlass) return fallback;
    final tap = size < 48 ? 48.0 : size;
    final icon = this.icon;
    if (!native && icon == null) return fallback;
    final Widget glass = native
        ? AdaptiveButton.sfSymbol(
            // Natywny przycisk nie zmienia stylu po utworzeniu, więc zmiana wyglądu to nowy przycisk.
            key: ValueKey('$symbol-${color?.toARGB32()}-$selected'),
            onPressed: onTap,
            sfSymbol: SFSymbol(symbol, size: size * 0.43, color: selected ? AppColors.onAccent : color),
            style: selected ? AdaptiveButtonStyle.prominentGlass : AdaptiveButtonStyle.glass,
            color: selected ? AppColors.accentFill : null,
            useSmoothRectangleBorder: false,
            borderRadius: BorderRadius.circular(size / 2),
          )
        : PressScale(
            onTap: onTap,
            child: GlassSurface(
              circle: true,
              selected: selected,
              frosted: frosted,
              blur: blur,
              child: Center(
                child: AnimatedScale(
                  scale: iconScale,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  child: Glyph(
                    icon!,
                    size: size * 0.45,
                    color: selected ? AppColors.onAccent : (color ?? AppColors.text),
                  ),
                ),
              ),
            ),
          );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: tap,
        height: tap,
        child: Center(child: SizedBox(width: size, height: size, child: glass)),
      ),
    );
  }
}

/// Pigułka z treścią (ikona i napis) na szkle rysowanym przez Fluttera: filtry, przełączniki i przyciski akcji.
/// [selected]: szkło w kolorze akcentu (treść w kolorze [AppColors.onAccent] podaje wywołujący).
/// Poza iOS 26 [fallback].
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.onPressed,
    required this.content,
    required this.fallback,
    this.selected = false,
    this.tint,
    this.height = 44,
    this.semanticLabel,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.blur = false,
  });

  final VoidCallback? onPressed;

  /// Pływa nad przewijaną treścią: rozmycie pod szkłem ([GlassSurface.blur]).
  final bool blur;

  /// Treść pigułki (ikona i napis).
  final Widget content;
  final Widget fallback;
  final bool selected;

  /// Kolor wybranej pigułki. Domyślnie akcent.
  final Color? tint;
  final double height;
  final String? semanticLabel;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (!nativeLiquidGlass) return fallback;
    final pill = PressScale(
      onTap: onPressed,
      child: SizedBox(
        height: height,
        child: GlassSurface(
          selected: selected,
          tint: tint,
          blur: blur,
          child: Padding(
            padding: padding,
            child: Center(widthFactor: 1, child: content),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      // Wysokość pigułki zawsze [height], na środku wyższego rzędu (np. 48 dp pola dotyku); szerokość jak u rodzica.
      child: UnconstrainedBox(
        constrainedAxis: Axis.horizontal,
        child: Opacity(opacity: onPressed == null ? 0.5 : 1, child: pill),
      ),
    );
  }
}

/// „Wstecz” albo „Zamknij” w pasku u góry: na iOS 26 natywny przycisk Liquid Glass. Null (zwykły przycisk paska
/// albo nic, gdy nie ma dokąd wrócić) na innych systemach i na pierwszym ekranie zakładki.
/// Użycie: `AppBar(leading: glassLeading(context), …)`.
Widget? glassLeading(BuildContext context) {
  if (!nativeLiquidGlass) return null;
  final route = ModalRoute.of(context);
  if (route == null || !route.impliesAppBarDismissal) return null;
  final close = route is PageRoute && route.fullscreenDialog;
  return GlassIconButton(
    symbol: close ? 'xmark' : 'chevron.left',
    label: close ? 'Zamknij' : 'Wstecz',
    native: true,
    onTap: () => Navigator.maybePop(context),
    fallback: close ? const CloseButton() : const BackButton(),
  );
}

/// Przycisk z napisem w pasku u góry (np. „Dzisiaj”): na iOS 26 i nowszym natywny Liquid Glass z napisem UIKit,
/// jak „Wstecz”, także pod otwartym oknem. Poza iOS 26 [fallback].
class GlassTextButton extends StatelessWidget {
  const GlassTextButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.fallback,
    this.semanticLabel,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Widget fallback;
  final String? semanticLabel;

  /// Kolor napisu. Null: kolor tekstu.
  final Color? color;

  static const _style = TextStyle(fontSize: 17, fontWeight: FontWeight.w500);

  @override
  Widget build(BuildContext context) {
    if (!nativeLiquidGlass) return fallback;
    final painter = TextPainter(
      text: TextSpan(text: label, style: _style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final width = painter.width + 36;
    painter.dispose();
    final glass = AdaptiveButton(
      // Natywny przycisk nie zmienia stylu po utworzeniu, więc zmiana koloru to nowy przycisk.
      key: ValueKey('glass-text-${color?.toARGB32()}'),
      onPressed: onTap,
      label: label,
      style: AdaptiveButtonStyle.glass,
      textColor: color ?? AppColors.text,
      useSmoothRectangleBorder: false,
      borderRadius: BorderRadius.circular(22),
    );
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: 48,
        child: Center(child: SizedBox(width: width, height: 44, child: glass)),
      ),
    );
  }
}

/// Przełącznik ikon jak dolne menu (np. karty / lista): na iOS 26 i nowszym natywny UISegmentedControl z Liquid
/// Glass i symbolami SF, także pod otwartym oknem. Poza iOS 26 [fallback].
class GlassSegmentedIcons extends StatelessWidget {
  const GlassSegmentedIcons({
    super.key,
    required this.symbols,
    required this.icons,
    required this.labels,
    required this.selected,
    required this.onChanged,
    required this.fallback,
  });

  final List<String> symbols;

  /// Ikony dla czytnika ekranu i miejsc bez natywnego widoku (zostają w API dla [fallback]).
  final List<AppIconData> icons;

  /// Nazwy opcji dla czytnika ekranu.
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final Widget fallback;

  static const double _segment = 50;
  static const double _height = 40;

  @override
  Widget build(BuildContext context) {
    if (!nativeLiquidGlass) return fallback;
    return SizedBox(
      width: _segment * symbols.length,
      height: 48,
      child: Center(
        child: IOS26SegmentedControl(
          labels: labels,
          icons: symbols,
          selectedIndex: selected,
          onValueChanged: onChanged,
          height: _height,
          iconSize: 17,
          iconColor: AppColors.text,
        ),
      ),
    );
  }
}

/// Opcja w [GlassMenuButton]: nazwa, symbol SF (natywne menu), ikona (gdzie indziej), wybrana (ptaszek)
/// i kreska przed nią.
typedef GlassMenuItem = ({String label, String symbol, AppIconData icon, bool selected, bool dividerBefore});

/// Okrągły przycisk z menu, np. widok Kalendarza jak w Apple Calendar: na iOS 26 i nowszym natywny przycisk
/// Liquid Glass z menu UIKit (ptaszek przy wybranej opcji, kreski między grupami). Poza iOS 26 [fallback].
class GlassMenuButton extends StatelessWidget {
  const GlassMenuButton({
    super.key,
    required this.symbol,
    required this.items,
    required this.onSelected,
    required this.fallback,
  });

  /// Symbol SF na przycisku.
  final String symbol;
  final List<GlassMenuItem> items;

  /// Numer wybranej opcji w [items].
  final ValueChanged<int> onSelected;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    if (!nativeLiquidGlass) return fallback;
    final entries = <AdaptivePopupMenuEntry>[
      for (final (i, item) in items.indexed) ...[
        if (item.dividerBefore) const AdaptivePopupMenuDivider(),
        AdaptivePopupMenuItem<int>(label: item.label, icon: item.symbol, selected: item.selected, value: i),
      ],
    ];
    return SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: AdaptivePopupMenuButton.icon<int>(
          // Natywny przycisk i menu powstają od nowa przy zmianie symbolu albo wybranej opcji.
          key: ValueKey('glass-menu-$symbol-${items.map((e) => e.selected ? 1 : 0).join()}'),
          icon: symbol,
          items: entries,
          onSelected: (_, entry) {
            final value = entry.value;
            if (value != null) onSelected(value);
          },
          tint: AppColors.text,
          size: 44,
          iconSize: 18,
          buttonStyle: PopupButtonStyle.glass,
        ),
      ),
    );
  }
}
