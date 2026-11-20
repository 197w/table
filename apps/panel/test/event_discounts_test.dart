import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
import 'package:table_panel/features/calendar/calendar_screen.dart';

MenuItem _dish(String id, String section, String name, int price) => MenuItem.fromJson({
  'id': id,
  'section_id': section,
  'name': name,
  'price_grosze': price,
  'position': 0,
});

void main() {
  test('zniżka na dział z bazy', () {
    final d = EventDiscount.fromJson({'section_id': 's1', 'percent': 25});
    expect(d.sectionId, 's1');
    expect(d.percent, 25);
  });

  testWidgets('okno wydarzenia: zniżki na sekcje (dodanie, procent, usunięcie)', (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('pl_PL');
      final loader = FontLoader('packages/table_core/Geist');
      for (final weight in ['Regular', 'Medium', 'SemiBold']) {
        loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
      }
      await loader.load();
    });
    tester.view.physicalSize = const Size(1700, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppColors.use(PanelPalette.dark);
    final sections = [
      MenuSection(id: 's1', name: 'Pizza', position: 0, items: [_dish('i1', 's1', 'Margherita', 3200)]),
      MenuSection(id: 's2', name: 'Napoje', position: 1, items: [_dish('i2', 's2', 'Cola', 900)]),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentRestaurantProvider.overrideWithValue(
            const PanelRestaurant(id: 'r1', name: 'Lokal', city: 'Białystok', isPro: true, role: StaffRole.owner),
          ),
          memberPermissionsProvider.overrideWithValue({'calendar', 'menu', 'menu_edit'}),
          menuProvider.overrideWith((ref, id) async => sections),
          calendarEventsProvider.overrideWith((ref, q) async => const <CalendarEvent>[]),
          eventDiscountsProvider.overrideWith((ref, id) async => const <EventDiscount>[]),
        ],
        child: MaterialApp(
          theme: PanelTheme.build(PanelPalette.dark),
          home: const Scaffold(body: CalendarScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nowe wydarzenie').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Zniżki na sekcje'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Bez zniżek.'), findsOneWidget);

    // Dodanie zniżki: sekcja z listy dostaje 10%.
    await tester.tap(find.text('Dodaj zniżkę na sekcję'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pizza ·').last);
    await tester.pumpAndSettle();
    expect(find.text('Bez zniżek.'), findsNothing);
    final percent = find.byWidgetPredicate((w) => w is TextField && w.controller?.text == '10');
    expect(percent, findsOneWidget);

    // Zmiana procentu i usunięcie zniżki.
    await tester.enterText(percent, '25');
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is TextField && w.controller?.text == '25'), findsOneWidget);
    await tester.tap(find.byTooltip('Usuń zniżkę'));
    await tester.pumpAndSettle();
    expect(find.text('Bez zniżek.'), findsOneWidget);
  });
}
