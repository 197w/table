import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/app/app.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/data/models.dart';

void main() {
  test('liczby w inwentaryzacji po polsku, bez zbędnych zer', () {
    expect(inventoryNumber(0.7), '0,7');
    expect(inventoryNumber(2.45), '2,45');
    expect(inventoryNumber(12), '12');
    expect(inventoryNumber(1.75), '1,75');
    expect(parseInventoryNumber('2,5'), 2.5);
    expect(parseInventoryNumber(' 3.25 '), 3.25);
    expect(parseInventoryNumber(''), isNull);
    expect(parseInventoryNumber('dwa'), isNull);
  });

  test('następna inwentaryzacja według okresu lokalu', () {
    final last = DateTime(2026, 9, 30);
    expect(nextInventoryDay('day', last), DateTime(2026, 10, 1));
    expect(nextInventoryDay('week', last), DateTime(2026, 10, 7));
    expect(nextInventoryDay('two_weeks', last), DateTime(2026, 10, 14));
    expect(nextInventoryDay('month', last), DateTime(2026, 10, 30));
    expect(nextInventoryDay('week', null), isNull);
    expect(inventoryPeriodLabel('two_weeks'), 'Co 2 tygodnie');
  });

  test('spis z ilością w opakowaniach i razem w jednostce', () {
    final count = InventoryCount.fromJson({
      'id': 'c1',
      'started_at': '2026-09-30T10:00:00Z',
      'finished_at': null,
      'started_by': 'Anna Kowalska',
      'lines': [
        {
          'item_id': 'i1',
          'name': 'Wódka',
          'unit': 'l',
          'capacity': 0.7,
          'quantity': 2.5,
          'counted_by': 'Anna Kowalska',
        },
      ],
    });
    expect(count.open, isTrue);
    expect(count.line('i1')!.totalText, '1,75 l');
    expect(count.line('i2'), isNull);

    final item = InventoryItem.fromJson({'id': 'i2', 'name': 'Cytryny', 'unit': 'szt', 'capacity': '1.000', 'sort': 0});
    expect(item.package, '1 szt.');
  });

  test('zakładka Inwentaryzacja dla edycji albo wpisywania ilości', () {
    expect(canOpenRoute(PanelRoutes.inventory, {'inventory_count'}), isTrue);
    expect(canOpenRoute(PanelRoutes.inventory, {'inventory_edit'}), isTrue);
    expect(canOpenRoute(PanelRoutes.inventory, {'menu'}), isFalse);
    expect(StaffPermission.fromKey('inventory_edit')?.label, 'Edytowanie składników');
    expect(StaffPermission.fromKey('inventory_count')?.label, 'Wpisywanie ilości składników');
  });

  test('receptura dania: jednostki porcji i zapis', () {
    expect(InventoryUnit.l.portion, InventoryUnit.ml);
    expect(InventoryUnit.kg.portion, InventoryUnit.g);
    expect(InventoryUnit.szt.compatible, [InventoryUnit.szt]);
    expect(InventoryUnit.ml.compatible, containsAll([InventoryUnit.ml, InventoryUnit.l]));

    final item = MenuItem.fromJson({
      'id': 'm1',
      'section_id': 's1',
      'name': 'Wódka 50 ml',
      'price_grosze': 1200,
      'position': 0,
      'menu_item_ingredients': [
        {'item_id': 'i1', 'amount': 50, 'unit': 'ml'},
      ],
    });
    expect(item.ingredients.single.amount, 50);
    expect(item.ingredients.single.unit, InventoryUnit.ml);
    expect(item.ingredients.single.toJson(), {'item_id': 'i1', 'amount': 50.0, 'unit': 'ml'});
  });

  test('inwentaryzacja porównana ze sprzedażą', () {
    final line = InventoryLine.fromJson({
      'item_id': 'i1',
      'name': 'Wódka',
      'unit': 'l',
      'capacity': 0.7,
      'quantity': 4,
      'used': 1.2,
      'expected': 3.0,
    });
    expect(line.total, closeTo(2.8, 1e-9));
    expect(line.difference, closeTo(-0.2, 1e-9));

    final first = InventoryLine.fromJson({'item_id': 'i2', 'name': 'Mleko', 'unit': 'l', 'capacity': 1, 'quantity': 5});
    expect(first.difference, isNull);

    final stock = InventoryStock.fromJson({
      'item_id': 'i1',
      'counted': 4.2,
      'counted_at': '2026-09-23T08:10:00Z',
      'used': 0.35,
      'stock': 3.85,
    });
    expect(stock.stock, 3.85);
    expect(InventoryStock.fromJson({'item_id': 'i3', 'used': 0}).stock, isNull);
  });

  test('opakowania po polsku: 1 worek, 2 worki, 5 worków, 2,5 worka', () {
    expect(packCount(1, 'worek'), '1 worek');
    expect(packCount(2, 'worek'), '2 worki');
    expect(packCount(5, 'worek'), '5 worków');
    expect(packCount(12, 'zgrzewka'), '12 zgrzewek');
    expect(packCount(22, 'zgrzewka'), '22 zgrzewki');
    expect(packCount(2.5, 'worek'), '2,5 worka');
    expect(packCount(3, null), '3 op.');
    expect(packCount(3, 'wiaderko'), '3 wiaderko');
    expect(packWord('Puszka', null), 'puszek');
  });

  test('ruchy od inwentaryzacji: dostawy, usunięcia i pojemnik w spisie', () {
    final line = InventoryLine.fromJson({
      'item_id': 'm',
      'name': 'Mąka',
      'unit': 'kg',
      'capacity': 25,
      'quantity': 3,
      'previous': 27.5,
      'used': 0,
      'delivered': 50,
      'removed': 1.5,
      'expected': 76,
      'container': 'Średni',
      'container_id': 'b',
      'tare': 350,
      'gross': 2850,
      'loose': 2500,
    });
    expect(line.total, 75);
    expect(line.difference, closeTo(-1, 1e-9));
    expect(line.gross, 2850);

    final doc = InventoryDoc.fromJson({
      'id': 'd',
      'kind': 'removal',
      'happened_at': '2026-10-30T10:00:00Z',
      'reason': 'transfer',
      'note': 'Na Rynek',
      'lines': [
        {
          'item_id': 'w',
          'name': 'Woda',
          'unit': 'szt',
          'capacity': 12,
          'pack_name': 'zgrzewka',
          'packages': 2,
          'loose': 3,
          'amount': 27,
        },
        {'item_id': 'c', 'name': 'Cytryny', 'unit': 'szt', 'capacity': 1, 'loose': 5, 'amount': 5},
      ],
    });
    expect(doc.title, 'Usunięcie · Przekazanie do innego lokalu');
    expect(doc.lines.first.text, '2 zgrzewki + 3 szt. = 27 szt.');
    expect(doc.lines.last.text, '5 szt.');
  });

  test('próg zamówienia przy składniku (0086)', () {
    final item = InventoryItem.fromJson({
      'id': 'i1',
      'name': 'Mąka',
      'unit': 'kg',
      'capacity': 25,
      'reorder_at': '5.000',
    });
    expect(item.reorderAt, 5);
    expect(item.needsOrder(12), isFalse);
    expect(item.needsOrder(5), isTrue);
    expect(item.needsOrder(-1), isTrue);
    expect(item.needsOrder(null), isFalse, reason: 'bez inwentaryzacji nie wiadomo, ile jest');
    final noAlert = InventoryItem.fromJson({'id': 'i2', 'name': 'Sól', 'unit': 'kg', 'capacity': 1});
    expect(noAlert.reorderAt, isNull);
    expect(noAlert.needsOrder(0), isFalse);
  });

  test('zużycie dziennie i prognoza „wystarczy na” w Statystykach (0086)', () {
    final report = InventoryUsageReport.fromJson({
      'from': '2026-11-05',
      'today': '2026-11-11',
      'items': [
        {
          'id': 'm',
          'name': 'Mąka',
          'unit': 'kg',
          'capacity': 25,
          'reorder_at': 4,
          'since': '2026-09-30',
          'stock': 10,
          'days': [
            {'day': '2026-11-06', 'sold': 4, 'lost': 0},
            {'day': '2026-11-10', 'sold': 2, 'lost': 1},
          ],
        },
        // Dodany przedwczoraj: średnia liczy się od dodania, nie z całego tygodnia.
        {
          'id': 'o',
          'name': 'Olej',
          'unit': 'l',
          'capacity': 10,
          'since': '2026-11-09',
          'stock': 0,
          'days': [
            {'day': '2026-11-09', 'sold': 1.5, 'lost': 0},
          ],
        },
        {'id': 's', 'name': 'Sól', 'unit': 'kg', 'capacity': 1, 'since': '2026-09-30', 'stock': null, 'days': []},
      ],
    });
    expect(report.days.length, 7);
    expect(report.days.first, DateTime.utc(2026, 11, 5));
    expect(report.days.last, DateTime.utc(2026, 11, 11));

    final flour = report.items.first;
    expect(flour.used, 7);
    expect(flour.lost, 1);
    expect(flour.activeDays, 7);
    expect(flour.perDay, 1);
    expect(flour.usedOn(DateTime.utc(2026, 11, 10)), 3);
    expect(flour.usedOn(DateTime.utc(2026, 11, 7)), 0);
    expect(flour.daysLeft, 10);
    expect(flour.needsOrder, isFalse);
    expect(flour.daysToOrder, 6);

    final oil = report.items[1];
    expect(oil.activeDays, 3);
    expect(oil.perDay, 0.5);
    expect(oil.daysLeft, 0, reason: 'stan zero to brak');

    final salt = report.items.last;
    expect(salt.daysLeft, isNull);
    expect(salt.daysToOrder, isNull);
    expect(salt.perDay, 0);

    expect(inventoryDaysText(0.4), 'mniej niż dzień');
    expect(inventoryDaysText(1.9), 'ok. 1 dzień');
    expect(inventoryDaysText(4.2), 'ok. 4 dni');
    expect(inventoryDaysText(400), 'ponad rok');
  });
}
