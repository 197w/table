import 'dart:io' show Platform;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart'
    show AdaptiveNavigationDestination, IOS26NativeTabBar, PlatformInfo;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

/// Prawdziwy, systemowy Liquid Glass jest tylko na iOS 26 i nowszym (natywne kontrolki UIKit).
/// Starszy iOS zostaje przy szklanym pasku rysowanym przez Fluttera, Android przy Material.
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
