import 'package:flutter_test/flutter_test.dart';
import 'package:table_staff/data.dart';
import 'package:table_staff/orders_data.dart';
import 'package:table_staff/schedule_screen.dart';

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

  test('wolne od przełożonego', () {
    final shift = PlannedShift.fromJson({
      'id': 's3',
      'member_id': 'm1',
      'restaurant_name': 'REVE',
      'day': '2026-10-03',
      'starts': null,
      'ends': null,
      'status': 'off',
    });
    expect(shift.off, isTrue);
    expect(shift.pending, isFalse);
    expect(shift.starts, isEmpty);
  });

  test('okres grafiku lokalu z danych pracownika', () {
    Job job(Object? period) => Job.fromJson({
      'member_id': 'm',
      'restaurant_id': 'r',
      'restaurant_name': 'REVE',
      'member_name': 'Ola',
      'week_seconds': 0,
      'schedule_period': period,
    });
    expect(job('month').schedulePeriod, 'month');
    expect(job(null).schedulePeriod, 'week');
  });

  test('okresy grafiku idą jeden po drugim', () {
    for (final kind in ['week', 'two_weeks', 'month']) {
      final now = periodFor(kind, 0);
      final next = periodFor(kind, 1);
      final today = DateTime.now();
      expect(now.from.isAfter(DateTime(today.year, today.month, today.day)), isFalse, reason: kind);
      expect(now.to.isBefore(DateTime(today.year, today.month, today.day)), isFalse, reason: kind);
      expect(next.from, DateTime(now.to.year, now.to.month, now.to.day + 1), reason: kind);
      if (kind == 'month') {
        expect(now.from.day, 1);
        expect(DateTime(now.to.year, now.to.month, now.to.day + 1).day, 1);
      } else {
        expect(now.from.weekday, DateTime.monday, reason: kind);
        expect(now.to.difference(now.from).inDays, kind == 'week' ? 6 : 13, reason: kind);
      }
    }
    // Pary tygodni są wspólne dla całego lokalu: liczone od poniedziałku 5 stycznia 2026.
    final from = periodFor('two_weeks', 0).from;
    expect(DateTime.utc(from.year, from.month, from.day).difference(DateTime.utc(2026, 1, 5)).inDays % 14, 0);
  });

  test('menu kelnera: „od” tylko przy różnych cenach wariantów', () {
    WMenuItem item(List<Map<String, Object>> variants) =>
        WMenuItem.fromJson({'id': 'm1', 'name': 'Tonic', 'price_grosze': 1500, 'variants': variants});
    final tonic = item([{'name': '200 ml', 'price_grosze': 1500}]);
    expect(tonic.priceVaries, isFalse);
    expect(tonic.fromPrice, 1500);
    final pizza = item([{'name': 'Duża', 'price_grosze': 3900}, {'name': 'Mała', 'price_grosze': 2500}]);
    expect(pizza.priceVaries, isTrue);
    expect(pizza.fromPrice, 2500);
  });

  test('rachunek kelnera: rabat od części i równy podział', () {
    final due = WDue.fromJson({'total': 11000, 'discount': 1100, 'due': 9900, 'discount_percent': 10});
    expect(due.forPart(4200), (420, 3780));
    expect(splitEqually(6120, 2), [3060, 3060]);
    expect(const WPart(WPayment.cash, 3060, tip: 100).toJson(), {'method': 'cash', 'amount': 3060, 'tip': 100});
  });

  test('zadatek z rezerwacji w kwocie do zapłaty', () {
    final due = WDue.fromJson({'total': 25200, 'discount': 0, 'deposit': 20000, 'due': 5200});
    expect(due.deposit, 20000);
    expect(due.due, 5200);
  });

  test('kod rabatowy przy rachunku i podpowiedzi kodów', () {
    final due = WDue.fromJson({
      'total': 4400,
      'discount': 500,
      'due': 3900,
      'discount_label': 'TESTPIEC (−5,00 zł)',
      'discount_code': 'TESTPIEC',
      'reservation_code': null,
    });
    expect(due.code, 'TESTPIEC');
    expect(due.reservationCode, isNull);
    expect(due.forPart(2200), (0, 2200));
    final hint = WDiscountHint.fromJson({'code': 'LATO10', 'kind': 'percent', 'value': 10, 'note': ' '});
    expect(hint.valueText, '−10%');
    expect(hint.note, isNull);
    expect(WDiscountHint.fromJson({'code': 'PIEC', 'kind': 'amount', 'value': 500}).valueText, '−5,00 zł');
  });
}
