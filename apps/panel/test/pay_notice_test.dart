import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/models.dart';

void main() {
  test('napis o płatności w lokalu: gotówka i karta przy odbiorze to nieopłacone', () {
    expect(takeawayPayNotice(OrderKind.delivery, 'cash'), 'NIEOPŁACONE · gotówka u dostawcy');
    expect(takeawayPayNotice(OrderKind.delivery, 'card_on_delivery'), 'NIEOPŁACONE · karta u dostawcy');
    expect(takeawayPayNotice(OrderKind.pickup, 'cash'), 'NIEOPŁACONE · gotówka przy odbiorze');
    expect(takeawayPayNotice(OrderKind.pickup, 'card_on_delivery'), 'NIEOPŁACONE · karta przy odbiorze');
    // Opłacone z góry i rachunek na sali bez napisu.
    expect(takeawayPayNotice(OrderKind.delivery, 'card_online'), isNull);
    expect(takeawayPayNotice(OrderKind.pickup, 'prepaid'), isNull);
    expect(takeawayPayNotice(OrderKind.dineIn, 'cash'), isNull);
    expect(takeawayPayNotice(OrderKind.delivery, null), isNull);
  });

  test('bilecik kuchni i karta Kompletowania niosą napis o płatności zamówienia na wynos', () {
    Map<String, dynamic> row(String status, Map<String, dynamic> order) => {
      'id': 'i1',
      'order_id': 'o1',
      'name': 'Pizza',
      'quantity': 1,
      'unit_price_grosze': 3200,
      'status': status,
      'created_at': '2026-11-20T18:00:00Z',
      'sent_at': '2026-11-20T18:01:00Z',
      'ready_at': '2026-11-20T18:10:00Z',
      'orders': order,
    };
    final delivery = {'kind': 'delivery', 'number': 7, 'fulfillment': 'accepted', 'payment_choice': 'cash'};

    final kitchen = KitchenTicket.fromRows([row('sent', delivery)]);
    expect(kitchen.single.payNotice, 'NIEOPŁACONE · gotówka u dostawcy');

    final serving = ServingTicket.fromRows([row('ready', delivery)]);
    expect(serving.single.payNotice, 'NIEOPŁACONE · gotówka u dostawcy');

    final paid = ServingTicket.fromRows([row('ready', {...delivery, 'payment_choice': 'card_online'})]);
    expect(paid.single.payNotice, isNull);
    final table = KitchenTicket.fromRows([row('sent', {'kind': 'dine_in', 'table_id': 't1'})]);
    expect(table.single.payNotice, isNull);
  });
}
