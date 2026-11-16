import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
import 'package:table_panel/features/menu/menu_screen.dart';

MenuItem _dish(String id, String section, String name, {bool available = true, int price = 3200, int position = 0}) =>
    MenuItem(
      id: id,
      sectionId: section,
      name: name,
      priceGrosze: price,
      allergens: const ['gluten'],
      position: position,
      available: available,
    );

void main() {
  group('okres sezonu', () {
    test('jednorazowy okres: dni włącznie, poza nim nie', () {
      final s = MenuSeason(from: DateTime(2026, 12, 1), to: DateTime(2027, 1, 6));
      expect(s.contains(DateTime(2026, 12, 1)), isTrue);
      expect(s.contains(DateTime(2027, 1, 6, 23, 59)), isTrue);
      expect(s.contains(DateTime(2026, 11, 30, 23, 59)), isFalse);
      expect(s.contains(DateTime(2027, 1, 7)), isFalse);
      // Inny rok bez „co roku”: nie.
      expect(s.contains(DateTime(2027, 12, 20)), isFalse);
      expect(s.startsAfter(DateTime(2026, 11, 16)), isTrue);
      expect(s.endedBefore(DateTime(2027, 2, 1)), isTrue);
      expect(s.statusAt(DateTime(2026, 11, 16)), 'Od 1 gru');
      expect(s.statusAt(DateTime(2026, 12, 24)), 'W menu teraz');
      expect(s.statusAt(DateTime(2027, 2, 1)), 'Zakończony');
    });

    test('co roku: liczy się miesiąc i dzień, okres przechodzi przez Nowy Rok', () {
      final christmas = MenuSeason(from: DateTime(2026, 12, 1), to: DateTime(2027, 1, 6), yearly: true);
      expect(christmas.contains(DateTime(2031, 12, 24)), isTrue);
      expect(christmas.contains(DateTime(2031, 1, 3)), isTrue);
      expect(christmas.contains(DateTime(2031, 7, 15)), isFalse);
      expect(christmas.contains(DateTime(2031, 1, 7)), isFalse);
      expect(christmas.statusAt(DateTime(2031, 7, 15)), 'Poza sezonem');
      expect(christmas.endedBefore(DateTime(2031, 7, 15)), isFalse);

      final summer = MenuSeason(from: DateTime(2026, 6, 1), to: DateTime(2026, 8, 31), yearly: true);
      expect(summer.contains(DateTime(2030, 6, 1)), isTrue);
      expect(summer.contains(DateTime(2030, 8, 31, 22)), isTrue);
      expect(summer.contains(DateTime(2030, 9, 1)), isFalse);
    });

    test('gotowe okresy: zima obejmuje 29 lutego, lato kończy się z sierpniem', () {
      final winter = menuSeasonPresets.firstWhere((p) => p.name == 'Zima').season();
      expect(winter.yearly, isTrue);
      expect(winter.contains(DateTime(2028, 2, 29)), isTrue);
      expect(winter.contains(DateTime(2027, 2, 28)), isTrue);
      expect(winter.contains(DateTime(2027, 3, 1)), isFalse);
      expect(winter.contains(DateTime(2027, 12, 1)), isTrue);
      expect(menuSeasonPresets.map((p) => p.name), ['Wiosna', 'Lato', 'Jesień', 'Zima', 'Święta']);
      // Każdy dzień roku należy do dokładnie jednej pory roku.
      for (var day = DateTime(2028, 1, 1); day.year == 2028; day = day.add(const Duration(days: 1))) {
        final hits = [
          for (final p in menuSeasonPresets.take(4))
            if (p.season().contains(day)) p.name,
        ];
        expect(hits.length, 1, reason: '$day: $hits');
      }
    });

    test('z kolumn bazy i z powrotem, opis okresu', () {
      final s = MenuSeason.fromJson({'season_from': '2026-12-01', 'season_to': '2027-01-06', 'season_yearly': true})!;
      expect(s.from, DateTime(2026, 12, 1));
      expect(s.to, DateTime(2027, 1, 6));
      expect(s.label, '1 gru – 6 sty, co roku');
      expect(MenuSeason.dbDay(s.to), '2027-01-06');
      expect(MenuSeason(from: DateTime(2026, 6, 1), to: DateTime(2026, 8, 31)).label, '1 cze – 31 sie 2026');
      expect(MenuSeason(from: DateTime(2026, 12, 1), to: DateTime(2027, 1, 6)).label, '1 gru 2026 – 6 sty 2027');
      expect(MenuSeason.fromJson({'season_from': null, 'season_to': null}), isNull);
      expect(MenuSeason.fromJson({'season_from': '2026-12-01', 'season_to': null}), isNull);
    });

    test('dział w menu: zwykły zawsze, sezonowy w okresie, na wydarzenie w jego czasie', () {
      MenuSection section(Map<String, dynamic> extra) => MenuSection.fromJson({
        'id': 's',
        'name': 'Dział',
        'position': 0,
        'menu_items': const [],
        ...extra,
      });
      final always = section({});
      final seasonal = section({'season_from': '2026-12-01', 'season_to': '2027-01-06', 'season_yearly': true});
      final event = section({
        'event_id': 'e1',
        'event': {'title': 'Wieczór', 'starts_at': '2026-11-20T17:00:00Z', 'ends_at': '2026-11-20T21:00:00Z'},
      });
      expect(always.visibleAt(DateTime(2026, 7, 1)), isTrue);
      expect(seasonal.season, isNotNull);
      expect(seasonal.visibleAt(DateTime(2026, 12, 24)), isTrue);
      expect(seasonal.visibleAt(DateTime(2027, 7, 1)), isFalse);
      expect(menuWhenOf(always), MenuWhen.always);
      expect(menuWhenOf(seasonal), MenuWhen.season);
      expect(menuWhenOf(event), MenuWhen.event);
      expect(event.visibleAt(DateTime.utc(2026, 11, 20, 18)), isTrue);
      expect(event.visibleAt(DateTime.utc(2026, 11, 21)), isFalse);
    });
  });

  group('ekran Menu', () {
    final sections = [
      MenuSection(
        id: 's1',
        name: 'Dania główne',
        position: 0,
        items: [_dish('i1', 's1', 'Pierogi ruskie'), _dish('i2', 's1', 'Schabowy', available: false, position: 1)],
      ),
      MenuSection(
        id: 's2',
        name: 'Menu letnie',
        position: 1,
        season: MenuSeason(from: DateTime(2026, 6, 1), to: DateTime(2026, 8, 31), yearly: true),
        items: [_dish('i3', 's2', 'Gazpacho', price: 2400)],
      ),
    ];

    Future<void> open(WidgetTester tester) async {
      await tester.runAsync(() async {
        await initializeDateFormatting('pl');
        final loader = FontLoader('packages/table_core/Geist');
        for (final weight in ['Regular', 'Medium', 'SemiBold']) {
          loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
        }
        await loader.load();
      });
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AppColors.use(PanelPalette.dark);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentRestaurantProvider.overrideWithValue(
              const PanelRestaurant(id: 'r1', name: 'Lokal', city: 'Kraków', isPro: true, role: StaffRole.owner),
            ),
            memberPermissionsProvider.overrideWithValue({'menu', 'menu_edit', 'menu_availability', 'calendar'}),
            menuProvider.overrideWith((ref, id) async => sections),
            inventoryItemsProvider.overrideWith((ref, id) async => const <InventoryItem>[]),
          ],
          child: MaterialApp(
            theme: PanelTheme.build(PanelPalette.dark),
            home: const Scaffold(body: MenuScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('sekcje z daniami, sezon przy sekcji i filtry z liczbą dań', (tester) async {
      await open(tester);
      expect(find.text('Dania główne'), findsWidgets);
      expect(find.text('Menu letnie'), findsWidgets);
      expect(find.text('Pierogi ruskie'), findsOneWidget);
      expect(find.text('Gazpacho'), findsOneWidget);
      // Okres sezonu i jego stan przy sekcji.
      expect(find.textContaining('1 cze – 31 sie, co roku'), findsOneWidget);
      expect(find.text('Niedostępne'), findsWidgets);
      // Filtr „Kiedy w menu” liczy dania: zawsze 2, sezonowe 1, na wydarzenie 0.
      expect(find.text('Zawsze (2)'), findsOneWidget);
      expect(find.text('Sezonowe (1)'), findsOneWidget);
      expect(find.text('Na wydarzenie (0)'), findsOneWidget);

      await tester.tap(find.text('Sezonowe (1)'));
      await tester.pump();
      expect(find.text('Gazpacho'), findsOneWidget);
      expect(find.text('Pierogi ruskie'), findsNothing);
    });

    testWidgets('wyszukiwanie po daniu i po nazwie sekcji', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField).first, 'schab');
      await tester.pump();
      expect(find.text('Schabowy'), findsOneWidget);
      expect(find.text('Pierogi ruskie'), findsNothing);
      expect(find.text('Gazpacho'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'letnie');
      await tester.pump();
      expect(find.text('Gazpacho'), findsOneWidget);
      expect(find.text('Schabowy'), findsNothing);
    });

    testWidgets('nowa sekcja: okno z wyborem Zawsze, Sezon albo Wydarzenie i gotowymi okresami', (tester) async {
      await open(tester);
      await tester.tap(find.text('Nowa sekcja').first);
      await tester.pumpAndSettle();
      // Napis jest i w filtrach po lewej, i w oknie sekcji.
      expect(find.text('Kiedy w menu'), findsNWidgets(2));
      expect(find.text('Okres'), findsNothing);
      await tester.tap(find.text('Sezon'));
      await tester.pumpAndSettle();
      expect(find.text('Okres'), findsOneWidget);
      for (final name in ['Wiosna', 'Lato', 'Jesień', 'Zima', 'Święta']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('Powtarzaj co roku'), findsOneWidget);
      // Gotowy okres ustawia „co roku” i daty.
      await tester.tap(find.text('Lato'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 cze – 31 sie, co roku'), findsWidgets);
    });

    testWidgets('danie otwiera okno z sekcją, ceną i alergenami', (tester) async {
      await open(tester);
      await tester.tap(find.text('Pierogi ruskie'));
      await tester.pumpAndSettle();
      expect(find.text('Edytuj pozycję'), findsOneWidget);
      expect(find.text('Sekcja'), findsWidgets);
      expect(find.text('Warianty'), findsOneWidget);
      expect(find.text('Stawka VAT'), findsOneWidget);
      expect(find.text('Zapisz'), findsOneWidget);
    });
  });
}
