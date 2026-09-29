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

  test('zgłoszenie godzin przyjęte ze zmienionymi godzinami', () {
    final shift = PlannedShift.fromJson({
      'id': 's1',
      'member_id': 'm1',
      'day': '2026-10-01',
      'starts': '13:00:00',
      'ends': '20:00:00',
      'requested_starts': '12:00:00',
      'requested_ends': '20:00:00',
      'status': 'accepted',
      'note': 'rano szkoła',
      'answer': 'od 13',
    });
    expect(shift.status, PlannedShiftStatus.accepted);
    expect((shift.starts, shift.ends), ('13:00', '20:00'));
    expect((shift.requestedStarts, shift.requestedEnds), ('12:00', '20:00'));
    expect(shift.changed, isTrue);
    expect(shift.day, DateTime(2026, 10, 1));
  });

  test('godziny wpisane przez przełożonego nie są „zmienione”', () {
    final shift = PlannedShift.fromJson({
      'id': 's2',
      'member_id': 'm1',
      'day': '2026-10-02',
      'starts': '10:00:00',
      'ends': '18:00:00',
      'status': 'accepted',
    });
    expect(shift.requestedStarts, isNull);
    expect(shift.changed, isFalse);
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

  test('zakładki według uprawnień', () {
    expect(canOpenRoute(PanelRoutes.staff, {'staff'}), isTrue);
    expect(canOpenRoute(PanelRoutes.staff, {'schedule'}), isTrue);
    expect(canOpenRoute(PanelRoutes.staff, {'staff_logins'}), isTrue);
    expect(canOpenRoute(PanelRoutes.staff, {'orders'}), isFalse);
    expect(canOpenRoute(PanelRoutes.reservations, {'orders'}), isFalse);
    expect(canOpenRoute(PanelRoutes.settings, {'settings'}), isTrue);
    expect(canOpenRoute(PanelRoutes.settings, {'profile'}), isFalse);
    expect(canOpenRoute(PanelRoutes.profile, {'profile'}), isTrue);
  });

  test('zakładka dla adresu i konto restauracji z pełnym dostępem', () {
    expect(tabForRoute('/zamowienia?stolik=t1'), PanelRoutes.orders);
    expect(tabForRoute('/logowanie'), isNull);
    final account = ActingMember.account();
    expect(account.isAccount, isTrue);
    expect(account.dbMemberId, isNull);
    expect(account.permissions, containsAll(['orders_close', 'positions', 'settings']));
  });
}
