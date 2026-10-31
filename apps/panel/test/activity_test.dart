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

  test('Time Machine z całej doby: stan w każdej chwili liczony w panelu', () {
    final day = TimeMachineDay.fromJson({
      'bills': [
        {
          'order_id': 'o1',
          'table_id': 't1',
          'label': 'Stolik 1',
          'opened_at': '2026-10-30T12:00:00Z',
          'closed_at': '2026-10-30T14:00:00Z',
          'opened_by': 'Marek',
          'guests': 2,
          'payments': [
            {'at': '2026-10-30T13:50:00Z', 'amount': 5000},
          ],
          'items': [
            {
              'name': 'Pierogi',
              'quantity': 2,
              'price': 3200,
              'created_at': '2026-10-30T12:05:00Z',
              'sent_at': '2026-10-30T12:06:00Z',
              'ready_at': '2026-10-30T12:20:00Z',
              'served_at': '2026-10-30T12:25:00Z',
            },
            {
              'name': 'Kompot',
              'quantity': 1,
              'price': 900,
              'created_at': '2026-10-30T12:30:00Z',
              'cancelled_at': '2026-10-30T12:40:00Z',
            },
            {'name': 'Stare', 'quantity': 1, 'price': 100, 'created_at': '2026-10-30T12:01:00Z', 'cancelled': true},
          ],
        },
      ],
      'reservations': [
        {
          'name': 'Nowak',
          'party': 4,
          'starts_at': '2026-10-30T13:00:00Z',
          'ends_at': '2026-10-30T15:00:00Z',
          'created_at': '2026-10-30T09:00:00Z',
          'seated_at': '2026-10-30T13:10:00Z',
          'table_ids': ['t5'],
        },
      ],
      'takeaway': [
        {
          'order_id': 'o3',
          'label': '#4 dostawa',
          'kind': 'delivery',
          'fulfillment': 'delivered',
          'opened_at': '2026-10-30T12:10:00Z',
          'accepted_at': '2026-10-30T12:12:00Z',
          'ready_at': '2026-10-30T12:40:00Z',
          'picked_up_at': '2026-10-30T12:45:00Z',
          'delivered_at': '2026-10-30T13:05:00Z',
          'total': 6400,
        },
        {
          'order_id': 'o4',
          'label': '#5 odbiór',
          'kind': 'pickup',
          'fulfillment': 'rejected',
          'opened_at': '2026-10-30T12:50:00Z',
          'closed_at': '2026-10-30T12:55:00Z',
          'total': 1000,
        },
      ],
      'staff': [
        {'name': 'Anna', 'started_at': '2026-10-30T07:00:00Z', 'ended_at': '2026-10-30T13:00:00Z'},
        {'name': 'Marek', 'started_at': '2026-10-30T11:00:00Z'},
      ],
    });

    final early = day.at(DateTime.parse('2026-10-30T12:10:00Z'));
    final bill = early.billAt('t1')!;
    expect([for (final i in bill.items) i.status], ['sent', 'cancelled']);
    expect(bill.total, 6400);
    expect(bill.paid, 0);
    expect(early.takeaway.single.stage, 'placed');
    expect(early.staff.map((s) => s.$1), ['Anna', 'Marek']);
    expect(early.reservations, isEmpty);

    final middle = day.at(DateTime.parse('2026-10-30T12:52:00Z'));
    expect([for (final i in middle.billAt('t1')!.items) i.status], ['served', 'cancelled', 'cancelled']);
    expect(middle.takeaway.map((t) => t.stage), ['on_the_way', 'placed']);

    final late = day.at(DateTime.parse('2026-10-30T13:55:00Z'));
    expect(late.billAt('t1')!.paid, 5000);
    expect(late.reservationAt('t5')!.seated, isTrue);
    expect(late.takeaway, isEmpty);
    expect(late.staff.single.$1, 'Marek');

    final closed = day.at(DateTime.parse('2026-10-30T14:00:00Z'));
    expect(closed.bills, isEmpty);
  });
}
