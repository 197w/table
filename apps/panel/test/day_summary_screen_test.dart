import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/app.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
import 'package:table_panel/features/management/day_screen.dart';

DaySummary _summary({DayReport? report}) => DaySummary(
  revenueGrosze: 428000,
  orders: 57,
  dineIn: 40,
  takeaway: 17,
  cashGrosze: 112000,
  cardGrosze: 218000,
  cardOnlineGrosze: 74000,
  otherGrosze: 24000,
  cancelled: 3,
  pettyOutGrosze: 4500,
  pettyInGrosze: 20000,
  tipsCashGrosze: 6000,
  tipsCardGrosze: 9000,
  discountsGrosze: 12000,
  ordersNet: 54,
  revenueNetGrosze: 352000,
  kaucjaGrosze: 3600,
  kaucjaCount: 18,
  petty: const [],
  report: report,
);

void main() {
  test('liczba zamówień po polsku', () {
    expect(ordersWord(1), '1 zamówienie');
    expect(ordersWord(3), '3 zamówienia');
    expect(ordersWord(12), '12 zamówień');
    expect(ordersWord(57), '57 zamówień');
  });

  testWidgets('podsumowanie dnia: liczby dnia, zamówienia razem, kontrole i zapis', (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('pl_PL');
      final loader = FontLoader('packages/table_core/Geist');
      for (final weight in ['Regular', 'Medium', 'SemiBold']) {
        loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
      }
      await loader.load();
    });
    tester.view.physicalSize = const Size(1500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppColors.use(PanelPalette.dark);
    final report = DayReport(
      fiscalGrosze: 428000,
      fiscalNetGrosze: 361500,
      terminals: const [TerminalReport('Terminal sala', 150000), TerminalReport('Terminal bar', 77000)],
      cashCountedGrosze: 128000,
      updatedAt: DateTime(2026, 11, 20, 23, 40),
      updatedBy: 'Kasia',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentRestaurantProvider.overrideWithValue(
            const PanelRestaurant(id: 'r1', name: 'Lokal', city: 'Białystok', isPro: true, role: StaffRole.owner),
          ),
          daySummaryProvider.overrideWith((ref, q) async => _summary(report: report)),
          unclosedOrdersProvider.overrideWith((ref, id) async => const <UnclosedOrder>[]),
          profileProvider.overrideWith((ref, id) => Completer<RestaurantProfile>().future),
        ],
        child: MaterialApp(
          theme: PanelTheme.build(PanelPalette.dark),
          home: const Scaffold(body: DaySummaryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Zamówienia z lokalu i z dostaw są razem: 57, w tym 40 w lokalu i 17 na wynos.
    expect(find.text('57 zamówień · w lokalu 40 · na wynos 17'), findsOneWidget);
    for (final title in ['Obrót', 'Średni rachunek', 'Do koperty', 'Gotówka w kasie']) {
      expect(find.text(title), findsWidgets, reason: title);
    }
    // Kasa fiskalna i terminale zgadzają się z panelem, gotówka w kasie o 55 zł mniej.
    expect(find.text('Zgadza się'), findsNWidgets(2));
    expect(find.textContaining('Różnica'), findsOneWidget);
    expect(find.text('Jak zapłacono'), findsOneWidget);
    expect(find.text('Rozliczenie dnia'), findsOneWidget);
    expect(find.text('Zapisano 23:40 · Kasia'), findsOneWidget);

    // Zmiana kwoty oznacza niezapisane zmiany.
    final fiscal = find.byWidgetPredicate((w) => w is TextField && w.controller?.text == '4280');
    expect(fiscal, findsOneWidget);
    await tester.enterText(fiscal, '4300');
    await tester.pump();
    expect(find.text('Niezapisane zmiany'), findsOneWidget);
    expect(find.text('Zgadza się'), findsNWidgets(1));
  });
}
