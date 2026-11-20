import 'package:flutter_test/flutter_test.dart';
import 'package:table/data/models.dart';
import 'package:table/shared/discounted_price.dart';

void main() {
  final starts = DateTime(2026, 11, 20, 18);
  final ends = DateTime(2026, 11, 20, 23);

  MenuSection section({List<Map<String, dynamic>> discounts = const []}) => MenuSection.fromJson({
    'id': 's1',
    'name': 'Pizza',
    'position': 0,
    'discounts': discounts,
    'menu_items': [
      {
        'id': 'i1',
        'name': 'Margherita',
        'price_grosze': 4200,
        'position': 0,
        'variants': const [],
        'addons': const [],
      },
      {
        'id': 'i2',
        'name': 'Pepperoni',
        'price_grosze': 1010,
        'position': 1,
        'variants': [
          {'name': 'mała', 'price_grosze': 1010},
          {'name': 'duża', 'price_grosze': 2000},
        ],
        'addons': const [],
      },
    ],
  });

  Map<String, dynamic> discount(int percent, DateTime from, DateTime to) => {
    'percent': percent,
    'event': {'starts_at': from.toUtc().toIso8601String(), 'ends_at': to.toUtc().toIso8601String()},
  };

  group('zniżka na dział w czasie wydarzenia (0092)', () {
    test('działa tylko w czasie wydarzenia', () {
      final item = section(discounts: [discount(25, starts, ends)]).items.first;
      expect(item.discountAt(DateTime(2026, 11, 20, 17, 59)), 0);
      expect(item.discountAt(starts), 25);
      expect(item.discountAt(DateTime(2026, 11, 20, 22, 59)), 25);
      // Koniec wydarzenia już bez zniżki.
      expect(item.discountAt(ends), 0);
      expect(item.priceAfterDiscount(4200, DateTime(2026, 11, 20, 19)), 3150);
      expect(item.priceAfterDiscount(4200, DateTime(2026, 11, 21)), 4200);
    });

    test('dwa wydarzenia naraz: większa zniżka, zaokrąglenie do grosza jak w bazie', () {
      final item = section(discounts: [discount(10, starts, ends), discount(30, starts, ends)]).items.last;
      final at = DateTime(2026, 11, 20, 20);
      expect(item.discountAt(at), 30);
      // 1010 · 70% = 707, 2000 · 70% = 1400.
      expect(item.priceAfterDiscount(1010, at), 707);
      expect(item.priceAfterDiscount(2000, at), 1400);
      // Połówka groszy w górę: 1010 · 95% = 959,5 → 960.
      final five = section(discounts: [discount(5, starts, ends)]).items.last;
      expect(five.priceAfterDiscount(1010, at), 960);
    });

    test('bez zniżek nic się nie zmienia, a źle zapisana zniżka (bez wydarzenia) jest pomijana', () {
      final plain = section().items.first;
      expect(plain.discounts, isEmpty);
      expect(plain.priceAfterDiscount(4200), 4200);
      final broken = section(discounts: [
        {'percent': 20, 'event': null},
      ]).items.first;
      expect(broken.discounts, isEmpty);
    });

    test('napis ceny w menu: zniżka i „od” przy wariantach', () {
      String plain(String s) => s.replaceAll(RegExp(r'[  ]'), ' ');
      final pizza = section(discounts: [discount(25, starts, ends)]);
      final at = DateTime(2026, 11, 20, 19);
      expect(plain(menuPriceText(pizza.items.first, at)), '−25% 31,50 zł');
      expect(plain(menuPriceText(pizza.items.last, at)), '−25% od 7,58 zł');
      expect(plain(menuPriceText(pizza.items.first, DateTime(2026, 11, 21))), '42,00 zł');
    });
  });
}
