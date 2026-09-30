import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table/data/models.dart';
import 'package:table/data/providers.dart';

void main() {
  test('koszyk łączy to samo danie z tymi samymi opcjami', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final cart = container.read(cartProvider('r1').notifier);
    const pizza = CartLine(menuItemId: 'm1', name: 'Pizza', unitPriceGrosze: 3900, quantity: 1, variant: 'Duża');
    cart.add(pizza);
    cart.add(pizza);
    cart.add(const CartLine(menuItemId: 'm1', name: 'Pizza', unitPriceGrosze: 2500, quantity: 1, variant: 'Mała'));
    final lines = container.read(cartProvider('r1'));
    expect(lines.length, 2);
    expect(lines.first.quantity, 2);
    expect(lines.fold(0, (s, l) => s + l.totalGrosze), 3900 * 2 + 2500);
    cart.setQuantity(lines.first.key, 0);
    expect(container.read(cartProvider('r1')).length, 1);
    expect(lines.first.toJson(), {'menu_item_id': 'm1', 'quantity': 2, 'variant': 'Duża', 'addons': <String>[]});
  });

  test('zamówienie gościa: suma z dostawą i etap', () {
    final order = GuestOrder.fromJson({
      'id': 'o1',
      'restaurant_id': 'r1',
      'kind': 'delivery',
      'number': 7,
      'fulfillment': 'accepted',
      'opened_at': '2026-09-30T17:00:00Z',
      'delivery_address': 'Lipowa 1',
      'delivery_fee_grosze': 800,
      'payment_choice': 'card_online',
      'payment_status': 'paid',
      'payment_test': true,
      'restaurants': {'name': 'REVE', 'phone': '600', 'address': 'Rynek 1', 'city': 'Białystok'},
      'order_items': [
        {'name': 'Pizza', 'quantity': 2, 'unit_price_grosze': 3900, 'addons': [], 'status': 'sent'},
      ],
    });
    expect(order.totalGrosze, 8600);
    expect(order.stage, OrderStage.accepted);
    expect(order.canCancel, isFalse);
    expect(order.payment, PaymentChoice.card);
    expect(order.restaurantAddress, 'Rynek 1, Białystok');
  });
}
