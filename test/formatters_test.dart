import 'package:flutter_test/flutter_test.dart';
import 'package:rarytka/core/formatters.dart';
import 'package:rarytka/data/models.dart';
import 'package:rarytka/features/auth/auth_screens.dart';

void main() {
  group('normalizePolishPhone', () {
    test('9 cyfr dostaje prefiks +48', () {
      expect(normalizePolishPhone('600 700 800'), '+48600700800');
    });

    test('numer z 48 na początku', () {
      expect(normalizePolishPhone('48600700800'), '+48600700800');
    });

    test('odrzuca za krótki i obcy numer', () {
      expect(normalizePolishPhone('60070080'), isNull);
      expect(normalizePolishPhone('+44 7700 900123'), isNull);
    });
  });

  group('liczebniki', () {
    test('osoby', () {
      expect(Fmt.people(1), '1 osoba');
      expect(Fmt.people(2), '2 osoby');
      expect(Fmt.people(5), '5 osób');
      expect(Fmt.people(12), '12 osób');
      expect(Fmt.people(22), '22 osoby');
    });

    test('osoby w bierniku', () {
      expect(Fmt.peopleAccusative(1), '1 osobę');
      expect(Fmt.peopleAccusative(3), '3 osoby');
      expect(Fmt.peopleAccusative(7), '7 osób');
    });

    test('opinie', () {
      expect(Fmt.reviews(1), '1 opinia');
      expect(Fmt.reviews(3), '3 opinie');
      expect(Fmt.reviews(14), '14 opinii');
      expect(Fmt.reviews(24), '24 opinie');
    });

    test('lokale', () {
      expect(Fmt.restaurants(1), '1 lokal');
      expect(Fmt.restaurants(4), '4 lokale');
      expect(Fmt.restaurants(8), '8 lokali');
      expect(Fmt.restaurants(13), '13 lokali');
    });
  });

  test('poziom cen w dolarach', () {
    expect(Fmt.priceLevel(1), r'$');
    expect(Fmt.priceLevel(3), r'$$$');
    expect(Fmt.priceLevel(0), r'$');
    expect(Fmt.priceLevel(9), r'$$$$');
  });

  group('odległość', () {
    test('kilometry', () {
      expect(Fmt.distance(450), '450 m');
      expect(Fmt.distance(1234), '1,2 km');
      expect(Fmt.radius(10, DistanceUnit.kilometers), '10 km');
    });

    test('mile', () {
      expect(Fmt.distance(100, DistanceUnit.miles), '330 ft');
      expect(Fmt.distance(1609.344, DistanceUnit.miles), '1,0 mi');
      expect(Fmt.radius(10, DistanceUnit.miles), '6,2 mi');
    });
  });

  test('numer telefonu', () {
    expect(Fmt.phone('48511448098'), '+48 511 448 098');
    expect(Fmt.phone(null), '–');
  });

  test('czas wizyty zgodny z bazą', () {
    expect(visitMinutes(2), 90);
    expect(visitMinutes(4), 105);
    expect(visitMinutes(6), 120);
  });

  test('wielka litera na początku', () {
    expect(Fmt.capitalize('wtorek, 15 września'), 'Wtorek, 15 września');
    expect(Fmt.capitalize(''), '');
  });
}
