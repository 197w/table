import 'package:flutter_test/flutter_test.dart';
import 'package:table_staff/data.dart';

void main() {
  test('numer telefonu w postaci +48XXXXXXXXX', () {
    expect(normalizePolishPhone('600 700 800'), '+48600700800');
    expect(normalizePolishPhone('48600700800'), '+48600700800');
    expect(normalizePolishPhone('60070080'), isNull);
  });

  test('zmiana bez końca trwa do teraz', () {
    final shift = Shift(
      id: 'a',
      restaurantName: 'REVE',
      startedAt: DateTime.now().subtract(const Duration(hours: 2)),
    );
    expect(shift.duration.inMinutes, inInclusiveRange(119, 121));
  });
}
