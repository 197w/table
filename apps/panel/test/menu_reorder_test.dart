import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
import 'package:table_panel/data/repository.dart';
import 'package:table_panel/features/menu/menu_screen.dart';

/// Menu w pamięci: `reorder` zapisuje pozycje tak jak baza, `menu` czyta je z powrotem.
class _MenuRepo implements PanelRepository {
  _MenuRepo(this.sections, this.items);

  final Map<String, int> sections;
  final Map<String, ({String section, String name, int position})> items;
  final reorders = <(String, List<String>)>[];

  @override
  Future<List<MenuSection>> menu(String restaurantId) async {
    final list = [
      for (final e in sections.entries)
        MenuSection.fromJson({
          'id': e.key,
          'name': 'Sekcja ${e.key}',
          'position': e.value,
          'menu_items': [
            for (final i in items.entries)
              if (i.value.section == e.key)
                {'id': i.key, 'section_id': e.key, 'name': i.value.name, 'price_grosze': 1000, 'position': i.value.position},
          ],
        }),
    ]..sort((a, b) => a.position.compareTo(b.position));
    return list;
  }

  @override
  Future<void> reorder(String table, List<String> ids) async {
    reorders.add((table, ids));
    for (var i = 0; i < ids.length; i++) {
      if (table == 'menu_items') {
        items[ids[i]] = (section: items[ids[i]]!.section, name: items[ids[i]]!.name, position: i);
      } else {
        sections[ids[i]] = i;
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('menu: „Przesuń niżej” przesuwa pozycję w dół, „Przesuń wyżej” w górę, sekcje tak samo', (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('pl_PL');
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
    final repo = _MenuRepo(
      {'A': 0, 'B': 1},
      {
        'i1': (section: 'A', name: 'Tatar', position: 0),
        'i2': (section: 'A', name: 'Pierogi', position: 1),
        'i3': (section: 'A', name: 'Sałatka', position: 2),
        'i4': (section: 'B', name: 'Cola', position: 0),
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentRestaurantProvider.overrideWithValue(
            const PanelRestaurant(id: 'r1', name: 'Lokal', city: 'Białystok', isPro: true, role: StaffRole.owner),
          ),
          memberPermissionsProvider.overrideWithValue({'menu', 'menu_edit', 'menu_availability'}),
          repositoryProvider.overrideWithValue(repo),
          inventoryItemsProvider.overrideWith((ref, id) async => const <InventoryItem>[]),
        ],
        child: MaterialApp(
          theme: PanelTheme.build(PanelPalette.dark),
          home: const Scaffold(body: MenuScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(y('Tatar') < y('Pierogi') && y('Pierogi') < y('Sałatka'), isTrue, reason: 'kolejność na starcie');

    Future<void> menuOf(String dish, String action) async {
      // „⋯” w wierszu tego dania.
      final row = find.ancestor(of: find.text(dish), matching: find.byType(InkWell)).first;
      await tester.tap(find.descendant(of: row, matching: find.byTooltip('Więcej')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action).last);
      await tester.pumpAndSettle();
    }

    // Pierwsza pozycja w dół: Tatar schodzi pod Pierogi.
    await menuOf('Tatar', 'Przesuń niżej');
    expect(repo.reorders.last.$1, 'menu_items');
    expect(repo.reorders.last.$2, ['i2', 'i1', 'i3']);
    expect(y('Pierogi') < y('Tatar') && y('Tatar') < y('Sałatka'), isTrue, reason: 'w dół ma być niżej');

    // Ostatnia pozycja w górę: Sałatka wchodzi nad Tatar.
    await menuOf('Sałatka', 'Przesuń wyżej');
    expect(repo.reorders.last.$2, ['i2', 'i3', 'i1']);
    expect(y('Pierogi') < y('Sałatka') && y('Sałatka') < y('Tatar'), isTrue, reason: 'w górę ma być wyżej');

    // Menu otwiera się pod przyciskiem „⋯”, nie na nim.
    final row = find.ancestor(of: find.text('Pierogi'), matching: find.byType(InkWell)).first;
    final button = find.descendant(of: row, matching: find.byTooltip('Więcej'));
    final buttonBottom = tester.getBottomLeft(button).dy;
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Edytuj')).dy, greaterThanOrEqualTo(buttonBottom - 1));
  });
}
