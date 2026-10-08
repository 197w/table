import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/features/orders/order_history_screen.dart';

Map<String, dynamic> _item(String id, String status, {String? sentAt, List<Map<String, dynamic>>? changes}) => {
  'id': id,
  'order_id': 'o1',
  'name': 'Pizza',
  'addons': [],
  'unit_price_grosze': 3000,
  'vat_rate': 8,
  'quantity': 1,
  'course': 1,
  'status': status,
  'created_at': '2026-10-08T10:00:00Z',
  'sent_at': sentAt,
  'changes': changes ?? [],
};

void main() {
  group('dane klienta zamówienia z panelu', () {
    test('dostawa wymaga imienia albo nazwy lokalu, telefonu, adresu i płatności', () {
      const empty = TakeawayCustomer();
      expect(empty.missing(OrderKind.delivery), [
        'imię i nazwisko albo nazwa lokalu',
        'telefon',
        'ulica',
        'numer domu albo lokalu',
        'miasto',
        'opłacone czy do opłacenia',
      ]);
      // Odbiór osobisty bez adresu.
      expect(empty.missing(OrderKind.pickup), ['imię i nazwisko albo nazwa lokalu', 'telefon', 'opłacone czy do opłacenia']);
    });

    test('nazwa lokalu zamiast imienia, NIP opcjonalny, ale 10 cyfr', () {
      const firm = TakeawayCustomer(company: 'Biuro ABC', phone: '+48 600 100 200', paid: true);
      expect(firm.missing(OrderKind.pickup), isEmpty);
      expect(const TakeawayCustomer(company: 'Biuro ABC', phone: '600100200', paid: true, nip: '123').missing(OrderKind.pickup),
          ['NIP (10 cyfr)']);
      final json = const TakeawayCustomer(
        name: ' Jan Kowalski ',
        phone: '600 100 200',
        nip: '542-345-67-89',
        street: 'Lipowa',
        house: '14/3',
        city: 'Białystok',
        paid: false,
      ).toJson();
      expect(json['name'], 'Jan Kowalski');
      expect(json['nip'], '5423456789');
      expect(json['paid'], isFalse);
    });

    test('zamówienie z panelu wraca do formularza z danymi i płatnością', () {
      final order = TakeawayOrder.fromJson({
        'id': 'd1',
        'kind': 'delivery',
        'number': 12,
        'fulfillment': 'draft',
        'opened_at': '2026-10-08T10:00:00Z',
        'customer_name': 'Biuro ABC',
        'customer_company': 'Biuro ABC',
        'customer_nip': '5423456789',
        'customer_phone': '600100200',
        'delivery_address': 'Lipowa 14/3, Białystok',
        'address_street': 'Lipowa',
        'address_house': '14/3',
        'address_city': 'Białystok',
        'delivery_note': 'Domofon 14',
        'staff_note': 'Stały klient',
        'delivery_fee_grosze': 800,
        'payment_choice': 'prepaid',
        'payment_status': 'paid',
        'guest_id': null,
        'order_items': [_item('i1', 'new')],
      });
      expect(order.stage, TakeawayStage.draft);
      expect(order.prepaid, isTrue);
      expect(order.fromApp, isFalse);
      expect(order.personName, isNull);
      final c = order.customer;
      expect(c.company, 'Biuro ABC');
      expect(c.name, '');
      expect(c.paid, isTrue);
      expect(c.missing(OrderKind.delivery), isEmpty);
      expect(order.totalGrosze, 3800);
    });

    test('historia klienta po telefonie', () {
      final c = CustomerLookup.fromJson({'orders': 3, 'spent_grosze': 24500, 'name': 'Jan Kowalski', 'address': 'Lipowa 1, Białystok'});
      expect(c.orders, 3);
      expect(c.known, isTrue);
      expect(CustomerLookup.fromJson({'orders': 0, 'spent_grosze': 0}).known, isFalse);
    });
  });

  test('zmiany składników w opisie pozycji i w bazie', () {
    final item = OrderItem.fromJson(_item('i1', 'sent', changes: [
      {'name': 'Cebula', 'kind': 'without', 'item_id': 'inv1'},
      {'name': 'Ser', 'kind': 'extra', 'item_id': null},
    ]));
    expect(item.details, 'bez: cebula, więcej: ser');
    expect(item.changes.first.toJson(), {'name': 'Cebula', 'kind': 'without', 'item_id': 'inv1'});
  });

  test('stolik czeka od najstarszej niewydanej pozycji z kuchni', () {
    final order = PanelOrder.fromJson({
      'id': 'o1',
      'opened_at': '2026-10-08T10:00:00Z',
      'order_items': [
        _item('a', 'served', sentAt: '2026-10-08T10:01:00Z'),
        _item('b', 'sent', sentAt: '2026-10-08T10:05:00Z'),
        _item('c', 'ready', sentAt: '2026-10-08T10:03:00Z'),
        _item('d', 'new'),
      ],
    });
    expect(order.waitingSince, DateTime.parse('2026-10-08T10:03:00Z').toLocal());
    final done = PanelOrder.fromJson({
      'id': 'o2',
      'opened_at': '2026-10-08T10:00:00Z',
      'order_items': [_item('a', 'served', sentAt: '2026-10-08T10:01:00Z')],
    });
    expect(done.waitingSince, isNull);
  });

  test('historia dzieli zamówienia na restaurację, dostawy i odbiór', () {
    PanelOrder order(String kind) => PanelOrder.fromJson({
      'id': kind,
      'opened_at': '2026-10-08T10:00:00Z',
      'kind': kind,
      'delivery_fee_grosze': kind == 'delivery' ? 800 : 0,
      'order_items': [_item('i', 'served')],
    });
    final orders = [order('dine_in'), order('delivery'), order('pickup')];
    expect(orders.where(HistoryKind.dineIn.matches).single.kind, OrderKind.dineIn);
    expect(orders.where(HistoryKind.delivery.matches).single.billGrosze, 3800);
    expect(orders.where(HistoryKind.pickup.matches).single.kind, OrderKind.pickup);
    expect(orders.where(HistoryKind.all.matches), hasLength(3));
  });
}
