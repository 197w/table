import 'package:flutter_test/flutter_test.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/data/models.dart';

void main() {
  test('logi: zdarzenia po polsku i grupy na osi czasu', () {
    final pay = ActivityEvent.fromJson({
      'at': '2026-10-30T13:20:00Z',
      'kind': 'payment',
      'label': 'Stolik 2',
      'member': 'Marek',
      'amount': 12400,
      'tip': 1000,
      'method': 'card',
    });
    expect(pay.title, 'Płatność · Stolik 2');
    expect(pay.detail, contains('kartą'));
    expect(pay.detail, contains('przyjął(a) Marek'));
    expect(pay.group, ActivityGroup.bills);

    final sent = ActivityEvent.fromJson({
      'at': '2026-10-30T13:00:00Z',
      'kind': 'items_sent',
      'label': 'Stolik 1',
      'names': '3× Spaghetti Carbonara, 1× Pappardelle',
    });
    expect(sent.title, 'Na kuchnię · Stolik 1');
    expect(sent.detail, '3× Spaghetti Carbonara, 1× Pappardelle');
    expect(sent.group, ActivityGroup.kitchen);

    final pickup = ActivityEvent.fromJson({'at': '2026-10-30T13:00:00Z', 'kind': 'takeaway_done', 'label': '#4 odbiór'});
    expect(pickup.title, 'Wydane gościowi #4 odbiór');
    expect(pickup.group, ActivityGroup.takeaway);
  });

  test('Time Machine: rachunek bez anulowanych, stolik z rachunkiem i rezerwacją', () {
    final tm = TimeMachine.fromJson({
      'at': '2026-10-30T13:30:00Z',
      'bills': [
        {
          'order_id': 'o1',
          'table_id': 't1',
          'label': 'Stolik 1',
          'opened_at': '2026-10-30T12:40:00Z',
          'paid': 0,
          'items': [
            {'name': 'Pierogi', 'quantity': 2, 'price': 3200, 'status': 'served'},
            {'name': 'Kompot', 'quantity': 3, 'price': 900, 'status': 'cancelled'},
          ],
        },
      ],
      'reservations': [
        {
          'name': 'Nowak',
          'party': 4,
          'starts_at': '2026-10-30T13:00:00Z',
          'ends_at': '2026-10-30T15:00:00Z',
          'seated': true,
          'table_ids': ['t5'],
        },
      ],
      'takeaway': [
        {'order_id': 'o3', 'label': '#4 dostawa', 'stage': 'on_the_way', 'total': 6400},
      ],
      'staff': [
        {'name': 'Anna', 'since': '2026-10-30T07:00:00Z'},
      ],
    });
    expect(tm.bills.single.total, 6400);
    expect(tm.billAt('t1')?.orderId, 'o1');
    expect(tm.billAt('t5'), isNull);
    expect(tm.reservationAt('t5')?.name, 'Nowak');
    expect(tm.takeaway.single.stageLabel, 'w drodze');
    expect(tm.staff.single.$1, 'Anna');
  });
}
