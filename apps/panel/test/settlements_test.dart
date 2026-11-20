import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/app.dart';
import 'package:table_panel/app/sections.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
import 'package:table_panel/features/management/settlements_screen.dart';

SettlementOrder _order(
  String id,
  int number, {
  String? course,
  String choice = 'cash',
  int total = 5000,
  bool delivered = true,
  String? courier = 'm1',
  String? courierName = 'Marek',
  String? vehicle = 'Fiat Punto',
  String? plate = 'BI 12345',
  DateTime? at,
  String? address,
}) => SettlementOrder.fromJson({
  'id': id,
  'number': number,
  'course_id': course,
  'fulfillment': delivered ? 'delivered' : 'on_the_way',
  'at': (at ?? DateTime(2026, 11, 20, 18)).toUtc().toIso8601String(),
  'delivery_address': address ?? 'Lipowa $number, Białystok',
  'customer_name': 'Klient $number',
  'payment_choice': choice,
  'total_grosze': total,
  'courier_member': courier,
  'courier_name': courierName,
  'vehicle_name': vehicle,
  'vehicle_plate': plate,
});

void main() {
  group('rozliczenia dostawców: kursy', () {
    test('zamówienia z jednym kursem to jeden wiersz, zamówienie bez kursu to osobny kurs', () {
      final runs = CourierRun.group([
        _order('a', 12, course: 'k1', choice: 'cash', total: 4000, at: DateTime(2026, 11, 20, 19)),
        _order('b', 11, course: 'k1', choice: 'card_online', total: 6000, at: DateTime(2026, 11, 20, 18, 50)),
        _order('c', 9, choice: 'prepaid', total: 3000, at: DateTime(2026, 11, 20, 12)),
      ]);
      expect(runs.length, 2);
      // Najnowszy kurs pierwszy, zamówienia kursu od najmniejszego numeru.
      expect(runs.first.orders.map((o) => o.number), [11, 12]);
      expect(runs.first.totalGrosze, 10000);
      expect(runs.first.vehicleLabel, 'Fiat Punto · BI 12345');
      expect(runs.last.orders.single.number, 9);
    });

    test('opłacone: karta online i opłacone z góry; gotówka i karta przy odbiorze to nieopłacone', () {
      expect(_order('a', 1, choice: 'card_online').paid, isTrue);
      expect(_order('a', 1, choice: 'prepaid').paid, isTrue);
      expect(_order('a', 1, choice: 'cash').paid, isFalse);
      expect(_order('a', 1, choice: 'card_on_delivery').paid, isFalse);
      expect(_order('a', 1, choice: 'cash').paymentLabel, 'Gotówka u dostawcy');
      expect(_order('a', 1, choice: 'card_on_delivery').paymentLabel, 'Karta u dostawcy');
      expect(_order('a', 1, choice: 'cash').paymentShort, 'Gotówka');
      // Kurs z jednym nieopłaconym zamówieniem jest nieopłacony (dostawca ma coś do rozliczenia).
      final mixed = CourierRun.group([
        _order('a', 1, course: 'k', choice: 'card_online'),
        _order('b', 2, course: 'k', choice: 'cash'),
      ]).single;
      expect(mixed.paid, isFalse);
    });

    test('filtry: dostawca, opłacenie i wyszukiwanie; sumy opłaconych i nieopłaconych', () {
      final runs = CourierRun.group([
        _order('a', 1, choice: 'card_online', total: 7000),
        _order('b', 2, choice: 'cash', total: 3000, courier: 'm2', courierName: 'Ola', vehicle: null, plate: null),
        _order('c', 3, choice: 'prepaid', total: 2000, courier: null, courierName: null, vehicle: null, plate: null),
      ]);
      expect(filterRuns(runs).length, 3);
      expect(filterRuns(runs, couriers: {'m1'}).single.orders.single.number, 1);
      expect(filterRuns(runs, couriers: {'-'}).single.orders.single.number, 3);
      expect(filterRuns(runs, paid: {false}).single.orders.single.number, 2);
      expect(filterRuns(runs, query: '#2').single.orders.single.number, 2);
      expect(filterRuns(runs, query: 'ola').single.orders.single.number, 2);
      expect(filterRuns(runs, query: 'lipowa 3').single.orders.single.number, 3);
      final totals = settlementTotals(runs);
      expect(totals.paidGrosze, 9000);
      expect(totals.paidRuns, 2);
      expect(totals.unpaidGrosze, 3000);
      expect(totals.unpaidRuns, 1);
      expect(totals.orders, 3);
    });

    test('okresy: dziś, 7 dni, ten i poprzedni miesiąc', () {
      final today = DateTime(2026, 11, 20);
      expect(SettlementPeriod.today.range(today), (today, today));
      expect(SettlementPeriod.week.range(today), (DateTime(2026, 11, 14), today));
      expect(SettlementPeriod.month.range(today), (DateTime(2026, 11), today));
      expect(SettlementPeriod.lastMonth.range(today), (DateTime(2026, 10), DateTime(2026, 10, 31)));
      expect(SettlementPeriod.lastMonth.range(DateTime(2026, 1, 5)), (DateTime(2025, 12), DateTime(2025, 12, 31)));
    });

    test('zakładka w Managemencie, uprawnienie Podsumowanie dnia', () {
      expect(canOpenRoute(PanelRoutes.settlements, const {'day_close'}), isTrue);
      expect(canOpenRoute(PanelRoutes.settlements, const {'orders'}), isFalse);
      expect(PanelSection.forRoute(PanelRoutes.settlements), PanelSection.management);
      expect(panelTabLabels[PanelRoutes.settlements], 'Rozliczenia dostawców');
    });
  });

  testWidgets('ekran: tabela kursów, filtr dostawcy i suma opłaconych na dole', (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('pl_PL');
      final loader = FontLoader('packages/table_core/Geist');
      for (final weight in ['Regular', 'Medium', 'SemiBold']) {
        loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
      }
      await loader.load();
    });
    tester.view.physicalSize = const Size(1500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppColors.use(PanelPalette.dark);
    final orders = [
      _order('a', 11, course: 'k1', choice: 'card_online', total: 6000, at: DateTime(2026, 11, 20, 18, 50)),
      _order('b', 12, course: 'k1', choice: 'cash', total: 4000, at: DateTime(2026, 11, 20, 19)),
      _order('c', 9, choice: 'prepaid', total: 3000, courier: 'm2', courierName: 'Ola', vehicle: 'Skuter', plate: null),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentRestaurantProvider.overrideWithValue(
            const PanelRestaurant(id: 'r1', name: 'Lokal', city: 'Białystok', isPro: true, role: StaffRole.owner),
          ),
          courierSettlementsProvider.overrideWith((ref, q) async => orders),
        ],
        child: MaterialApp(
          theme: PanelTheme.build(PanelPalette.dark),
          home: const Scaffold(body: SettlementsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tabela: numery, adresy, dostawcy, auta i płatność.
    expect(find.text('#11 · Klient 11'), findsOneWidget);
    expect(find.text('#12 · Klient 12'), findsOneWidget);
    expect(find.text('Lipowa 11, Białystok'), findsOneWidget);
    expect(find.text('Fiat Punto · BI 12345'), findsOneWidget);
    expect(find.text('Skuter'), findsOneWidget);
    expect(find.text('Nieopłacone'), findsOneWidget);
    expect(find.text('Opłacone'), findsNWidgets(2));
    // Opłacone: prepaid (30 zł) nie liczy kursu z gotówką; kurs k1 jest nieopłacony (gotówka u dostawcy).
    expect(find.text('Suma kursów opłaconych'), findsOneWidget);
    expect(find.textContaining('30,00'), findsWidgets);

    // Filtr po dostawcy: sama Ola, jej kurs jest opłacony.
    await tester.tap(find.text('Ola (1)'));
    await tester.pumpAndSettle();
    expect(find.text('#11 · Klient 11'), findsNothing);
    expect(find.text('#9 · Klient 9'), findsOneWidget);
  });
}
