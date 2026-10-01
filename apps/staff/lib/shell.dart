import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_car/table_car.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'deliveries_screen.dart';
import 'home_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';
import 'waiter_screens.dart';

/// Dolne menu aplikacji: Zamówienia, Dostawy, Zeskanuj, Grafik, Ustawienia.
class StaffShell extends ConsumerStatefulWidget {
  const StaffShell({super.key});

  @override
  ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> {
  /// Na start „Zeskanuj”: tu zaczyna się zmianę.
  int _tab = 2;

  void _go(int tab) => setState(() => _tab = tab);

  StreamSubscription<CarConnection>? _car;
  CarConnection _connection = CarConnection.none;

  @override
  void initState() {
    super.initState();
    // Automatyczne rozpoznanie samochodu: po podłączeniu do Android Auto albo CarPlay
    // dostawca od razu widzi zakładkę „Dostawy”, a kurs jest na ekranie auta.
    _car = TableCar.connection.listen((connection) {
      if (!mounted || connection == _connection) return;
      final was = _connection;
      _connection = connection;
      if (connection == CarConnection.none) {
        if (was != CarConnection.none) showMessage(context, 'Odłączono od samochodu.');
        return;
      }
      final courier = (ref.read(jobsProvider).value ?? const <Job>[]).any((j) => j.permissions.contains('deliveries'));
      if (!courier) return;
      HapticFeedback.mediumImpact();
      _go(1);
      showMessage(
        context,
        'Kurs jest na ekranie samochodu. „Nawiguj” prowadzi do adresu.',
        title: connection == CarConnection.carPlay ? 'Połączono z CarPlay' : 'Połączono z Android Auto',
        tone: ToastTone.success,
        icon: AppIcons.moped,
      );
    });
  }

  @override
  void dispose() {
    _car?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Zakładki trzymają stan (np. wybrany miesiąc w grafiku) przy przełączaniu.
      body: IndexedStack(
        index: _tab,
        children: [
          _OrdersTab(onScan: () => _go(2)),
          DeliveriesTab(onScan: () => _go(2)),
          HomeScreen(onOrders: () => _go(0)),
          const ScheduleScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: [
          // Wybrana zakładka ma ikonę z wypełnieniem (duotone).
          for (final (icon, label) in const [
            (AppIcons.receipt, 'Zamówienia'),
            (AppIcons.moped, 'Dostawy'),
            (AppIcons.qrCode, 'Zeskanuj'),
            (AppIcons.calendarDots, 'Grafik'),
            (AppIcons.gear, 'Ustawienia'),
          ])
            NavigationDestination(
              icon: Glyph(icon, size: 22),
              selectedIcon: Glyph(icon.duotone, size: 22),
              label: label,
            ),
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
            : 'Zeskanuj kod w lokalu, żeby zacząć zmianę. Potem nabijesz tu zamówienia.',
        actionLabel: withOrders.isEmpty ? null : 'Zeskanuj kod',
        onAction: withOrders.isEmpty ? null : onScan,
      ),
    );
  }
}
