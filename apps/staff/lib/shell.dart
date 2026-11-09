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

/// Dolne menu aplikacji: Zamówienia, Dostawy, Zeskanuj, Kalendarz (dawniej Grafik), Konto. Na iOS 26 systemowy pasek
/// z Liquid Glass, gdzie indziej Material.
class StaffShell extends ConsumerStatefulWidget {
  const StaffShell({super.key});

  @override
  ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> {
  /// Na start „Zeskanuj”: tu zaczyna się zmianę. Po zmianie motywu (aplikacja buduje się od nowa) ta sama zakładka.
  static int _lastTab = 2;
  int _tab = _lastTab;

  void _go(int tab) => setState(() => _tab = _lastTab = tab);

  StreamSubscription<CarConnection>? _car;
  CarConnection _connection = CarConnection.none;

  /// Dostawca na zmianie: co 2 minuty sprawdzamy, czy zmiana trwa.
  Timer? _jobsCheck;

  @override
  void initState() {
    super.initState();
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
    _jobsCheck?.cancel();
    _car?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Zakładki trzymają stan (np. wybrany miesiąc w grafiku) przy przełączaniu.
    final body = IndexedStack(
      index: _tab,
      children: [
        _OrdersTab(onScan: () => _go(2)),
        DeliveriesTab(onScan: () => _go(2)),
        HomeScreen(onOrders: () => _go(0)),
        const ScheduleScreen(),
        const SettingsScreen(),
      ],
    );
    // iOS 26: prawdziwy Liquid Glass (natywny UITabBar), treść przewija się pod nim.
    if (nativeLiquidGlass) {
      return Scaffold(
        extendBody: true,
        body: body,
        bottomNavigationBar: NativeGlassTabBar(
          index: _tab,
          onTap: _go,
          tabs: const [
            (label: 'Zamówienia', symbol: 'list.bullet.rectangle', selectedSymbol: 'list.bullet.rectangle.fill'),
            (label: 'Dostawy', symbol: 'scooter', selectedSymbol: 'scooter'),
            (label: 'Zeskanuj', symbol: 'qrcode.viewfinder', selectedSymbol: 'qrcode.viewfinder'),
            (label: 'Kalendarz', symbol: 'calendar', selectedSymbol: 'calendar'),
            (label: 'Konto', symbol: 'person.crop.circle', selectedSymbol: 'person.crop.circle.fill'),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
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
                (AppIcons.calendarDots, 'Kalendarz'),
                (AppIcons.userCircle, 'Konto'),
              ])
                NavigationDestination(
                  icon: Glyph(icon, size: 22),
                  selectedIcon: Glyph(icon.duotone, size: 22),
                  label: label,
                  // Bez dymków po przytrzymaniu: nazwa jest pod ikoną (dymki tylko w panelu na komputerze).
                  tooltip: '',
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
      appBar: AppBar(leading: glassLeading(context), title: const Text('Zamówienia')),
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
