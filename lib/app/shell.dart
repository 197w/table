import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../shared/app_icons.dart';

/// Dolna nawigacja: Odkrywaj, Rezerwacje, Ustawienia.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
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
      ),
    );
  }
}
