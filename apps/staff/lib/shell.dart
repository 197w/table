import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_car/table_car.dart';
import 'package:table_core/table_core.dart';

import 'courier_location.dart';
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

class _StaffShellState extends ConsumerState<StaffShell> with WidgetsBindingObserver {
  /// Na start „Zeskanuj”: tu zaczyna się zmianę.
  int _tab = 2;

  void _go(int tab) => setState(() => _tab = tab);

  StreamSubscription<CarConnection>? _car;
  CarConnection _connection = CarConnection.none;

  /// Dostawca na zmianie: co 2 minuty sprawdzamy, czy zmiana trwa i czy lokal nadal wymaga lokalizacji.
  Timer? _jobsCheck;

  /// Zapamiętany przy starcie, bo po wylogowaniu (zamknięcie tego ekranu) wysyłanie ma się skończyć.
  late final CourierTracker _tracker = ref.read(courierTrackerProvider);

  /// Lokalizacja przez całą zmianę: dostawca w pracy w lokalu, który jej wymaga.
  void _syncLocation(List<Job> jobs) {
    final job = jobs.where((j) => j.sharesLocation).firstOrNull;
    _tracker.shift(job?.memberId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Powrót z ustawień telefonu: może jest już zgoda albo włączona lokalizacja.
    if (state != AppLifecycleState.resumed) return;
    final share = _tracker.state.value;
    if (share == ShareState.noPermission || share == ShareState.serviceOff) _tracker.retry();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(jobsProvider, (_, next) {
      if (next.value case final jobs?) _syncLocation(jobs);
    }, fireImmediately: true);
    _jobsCheck = Timer.periodic(const Duration(minutes: 2), (_) {
      final jobs = ref.read(jobsProvider).value ?? const <Job>[];
      if (jobs.any((j) => j.working && j.isCourier)) ref.invalidate(jobsProvider);
    });
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
    WidgetsBinding.instance.removeObserver(this);
    _jobsCheck?.cancel();
    _tracker.stop();
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
      // Napisy w jednej linii: mniejsze i bez powiększania czcionki z ustawień telefonu.
      bottomNavigationBar: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1,
        child: NavigationBarTheme(
          data: NavigationBarTheme.of(context).copyWith(
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: states.contains(WidgetState.selected) ? AppColors.text : AppColors.textMuted,
              ),
            ),
          ),
          child: NavigationBar(
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
        ),
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
