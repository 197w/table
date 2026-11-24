import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/features/inventory/inventory_docs.dart';

void main() {
  testWidgets('dostawa: luzem w dwóch polach (kilogramy i gramy), suma się przelicza', (tester) async {
    await tester.runAsync(() async {
      final loader = FontLoader('packages/table_core/Geist');
      for (final weight in ['Regular', 'Medium', 'SemiBold']) {
        loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
      }
      await loader.load();
    });
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppColors.use(PanelPalette.dark);
    final flour = InventoryItem.fromJson({
      'id': 'i1',
      'name': 'Mąka',
      'unit': 'kg',
      'capacity': 50,
      'sort': 1,
      'pack_name': 'worek',
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: PanelTheme.build(PanelPalette.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => InventoryDocDialog(restaurantId: 'r', delivery: true, items: [flour], memberId: null),
                ),
                child: const Text('Otwórz'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Otwórz'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mąka').last);
    await tester.pumpAndSettle();

    final packages = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'pełne op.');
    final loose = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'luzem');
    // Dwa pola luzem: kilogramy po lewej, gramy po prawej.
    expect(loose, findsNWidgets(2));
    expect(find.text('kg'), findsOneWidget);
    expect(find.text('g'), findsOneWidget);
    await tester.enterText(packages, '1');
    await tester.enterText(loose.first, '1');
    await tester.enterText(loose.last, '500');
    await tester.pump();
    // 50 kg w opakowaniu + 1 kg + 500 g = 51,5 kg.
    final totals = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().where((t) => t.startsWith('=')).toList();
    expect(totals, ['= 51,5 kg']);
    // Same gramy, bez kilogramów.
    await tester.enterText(loose.first, '');
    await tester.pump();
    final grams = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().where((t) => t.startsWith('=')).toList();
    expect(grams, ['= 50,5 kg']);
  });
}
