import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
import 'package:table_panel/features/inventory/inventory_screen.dart';

void main() {
  testWidgets('spis: luzem w dwóch kolumnach, kilogramy po lewej i gramy po prawej, sztuki tylko po prawej', (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('pl_PL');
      final loader = FontLoader('packages/table_core/Geist');
      for (final weight in ['Regular', 'Medium', 'SemiBold']) {
        loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
      }
      await loader.load();
    });
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppColors.use(PanelPalette.dark);
    final items = [
      InventoryItem.fromJson({'id': 'm', 'name': 'Mąka', 'unit': 'kg', 'capacity': 50, 'sort': 1, 'pack_name': 'worek'}),
      InventoryItem.fromJson({'id': 'w', 'name': 'Woda', 'unit': 'l', 'capacity': 9, 'sort': 2, 'pack_name': 'zgrzewka'}),
      InventoryItem.fromJson({'id': 'j', 'name': 'Jajka', 'unit': 'szt', 'capacity': 30, 'sort': 3, 'pack_name': 'tacka'}),
    ];
    final count = InventoryCount.fromJson({
      'id': 'c1',
      'started_at': '2026-11-24T08:00:00Z',
      'lines': [
        {'item_id': 'm', 'name': 'Mąka', 'unit': 'kg', 'capacity': 50, 'quantity': 51.5, 'packages': 1, 'loose': 1500},
      ],
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentRestaurantProvider.overrideWithValue(
            const PanelRestaurant(id: 'r1', name: 'Lokal', city: 'Białystok', isPro: true, role: StaffRole.owner),
          ),
          memberPermissionsProvider.overrideWithValue({'inventory_edit', 'inventory_count'}),
          inventoryItemsProvider.overrideWith((ref, id) async => items),
          inventoryStockProvider.overrideWith((ref, id) async => const <InventoryStock>[]),
          inventoryContainersProvider.overrideWith((ref, id) async => const <InventoryContainer>[]),
          inventoryCountsProvider.overrideWith((ref, id) async => [count]),
          profileProvider.overrideWith((ref, id) async => throw StateError('bez profilu')),
        ],
        child: MaterialApp(
          theme: PanelTheme.build(PanelPalette.dark),
          home: const Scaffold(body: InventoryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Dwie kolumny luzem w nagłówku.
    expect(find.text('Luzem: kg, l'), findsOneWidget);
    expect(find.text('Luzem: g, ml'), findsOneWidget);
    // Mąka z zapisanym 1500 g pokazuje 1 kg i 500 g.
    TextField field(String text) => tester.widget<TextField>(find.byWidgetPredicate((w) => w is TextField && w.controller?.text == text).first);
    expect(field('1').decoration?.suffixText, isNotNull);
    expect(find.byWidgetPredicate((w) => w is TextField && w.decoration?.suffixText == 'kg'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is TextField && w.decoration?.suffixText == 'l'), findsOneWidget);
    // Gramy, mililitry i sztuki są w prawej kolumnie.
    expect(find.byWidgetPredicate((w) => w is TextField && w.decoration?.suffixText == 'g'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is TextField && w.decoration?.suffixText == 'ml'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is TextField && w.decoration?.suffixText == 'szt.'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is TextField && w.controller?.text == '500'), findsOneWidget);
    // Wpisanie samych gramów i kilogramów liczy razem: 1 worek (50 kg) + 2 kg + 250 g.
    expect(find.text('51,5 kg'), findsOneWidget);
  });
}
