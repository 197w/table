import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/app/app.dart';
import 'package:table_panel/data/models.dart';

void main() {
  test('zamówienie na wynos w panelu: suma, etap i dostawca', () {
    final order = TakeawayOrder.fromJson({
      'id': 'o1',
      'kind': 'delivery',
      'number': 12,
      'fulfillment': 'ready',
      'opened_at': '2026-09-30T17:00:00Z',
      'customer_name': 'Anna',
      'customer_phone': '600 100 200',
      'delivery_address': 'Lipowa 1',
      'delivery_fee_grosze': 800,
      'payment_choice': 'cash',
      'payment_status': 'unpaid',
      'courier_member': 'c1',
      'courier': {'name': 'Adam'},
      'order_items': [
        {
          'id': 'i1', 'order_id': 'o1', 'name': 'Pizza', 'quantity': 2, 'unit_price_grosze': 2200,
          'vat_rate': 8, 'status': 'sent', 'course': 1, 'addons': [], 'created_at': '2026-09-30T17:00:00Z',
        },
      ],
    });
    expect(order.label, 'Dostawa #12');
    expect(order.totalGrosze, 5200);
    expect(order.stage, TakeawayStage.ready);
    expect(order.courierName, 'Adam');
    expect(TakeawayStage.delivered.finished, isTrue);
  });

  test('rachunek na wynos w historii ma numer zamiast stolika', () {
    final o = PanelOrder.fromJson({
      'id': 'o1', 'opened_at': '2026-09-30T17:00:00Z', 'kind': 'pickup', 'number': 3, 'order_items': [],
    });
    expect(o.takeawayLabel, 'Na wynos #3');
    expect(canOpenRoute(PanelRoutes.deliveries, {'orders'}), isTrue);
    expect(canOpenRoute(PanelRoutes.deliveries, {'kitchen'}), isFalse);
  });
}
