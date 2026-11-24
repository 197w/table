import 'package:flutter_test/flutter_test.dart';
import 'package:table/data/models.dart';

void main() {
  // 27.11.2026 to piątek. Piątek 12:00–02:00 (po północy), reszta tygodnia 12:00–22:00.
  final hours = [
    for (var d = 1; d <= 7; d++)
      OpeningHours.fromJson({'weekday': d, 'opens': '12:00:00', 'closes': d == 5 ? '02:00:00' : '22:00:00'}),
  ];

  test('lokal otwarty po północy jest otwarty wieczorem i w nocnej końcówce poprzedniego dnia', () {
    expect(openingStatus(hours, DateTime(2026, 11, 27, 20))!.label, 'Otwarte do 02:00');
    expect(openingStatus(hours, DateTime(2026, 11, 27, 20))!.state, OpenState.open);
    // Sobota 00:30 to jeszcze piątkowe okno otwarcia, a od 01:00 do zamknięcia mniej niż godzina.
    expect(openingStatus(hours, DateTime(2026, 11, 28, 0, 30))!.label, 'Otwarte do 02:00');
    final night = openingStatus(hours, DateTime(2026, 11, 28, 1, 30))!;
    expect(night.state, OpenState.closingSoon);
    expect(night.label, 'Wkrótce zamknięcie – 02:00');
    // Sobota 02:00 i rano: zamknięte do 12:00.
    expect(openingStatus(hours, DateTime(2026, 11, 28, 2, 0))!.state.isOpen, isFalse);
    expect(openingStatus(hours, DateTime(2026, 11, 28, 9))!.label, 'Zamknięte · otwiera o 12:00');
    // Zwykły dzień bez zmian.
    expect(openingStatus(hours, DateTime(2026, 11, 26, 15))!.label, 'Otwarte do 22:00');
    expect(openingStatus(hours, DateTime(2026, 11, 26, 23))!.state.isOpen, isFalse);
  });

  test('godziny zamówienia na wynos sięgają po północy, lista oczekujących do północy', () {
    final restaurant = RestaurantDetail.fromJson({
      'id': 'r1', 'name': 'REVE', 'cuisine': 'wloska', 'price_level': 2, 'address': 'a', 'city': 'b', 'phone': '1',
      'plan': 'pro',
      'opening_hours': [
        {'weekday': 5, 'opens': '12:00:00', 'closes': '02:00:00'},
      ],
    }, Rating.empty);
    final day = DateTime(2026, 11, 27);
    final slots = restaurant.orderSlots(OrderKind.pickup, day, DateTime(2026, 11, 27, 10));
    expect(slots.first, DateTime(2026, 11, 27, 12, 0));
    expect(slots.last, DateTime(2026, 11, 28, 1, 45));
    expect(slots.any((s) => s == DateTime(2026, 11, 28, 0, 30)), isTrue);
    // Przedział listy oczekujących kończy się o północy, gdy zamknięcie jest po północy.
    expect(halfHours('12:00', '02:00').last, '24:00');
    expect(halfHours('12:00', '22:00').last, '22:00');
    expect(halfHours('12:00', '24:00').last, '24:00');
  });
}
