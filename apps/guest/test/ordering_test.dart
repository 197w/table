import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table/data/models.dart';
import 'package:table/data/providers.dart';
import 'package:table/features/ordering/courier_map.dart';

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

  test('cena „od” tylko przy różnych cenach wariantów', () {
    MenuItem item(List<Map<String, Object>> variants) => MenuItem.fromJson({
      'id': 'm1', 'name': 'Tonic', 'price_grosze': 1500, 'position': 0, 'variants': variants,
    });
    expect(item([{'name': '200 ml', 'price_grosze': 1500}]).priceVaries, isFalse);
    expect(item([{'name': 'Mała', 'price_grosze': 2500}, {'name': 'Duża', 'price_grosze': 3900}]).priceVaries, isTrue);
    expect(item(const []).priceVaries, isFalse);
  });

  test('kod rabatowy przy rezerwacji', () {
    expect(GuestDiscount.fromJson({'code': 'REVE10', 'kind': 'percent', 'value': 10}).label, '−10% od rachunku');
    expect(GuestDiscount.fromJson({'code': 'ZIMA', 'kind': 'amount', 'value': 2050}).label, '−20,50 zł od rachunku');
  });

  test('zadatek: od ilu osób i ile za osobę', () {
    final r = RestaurantDetail.fromJson({
      'id': 'r1', 'name': 'REVE', 'cuisine': 'polska', 'price_level': 2, 'address': 'Rynek 1', 'city': 'Białystok',
      'phone': '600', 'plan': 'pro', 'max_party_size': 12, 'deposit_min_party': 4, 'deposit_per_person_grosze': 5000,
    }, Rating.empty);
    expect(r.depositFor(3), isNull);
    expect(r.depositFor(4), 20000);
    final d = ReservationDetail.fromJson({
      'id': 'x', 'restaurant_id': 'r1', 'restaurant_name': 'REVE', 'address': 'Rynek 1', 'city': 'Białystok', 'phone': '600',
      'lat': 53.1, 'lng': 23.1, 'party_size': 4, 'starts_at': DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String(),
      'ends_at': DateTime.now().add(const Duration(days: 1, hours: 2)).toUtc().toIso8601String(), 'status': 'confirmed',
      'reviewed': false, 'discount_code': 'REVE10', 'discount_kind': 'percent', 'discount_value': 10,
      'deposit_grosze': 20000, 'deposit_status': 'pending',
    });
    expect(d.depositPending, isTrue);
    expect(d.discountLabel, 'REVE10 · −10% od rachunku');
  });

  test('zamówienie na godzinę: godziny otwarcia i czas kuchni', () {
    final r = RestaurantDetail.fromJson({
      'id': 'r1', 'name': 'REVE', 'cuisine': 'polska', 'price_level': 2, 'address': 'Rynek 1', 'city': 'Białystok',
      'phone': '600', 'plan': 'pro', 'kitchen_lead_pickup_min': 20, 'kitchen_lead_delivery_min': 40,
      // Czwartek 12:00–22:00, piątek zamknięte.
      'opening_hours': [
        {'weekday': 4, 'opens': '12:00:00', 'closes': '22:00:00'},
      ],
    }, Rating.empty);
    final thursday = DateTime(2026, 10, 8);
    final now = DateTime(2026, 10, 8, 17, 2);
    // Odbiór: 20 min kuchni + 5 zapasu od 17:02, więc od 17:30; ostatnia 21:45.
    final pickup = r.orderSlots(OrderKind.pickup, thursday, now);
    expect(pickup.first, DateTime(2026, 10, 8, 17, 30));
    expect(pickup.last, DateTime(2026, 10, 8, 21, 45));
    // Dostawa: 40 + 5 minut, więc od 17:52 w górę do kwadransa: 18:00.
    expect(r.orderSlots(OrderKind.delivery, thursday, now).first, DateTime(2026, 10, 8, 18));
    expect(r.orderSlots(OrderKind.pickup, DateTime(2026, 10, 9), now), isEmpty);
    // Za tydzień od otwarcia.
    expect(r.orderSlots(OrderKind.pickup, DateTime(2026, 10, 15), now).first, DateTime(2026, 10, 15, 12));
    final order = GuestOrder.fromJson({
      'id': 'o1', 'restaurant_id': 'r1', 'kind': 'pickup', 'number': 3, 'fulfillment': 'accepted',
      'opened_at': '2026-10-08T15:00:00Z', 'scheduled_for': '2026-10-08T17:30:00Z', 'order_items': [],
    });
    expect(order.scheduledFor, DateTime.parse('2026-10-08T17:30:00Z').toLocal());
  });

  test('lista oczekujących: godziny co pół godziny i propozycja lokalu', () {
    expect(halfHours('12:15', '14:00'), ['12:30', '13:00', '13:30', '14:00']);
    expect(halfHours('22:00', '00:00'), ['22:00', '22:30', '23:00', '23:30', '24:00']);
    final w = GuestWaitlist.fromJson({
      'id': 'w', 'restaurant_id': 'r', 'restaurant_name': 'REVE', 'day': '2026-10-10', 'party_size': 4,
      'time_from': '18:00:00', 'time_to': '21:00:00', 'status': 'offered', 'offered_time': '19:30:00',
    });
    expect(w.offered, isTrue);
    expect(w.offeredTime, '19:30');
    expect(w.from, '18:00');
  });

  test('pozycja dostawcy na mapie', () {
    final p = CourierPosition.fromJson({
      'lat': 53.13, 'lng': 23.16, 'updated_at': '2026-10-04T12:00:00Z', 'restaurant_lat': 53.1, 'restaurant_lng': 23.1,
    })!;
    expect(p.courier!.latitude, 53.13);
    expect(p.restaurant!.longitude, 23.1);
    expect(CourierPosition.fromJson({'restaurant_lat': 53.1, 'restaurant_lng': 23.1})!.courier, isNull);
    expect(CourierPosition.fromJson(null), isNull);
  });
}
