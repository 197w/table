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

  test('zgłoszenie godzin przyjęte ze zmianą', () {
    final shift = PlannedShift.fromJson({
      'id': 's1',
      'member_id': 'm1',
      'restaurant_name': 'REVE',
      'day': '2026-10-01',
      'starts': '13:00:00',
      'ends': '20:00:00',
      'requested_starts': '12:00:00',
      'requested_ends': '20:00:00',
      'status': 'accepted',
    });
    expect(shift.accepted, isTrue);
    expect(shift.changed, isTrue);
    expect((shift.starts, shift.ends), ('13:00', '20:00'));
  });

  test('zgłoszenie czeka na przełożonego', () {
    final shift = PlannedShift.fromJson({
      'id': 's2',
      'member_id': 'm1',
      'restaurant_name': 'REVE',
      'day': '2026-10-02',
      'starts': '10:00:00',
      'ends': '18:00:00',
      'requested_starts': '10:00:00',
      'requested_ends': '18:00:00',
      'status': 'pending',
    });
    expect(shift.pending, isTrue);
    expect(shift.changed, isFalse);
  });
}
