import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/app/app.dart';
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
        {'item_id': 'i1', 'name': 'Wódka', 'unit': 'l', 'capacity': 0.7, 'quantity': 2.5, 'counted_by': 'Anna Kowalska'},
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
      'item_id': 'i1', 'name': 'Wódka', 'unit': 'l', 'capacity': 0.7, 'quantity': 4,
      'used': 1.2, 'expected': 3.0,
    });
    expect(line.total, closeTo(2.8, 1e-9));
    expect(line.difference, closeTo(-0.2, 1e-9));

    final first = InventoryLine.fromJson({'item_id': 'i2', 'name': 'Mleko', 'unit': 'l', 'capacity': 1, 'quantity': 5});
    expect(first.difference, isNull);

    final stock = InventoryStock.fromJson({
      'item_id': 'i1', 'counted': 4.2, 'counted_at': '2026-09-23T08:10:00Z', 'used': 0.35, 'stock': 3.85,
    });
    expect(stock.stock, 3.85);
    expect(InventoryStock.fromJson({'item_id': 'i3', 'used': 0}).stock, isNull);
  });
}
