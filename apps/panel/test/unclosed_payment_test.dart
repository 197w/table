import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/models.dart';

UnclosedOrder _order(String kind, String? choice, {String fulfillment = 'on_the_way', String? courier}) =>
    UnclosedOrder.fromJson({
      'id': 'o',
      'kind': kind,
      'number': 5,
      'fulfillment': kind == 'dine_in' ? null : fulfillment,
      'status': 'open',
      'opened_at': DateTime(2026, 11, 20, 18).toUtc().toIso8601String(),
      'payment_choice': choice,
      'courier': courier == null ? null : {'name': courier},
    });

void main() {
  group('niezamknięte zamówienia: płatność przy dostawie', () {
    test('gotówka i karta przy odbiorze to zamówienie nieopłacone, z formą płatności', () {
      final cash = _order('delivery', 'cash', courier: 'Marek');
      expect(cash.payOnDelivery, isTrue);
      expect(cash.paymentNotice, 'NIEOPŁACONE · gotówka u dostawcy');
      expect(cash.courierName, 'Marek');
      expect(_order('pickup', 'card_on_delivery', fulfillment: 'ready').paymentNotice, 'NIEOPŁACONE · karta przy odbiorze');
      expect(_order('delivery', 'card_on_delivery').paymentNotice, 'NIEOPŁACONE · karta u dostawcy');
    });

    test('karta online i opłacone wcześniej są opłacone, rachunek na sali nie ma napisu', () {
      expect(_order('delivery', 'card_online').paymentNotice, 'Opłacone');
      expect(_order('delivery', 'prepaid').payOnDelivery, isFalse);
      expect(_order('dine_in', 'cash').paymentNotice, isNull);
    });
  });
}
