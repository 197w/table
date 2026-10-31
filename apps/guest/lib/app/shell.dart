import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../core/live_activity.dart';
import '../data/providers.dart';

/// Dolna nawigacja: Odkrywaj, Rezerwacje, Konto. Na iOS 26 systemowy pasek z Liquid Glass,
/// na starszym iOS szkło rysowane przez Fluttera, na Androidzie Material. Na szerokim tablecie menu z boku.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lista rezerwacji żyje przez cały czas działania aplikacji, żeby kafel
    // na ekranie blokady pojawił się we właściwej chwili.
    ref.listen(myReservationsProvider, (_, next) {
      final list = next.value;
      if (list != null) LiveActivity.instance.sync(list);
    });
    ref.watch(myReservationsProvider);

    void select(int index) => navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);

    // iOS 26: prawdziwy Liquid Glass (natywny UITabBar), treść przewija się pod nim.
    if (nativeLiquidGlass) {
      return Scaffold(
        extendBody: true,
        body: navigationShell,
        bottomNavigationBar: NativeGlassTabBar(
          index: navigationShell.currentIndex,
          onTap: select,
          tabs: const [
            (label: 'Odkrywaj', symbol: 'safari', selectedSymbol: 'safari.fill'),
            (label: 'Rezerwacje', symbol: 'calendar', selectedSymbol: 'calendar'),
            (label: 'Konto', symbol: 'person.crop.circle', selectedSymbol: 'person.crop.circle.fill'),
          ],
        ),
      );
    }

    // Tablet poziomo (szeroko): menu z boku, treść ma całą wysokość.
    if (MediaQuery.sizeOf(context).width >= 840) {
      return Scaffold(
        body: SafeArea(
          right: false,
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: select,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.9,
                destinations: const [
                  NavigationRailDestination(
                    icon: Glyph(AppIcons.compass),
                    selectedIcon: Glyph(AppIcons.compassFill),
                    label: Text('Odkrywaj'),
                  ),
                  NavigationRailDestination(
                    icon: Glyph(AppIcons.calendarDots),
                    selectedIcon: Glyph(AppIcons.calendarDotsFill),
                    label: Text('Rezerwacje'),
                  ),
                  NavigationRailDestination(
                    icon: Glyph(AppIcons.userCircle),
                    selectedIcon: Glyph(AppIcons.userCircleFill),
                    label: Text('Konto'),
                  ),
                ],
              ),
              VerticalDivider(width: 1, color: AppColors.ring),
              Expanded(child: navigationShell),
            ],
          ),
        ),
      );
    }

    // Szklany pasek tylko na iOS i iPadOS. Android zostaje przy pełnym tle.
    final glass = Platform.isIOS;

    final bar = NavigationBar(
      backgroundColor: glass ? Colors.transparent : null,
      surfaceTintColor: glass ? Colors.transparent : null,
      elevation: glass ? 0 : null,
      shadowColor: glass ? Colors.transparent : null,
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: select,
      // Bez dymków po przytrzymaniu ikony: nazwa jest pod ikoną (dymki zostają w panelu na komputerze).
      destinations: const [
        NavigationDestination(
          icon: Glyph(AppIcons.compass),
          selectedIcon: Glyph(AppIcons.compassFill),
          label: 'Odkrywaj',
          tooltip: '',
        ),
        NavigationDestination(
          icon: Glyph(AppIcons.calendarDots),
          selectedIcon: Glyph(AppIcons.calendarDotsFill),
          label: 'Rezerwacje',
          tooltip: '',
        ),
        NavigationDestination(
          icon: Glyph(AppIcons.userCircle),
          selectedIcon: Glyph(AppIcons.userCircleFill),
          label: 'Konto',
          tooltip: '',
        ),
      ],
    );

    return Scaffold(
      // Treść przewija się pod szkłem, więc widać, że pasek nad nią leży.
      extendBody: glass,
      body: navigationShell,
      bottomNavigationBar: glass ? _GlassBar(child: bar) : bar,
    );
  }
}

/// Pasek menu jako materiał: rozmycie tego, co pod spodem, półprzezroczyste tło
/// i jasna krawędź u góry, która łapie światło.
class _GlassBar extends StatelessWidget {
  const _GlassBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: dark ? 0.62 : 0.72),
            border: Border(
              top: BorderSide(color: (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.12 : 0.08)),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
