import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/app/app.dart';
import 'package:table_panel/data/models.dart';

Map<String, dynamic> _row(String id, {String? waiter, String? opener}) => {
  'id': id,
  'order_id': 'o1',
  'name': 'Pierogi',
  'addons': [],
  'unit_price_grosze': 3200,
  'vat_rate': 8,
  'quantity': 1,
  'course': 1,
  'status': 'sent',
  'created_at': '2026-09-29T10:00:00Z',
  'sent_at': '2026-09-29T10:00:00Z',
  'orders': {'table_id': 't1', 'opener': opener == null ? null : {'name': opener}},
  'member': waiter == null ? null : {'name': waiter},
};

void main() {
  test('bilecik kuchni pokazuje, kto nabił pozycje', () {
    final tickets = KitchenTicket.fromRows([
      _row('a', waiter: 'Anna Kowalska'),
      _row('b', waiter: 'Anna Kowalska'),
      _row('c', waiter: 'Ola Zielińska'),
    ]);
    expect(tickets.single.waiter, 'Anna Kowalska, Ola Zielińska');
  });

  test('bez nabijającego bilecik pokazuje tego, kto otworzył rachunek', () {
    expect(KitchenTicket.fromRows([_row('a', opener: 'Krystian Nowak')]).single.waiter, 'Krystian Nowak');
    expect(KitchenTicket.fromRows([_row('a')]).single.waiter, isNull);
  });

  test('propozycja w grafiku z godzinami pracownika', () {
    final shift = PlannedShift.fromJson({
      'id': 's1',
      'member_id': 'm1',
      'day': '2026-10-01',
      'starts': '08:00:00',
      'ends': '16:00:00',
      'status': 'changed',
      'change_starts': '10:00:00',
      'change_ends': '18:00:00',
      'reply': 'Rano mam zajęcia',
    });
    expect(shift.status, PlannedShiftStatus.changed);
    expect((shift.starts, shift.ends), ('08:00', '16:00'));
    expect((shift.changeStarts, shift.changeEnds), ('10:00', '18:00'));
    expect(shift.day, DateTime(2026, 10, 1));
  });

  test('statystyki pracownika liczą średni rachunek', () {
    final stats = MemberStats.fromJson({
      'seconds': 3600,
      'orders_closed': 4,
      'revenue': 10000,
      'top_items': [
        {'name': 'Piwo', 'quantity': 7},
      ],
    });
    expect(stats.averageOrder, 2500);
    expect(stats.topItems.single, ('Piwo', 7));
    expect(const MemberStats().averageOrder, 0);
  });

  test('zakładka Pracownicy dla uprawnienia Pracownicy albo samego Grafiku', () {
    expect(canOpenRoute(PanelRoutes.staff, {'staff'}), isTrue);
    expect(canOpenRoute(PanelRoutes.staff, {'schedule'}), isTrue);
    expect(canOpenRoute(PanelRoutes.staff, {'orders'}), isFalse);
    expect(canOpenRoute(PanelRoutes.reservations, {'orders'}), isFalse);
    expect(canOpenRoute(PanelRoutes.settings, {'profile'}), isTrue);
    expect(canOpenRoute(PanelRoutes.settings, {'orders'}), isFalse);
  });
}
