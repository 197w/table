import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../core/live_activity.dart';
import '../data/providers.dart';

/// Dolna nawigacja: Odkrywaj, Rezerwacje, Ustawienia.
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

    // Szklany pasek tylko na iOS i iPadOS. Android zostaje przy pełnym tle.
    final glass = Platform.isIOS;

    final bar = NavigationBar(
      backgroundColor: glass ? Colors.transparent : null,
      surfaceTintColor: glass ? Colors.transparent : null,
      elevation: glass ? 0 : null,
      shadowColor: glass ? Colors.transparent : null,
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      ),
      destinations: const [
        NavigationDestination(
          icon: Glyph(AppIcons.compass),
          selectedIcon: Glyph(AppIcons.compassFill),
          label: 'Odkrywaj',
        ),
        NavigationDestination(
          icon: Glyph(AppIcons.calendarDots),
          selectedIcon: Glyph(AppIcons.calendarDotsFill),
          label: 'Rezerwacje',
        ),
        NavigationDestination(
          icon: Glyph(AppIcons.gear),
          selectedIcon: Glyph(AppIcons.gearFill),
          label: 'Ustawienia',
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
              top: BorderSide(
                color: (dark ? Colors.white : Colors.black).withValues(
                  alpha: dark ? 0.12 : 0.08,
                ),
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
