import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/features/orders/orders_screen.dart';

Map<String, dynamic> _item(
  String id, {
  required int price,
  int quantity = 1,
  int vat = 8,
  String status = 'new',
  String? variant,
  List<Map<String, dynamic>> addons = const [],
  int course = 1,
  String created = '2026-09-24T18:00:00Z',
}) => {
  'id': id,
  'order_id': 'o1',
  'name': 'Danie $id',
  'variant': variant,
  'addons': addons,
  'unit_price_grosze': price,
  'vat_rate': vat,
  'quantity': quantity,
  'course': course,
  'status': status,
  'created_at': created,
};

void main() {
  test('rachunek liczy sumę bez anulowanych pozycji i dzieli ją na stawki VAT', () {
    final order = PanelOrder.fromJson({
      'id': 'o1',
      'table_id': 't1',
      'opened_at': '2026-09-24T18:00:00Z',
      'order_items': [
        _item('a', price: 4300, quantity: 2),
        _item('b', price: 1500, vat: 23, status: 'sent'),
        _item('c', price: 9900, status: 'cancelled'),
      ],
    });
    expect(order.totalGrosze, 4300 * 2 + 1500);
    expect(order.unsent, 1);
    expect(order.byVat, {8: 8600, 23: 1500});
  });

  test('pozycje idą według kolejności wydawania, potem według czasu nabicia', () {
    final order = PanelOrder.fromJson({
      'id': 'o1',
      'opened_at': '2026-09-24T18:00:00Z',
      'order_items': [
        _item('deser', price: 100, course: 3),
        _item('zupa2', price: 100, created: '2026-09-24T18:05:00Z'),
        _item('zupa1', price: 100, created: '2026-09-24T18:01:00Z'),
      ],
    });
    expect(order.items.map((i) => i.id), ['zupa1', 'zupa2', 'deser']);
  });

  test('wariant i dodatki w jednym wierszu', () {
    final item = OrderItem.fromJson(
      _item(
        'a',
        price: 4300,
        variant: 'Duża',
        addons: [
          {'name': 'Skwarki', 'price_grosze': 400},
        ],
      ),
    );
    expect(item.details, 'Duża, + skwarki');
    expect(OrderItem.fromJson(_item('b', price: 100)).details, isNull);
  });

  test('pozycja z wariantami zaczyna się od najniższej ceny', () {
    final item = MenuItem.fromJson({
      'id': 'm1',
      'section_id': 's1',
      'name': 'Pizza',
      'price_grosze': 2500,
      'allergens': <String>[],
      'position': 0,
      'variants': [
        {'name': 'Duża', 'price_grosze': 3900},
        {'name': 'Mała', 'price_grosze': 2500},
      ],
      'vat_rate': 8,
      'available': true,
    });
    expect(item.fromPrice, 2500);
    expect(item.hasOptions, isTrue);
  });

  test('numery stolików rosną jak liczby', () {
    final labels = ['10', 'B1', '2', 'a2', '1']..sort(compareLabels);
    expect(labels, ['1', '2', '10', 'a2', 'B1']);
  });
}
