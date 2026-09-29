import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'home_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';
import 'waiter_screens.dart';

/// Dolne menu aplikacji: Zamówienia, Zeskanuj, Grafik, Ustawienia.
class StaffShell extends ConsumerStatefulWidget {
  const StaffShell({super.key});

  @override
  ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> {
  /// Na start „Zeskanuj”: tu zaczyna się zmianę.
  int _tab = 1;

  void _go(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Zakładki trzymają stan (np. wybrany miesiąc w grafiku) przy przełączaniu.
      body: IndexedStack(
        index: _tab,
        children: [
          _OrdersTab(onScan: () => _go(1)),
          HomeScreen(onOrders: () => _go(0)),
          const ScheduleScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Glyph(AppIcons.receipt, size: 22), label: 'Zamówienia'),
          NavigationDestination(icon: Glyph(AppIcons.squaresFour, size: 22), label: 'Zeskanuj'),
          NavigationDestination(icon: Glyph(AppIcons.calendarDots, size: 22), label: 'Grafik'),
          NavigationDestination(icon: Glyph(AppIcons.gear, size: 22), label: 'Ustawienia'),
        ],
      ),
    );
  }
}

/// Zamówienia lokalu, w którym mam trwającą zmianę i uprawnienie do zamówień.
class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobsProvider).value ?? const <Job>[];
    final withOrders = jobs.where((j) => j.canTakeOrders).toList();
    final working = withOrders.where((j) => j.working).firstOrNull;
    if (working != null) return WaiterTablesScreen(job: working);

    return Scaffold(
      appBar: AppBar(title: const Text('Zamówienia')),
      body: MessageView(
        icon: AppIcons.receipt,
        title: withOrders.isEmpty ? 'Brak uprawnienia do zamówień' : 'Zamówienia po rozpoczęciu zmiany',
        message: withOrders.isEmpty
            ? 'Twoje stanowisko nie nabija zamówień. Jeśli to pomyłka, porozmawiaj z przełożonym.'
            : 'Zeskanuj kod z panelu w lokalu, żeby zacząć zmianę. Potem nabijesz tu zamówienia.',
        actionLabel: withOrders.isEmpty ? null : 'Zeskanuj kod',
        onAction: withOrders.isEmpty ? null : onScan,
      ),
    );
  }
}
