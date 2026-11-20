import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
import 'package:table_panel/features/inventory/inventory_invoices.dart';

InventoryInvoice _invoice(
  String id,
  String supplier,
  String number, {
  required DateTime issued,
  DateTime? due,
  DateTime? paid,
  int gross = 100000,
}) => InventoryInvoice.fromJson({
  'id': id,
  'supplier': supplier,
  'number': number,
  'issued_on': '${issued.year}-${issued.month.toString().padLeft(2, '0')}-${issued.day.toString().padLeft(2, '0')}',
  'due_on': due == null ? null : '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}',
  'paid_on': paid == null ? null : '${paid.year}-${paid.month.toString().padLeft(2, '0')}-${paid.day.toString().padLeft(2, '0')}',
  'gross_grosze': gross,
});

void main() {
  final today = DateTime(2026, 11, 20);

  test('faktura: po terminie, ile dni do terminu, opłacona', () {
    final late = _invoice('a', 'Makro', 'FV/1', issued: DateTime(2026, 11, 1), due: DateTime(2026, 11, 17));
    expect(late.overdue(today), isTrue);
    expect(late.daysToDue(today), -3);
    expect(invoiceDueText(late, today), 'po terminie 3 dni');

    final soon = _invoice('b', 'Makro', 'FV/2', issued: DateTime(2026, 11, 15), due: DateTime(2026, 11, 25));
    expect(soon.overdue(today), isFalse);
    expect(invoiceDueText(soon, today), 'za 5 dni');
    expect(invoiceDueText(_invoice('c', 'M', 'FV/3', issued: today, due: today), today), 'termin dziś');
    expect(invoiceDueText(_invoice('d', 'M', 'FV/4', issued: today), today), 'bez terminu');

    // Opłacona nie jest po terminie, nawet po upływie terminu.
    final paid = _invoice('e', 'M', 'FV/5', issued: DateTime(2026, 11, 1), due: DateTime(2026, 11, 10), paid: DateTime(2026, 11, 9));
    expect(paid.paid, isTrue);
    expect(paid.overdue(today), isFalse);
    expect(paid.daysToDue(today), isNull);
  });

  testWidgets('zakładka Faktury: lista, filtr „Do zapłaty”, sumy i okno nowej faktury', (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('pl_PL');
      final loader = FontLoader('packages/table_core/Geist');
      for (final weight in ['Regular', 'Medium', 'SemiBold']) {
        loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
      }
      await loader.load();
    });
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppColors.use(PanelPalette.dark);
    final now = DateTime.now();
    final invoices = [
      _invoice('a', 'Makro Cash&Carry', 'FV/11/45', issued: now.subtract(const Duration(days: 20)), due: now.subtract(const Duration(days: 3)), gross: 250000),
      _invoice('b', 'Hurtownia Owoców', 'FV/12', issued: now.subtract(const Duration(days: 2)), due: now.add(const Duration(days: 12)), gross: 80050),
      _invoice('c', 'Piekarnia Zdrój', 'FV/9', issued: now.subtract(const Duration(days: 30)), due: now.subtract(const Duration(days: 16)), paid: now.subtract(const Duration(days: 17)), gross: 40000),
    ];
    var added = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryInvoicesProvider.overrideWith((ref, id) async => invoices),
          inventoryDocsProvider.overrideWith((ref, id) async => const <InventoryDoc>[]),
        ],
        child: MaterialApp(
          theme: PanelTheme.build(PanelPalette.dark),
          home: Scaffold(
            body: InventoryInvoicesTab(restaurantId: 'r1', memberId: null, onAdd: () => added++),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Makro Cash&Carry'), findsOneWidget);
    expect(find.text('FV/11/45'), findsOneWidget);
    expect(find.text('Po terminie'), findsOneWidget);
    expect(find.text('Do zapłaty'), findsOneWidget);
    expect(find.text('Opłacona'), findsOneWidget);
    expect(find.text('po terminie 3 dni'), findsOneWidget);
    // Do zapłaty: 2500,00 + 800,50 zł, z tego po terminie 2500,00 zł.
    Finder pill(String part) => find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').replaceAll(RegExp(r'[  ]'), ' ').contains(part),
    );
    expect(pill('Do zapłaty: 3 300,50'), findsOneWidget);
    expect(pill('Po terminie: 2 500,00'), findsOneWidget);

    await tester.tap(find.text('Do zapłaty (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Piekarnia Zdrój'), findsNothing);
    expect(find.text('Hurtownia Owoców'), findsOneWidget);

    await tester.tap(find.text('Opłacone (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Piekarnia Zdrój'), findsOneWidget);
    expect(find.text('Makro Cash&Carry'), findsNothing);

    // Wiersz otwiera okno faktury z jej danymi.
    await tester.tap(find.text('Piekarnia Zdrój'));
    await tester.pumpAndSettle();
    expect(find.text('Faktura FV/9'), findsOneWidget);
    expect(find.text('Dostawca'), findsWidgets);
    expect(find.text('Zapisz'), findsOneWidget);
    expect(added, 0);
  });
}
