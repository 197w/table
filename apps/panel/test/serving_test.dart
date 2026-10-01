import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_panel/app/app.dart';
import 'package:table_panel/app/idle_logout.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';

Map<String, dynamic> _item(
  String id,
  String order,
  String status, {
  int quantity = 1,
  String? readyAt,
  String sentAt = '2026-10-01T17:00:00Z',
  Map<String, dynamic>? orders,
}) => {
  'id': id,
  'order_id': order,
  'name': 'Danie $id',
  'quantity': quantity,
  'unit_price_grosze': 2000,
  'vat_rate': 8,
  'status': status,
  'course': 1,
  'addons': [],
  'created_at': '2026-10-01T16:58:00Z',
  'sent_at': sentAt,
  'ready_at': readyAt,
  'member': {'name': 'Kasia'},
  'orders': orders ?? {'table_id': 't1', 'status': 'open', 'kind': 'dine_in'},
};

void main() {
  test('wydanie: gotowe dania stolika, reszta na kuchni, na wynos tylko w przygotowaniu', () {
    const delivery = {'table_id': null, 'status': 'open', 'kind': 'delivery', 'number': 7, 'fulfillment': 'accepted'};
    const packed = {'table_id': null, 'status': 'open', 'kind': 'pickup', 'number': 8, 'fulfillment': 'ready'};
    final tickets = ServingTicket.fromRows([
      _item('a1', 'o1', 'ready', readyAt: '2026-10-01T17:06:00Z'),
      _item('a2', 'o1', 'sent', quantity: 2),
      // Stolik, w którym nic nie jest jeszcze gotowe: bez karty.
      _item('b1', 'o2', 'sent'),
      _item('c1', 'o3', 'ready', readyAt: '2026-10-01T17:03:00Z', orders: delivery),
      _item('c2', 'o3', 'sent', orders: delivery),
      // Spakowane na wynos czeka już w „Dostawach”.
      _item('d1', 'o4', 'ready', readyAt: '2026-10-01T17:01:00Z', orders: packed),
      // Napój bez kuchni: gotowy od wysłania.
      _item('e1', 'o5', 'ready', sentAt: '2026-10-01T17:04:00Z'),
    ]);

    expect(tickets.map((t) => t.orderId), ['o3', 'o5', 'o1']);
    final table = tickets.last;
    expect(table.items.map((i) => i.id), ['a1']);
    expect(table.cooking, 2);
    expect(table.waiter, 'Kasia');
    expect(table.isTakeaway, isFalse);

    final takeaway = tickets.first;
    expect(takeaway.takeawayLabel, 'Dostawa #7');
    expect(takeaway.items.map((i) => i.id), ['c1', 'c2']);
    expect(takeaway.allReady, isFalse);
    expect(takeaway.readyIds, ['c1']);
    expect(tickets[1].readySince.isAtSameMomentAs(DateTime.parse('2026-10-01T17:04:00Z')), isTrue);
  });

  test('zakładka Wydanie ma własne uprawnienie', () {
    expect(StaffPermission.values.map((p) => p.key), contains('serving'));
    expect(canOpenRoute(PanelRoutes.serving, {'serving'}), isTrue);
    expect(canOpenRoute(PanelRoutes.serving, {'kitchen'}), isFalse);
    expect(panelTabLabels[PanelRoutes.serving], 'Wydanie');
  });

  test('dane właściciela: puste, gdy wiersza nie ma, i wypełnione z bazy', () {
    final empty = OwnerDetails.fromJson(null);
    expect(empty.ownerName, isNull);
    expect(empty.nip, isNull);
    final d = OwnerDetails.fromJson({
      'owner_name': 'Jan Kowalski',
      'owner_phone': '600100200',
      'owner_email': 'jan@firma.pl',
      'company_name': 'Firma',
      'nip': '1234567890',
      'company_address': 'Rynek 1',
    });
    expect(d.ownerName, 'Jan Kowalski');
    expect(d.nip, '1234567890');
    expect(d.companyAddress, 'Rynek 1');
  });

  test('koniec zmiany: godziny zakończonej zmiany z odpowiedzi bazy', () {
    final m = ActingMember.fromJson({
      'member_id': 'm1',
      'name': 'Kasia Kelnerka',
      'permissions': ['orders'],
      'shift_started_at': null,
      'ended_shift_started_at': '2026-10-01T08:00:00Z',
      'ended_at': '2026-10-01T16:10:00Z',
    });
    expect(m.shiftStartedAt, isNull);
    expect(m.shiftEndedAt!.difference(m.endedShiftStartedAt!), const Duration(hours: 8, minutes: 10));
  });

  testWidgets('panel wylogowuje po 30 s bez ruchu, ruch liczy od nowa, kuchnia nie wylogowuje', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var path = PanelRoutes.orders;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: IdleLogout(
            location: () => path,
            navigators: const [],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    const anna = ActingMember(memberId: 'm1', name: 'Anna', permissions: {'orders'});
    container.read(panelMemberProvider.notifier).signIn(anna);
    await tester.pump();

    await tester.pump(const Duration(seconds: 20));
    expect(container.read(idleSecondsProvider), 20);

    // Ruch myszy zeruje licznik.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(const Offset(30, 30));
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(idleSecondsProvider), 1);
    expect(container.read(panelMemberProvider), isNotNull);

    await tester.pump(const Duration(seconds: 29));
    expect(container.read(panelMemberProvider), isNull);
    expect(container.read(idleSecondsProvider), 0);

    // Ekran kuchni zostaje zalogowany.
    path = PanelRoutes.kitchen;
    container.read(panelMemberProvider.notifier).signIn(anna);
    await tester.pump(const Duration(seconds: 90));
    expect(container.read(panelMemberProvider), isNotNull);

    container.read(panelMemberProvider.notifier).signOut();
    await mouse.removePointer();
    // Powiadomienie o wylogowaniu znika samo.
    await tester.pump(const Duration(seconds: 30));
  });
}
