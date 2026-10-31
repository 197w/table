import 'dart:io' show Platform;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart'
    show
        AdaptiveButton,
        AdaptiveButtonSize,
        AdaptiveButtonStyle,
        AdaptiveNavigationDestination,
        IOS26NativeTabBar,
        PlatformInfo,
        SFSymbol;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

// Liquid Glass w Table i Table for employees (10.2026). Prawdziwy, systemowy Liquid Glass jest tylko na iOS 26
// i nowszym (natywne kontrolki UIKit z adaptive_platform_ui). Starszy iOS i Android zostają przy przyciskach
// rysowanych przez Fluttera (Material), które każde miejsce podaje jako `fallback`.

/// Natywny Liquid Glass: iOS 26 i nowszy.
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

/// Okrągły przycisk z symbolem SF: na iOS 26 natywny Liquid Glass (wybrany: wypełniony kolorem akcentu),
/// gdzie indziej [fallback] (przycisk rysowany przez Fluttera).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.symbol,
    required this.label,
    required this.onTap,
    required this.fallback,
    this.color,
    this.selected = false,
    this.size = 44,
  });

  final String symbol;
  final String label;
  final VoidCallback onTap;
  final Widget fallback;

  /// Kolor symbolu (np. czerwone serce). Null: kolor systemowy.
  final Color? color;

  /// Wybrana opcja przełącznika: szkło w kolorze akcentu.
  final bool selected;

  /// Średnica szkła. Pole dotyku zawsze co najmniej 48.
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!nativeLiquidGlass) return fallback;
    final tap = size < 48 ? 48.0 : size;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: tap,
        height: tap,
        child: Center(
          child: SizedBox(
            width: size,
            height: size,
            child: AdaptiveButton.sfSymbol(
              // Natywny przycisk nie zmienia stylu po utworzeniu, więc zmiana wyglądu to nowy przycisk.
              key: ValueKey('$symbol-${color?.toARGB32()}-$selected'),
              onPressed: onTap,
              sfSymbol: SFSymbol(symbol, size: size * 0.43, color: selected ? AppColors.onAccent : color),
              style: selected ? AdaptiveButtonStyle.prominentGlass : AdaptiveButtonStyle.glass,
              color: selected ? AppColors.accentFill : null,
              useSmoothRectangleBorder: false,
              borderRadius: BorderRadius.circular(size / 2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pigułka z treścią Fluttera (ikona i napis) na natywnym szkle: filtry, przełączniki i przyciski akcji.
/// [selected] albo [prominent]: szkło w kolorze akcentu (treść w kolorze [AppColors.onAccent] podaje wywołujący).
/// Gdzie indziej [fallback].
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
  });

  final VoidCallback? onPressed;

  /// Treść pigułki (ikona i napis), rysowana przez Fluttera na szkle.
  final Widget content;
  final Widget fallback;
  final bool selected;

  /// Kolor wypełnienia wybranej pigułki. Domyślnie akcent.
  final Color? tint;
  final double height;
  final String? semanticLabel;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (!nativeLiquidGlass) return fallback;
    final button = SizedBox(
      height: height,
      child: AdaptiveButton.child(
        key: ValueKey('glass-$selected-${tint?.toARGB32()}'),
        onPressed: onPressed,
        enabled: onPressed != null,
        style: selected ? AdaptiveButtonStyle.prominentGlass : AdaptiveButtonStyle.glass,
        color: selected ? (tint ?? AppColors.accentFill) : null,
        size: height >= 44 ? AdaptiveButtonSize.large : AdaptiveButtonSize.medium,
        useSmoothRectangleBorder: false,
        borderRadius: BorderRadius.circular(height / 2),
        padding: padding,
        child: content,
      ),
    );
    if (semanticLabel == null) return button;
    return Semantics(button: true, selected: selected, label: semanticLabel, excludeSemantics: true, child: button);
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
    onTap: () => Navigator.maybePop(context),
    fallback: close ? const CloseButton() : const BackButton(),
  );
}
