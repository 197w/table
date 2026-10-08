import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
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
  group('zamówienia na godzinę', () {
    test('godzina idzie do bazy w UTC, a „jak najszybciej” jako null', () {
      final at = DateTime(2026, 10, 8, 18, 30);
      expect(TakeawayCustomer(scheduledFor: at).toJson()['scheduled_for'], at.toUtc().toIso8601String());
      expect(const TakeawayCustomer().toJson(), containsPair('scheduled_for', null));
    });

    test('zamówienie czeka na kuchnię do kitchen_at', () {
      final o = TakeawayOrder.fromJson({
        'id': 'o1', 'kind': 'delivery', 'number': 4, 'fulfillment': 'accepted', 'opened_at': '2026-10-08T10:00:00Z',
        'scheduled_for': '2026-10-08T16:30:00Z', 'kitchen_at': '2026-10-08T15:50:00Z', 'order_items': [],
      });
      expect(o.scheduledFor!.isAtSameMomentAs(DateTime.parse('2026-10-08T16:30:00Z')), isTrue);
      expect(o.waitingForKitchen(DateTime.parse('2026-10-08T15:00:00Z')), isTrue);
      expect(o.waitingForKitchen(DateTime.parse('2026-10-08T15:51:00Z')), isFalse);
      expect(o.customer.scheduledFor, o.scheduledFor);
    });

    test('bilecik zaplanowany czeka w pasku do swojej pory', () {
      final tickets = KitchenTicket.fromRows([
        {
          ..._item('i1', 'sent', sentAt: '2026-10-08T15:50:00Z'),
          'orders': {'kind': 'pickup', 'number': 4, 'customer_name': 'Ola', 'scheduled_for': '2026-10-08T16:10:00Z'},
        },
        {
          ..._item('i2', 'sent', sentAt: '2026-10-08T10:05:00Z'),
          'order_id': 'o2',
          'orders': {'kind': 'dine_in', 'table_id': 't1'},
        },
      ]);
      final planned = tickets.firstWhere((t) => t.orderId == 'o1');
      final table = tickets.firstWhere((t) => t.orderId == 'o2');
      expect(planned.upcomingAt(DateTime.parse('2026-10-08T15:00:00Z')), isTrue);
      expect(planned.upcomingAt(DateTime.parse('2026-10-08T15:50:01Z')), isFalse);
      // Rachunek na sali nigdy nie czeka, nawet gdy zegar komputera się spóźnia.
      expect(table.upcomingAt(DateTime.parse('2026-10-08T10:00:00Z')), isFalse);
    });

    test('dzień i godzina', () {
      final now = DateTime(2026, 10, 8, 12);
      expect(dayTimeLabel(DateTime(2026, 10, 8, 18, 30), now), '18:30');
      expect(dayTimeLabel(DateTime(2026, 10, 9, 9, 5), now), 'jutro 09:05');
      expect(dayTimeLabel(DateTime(2026, 10, 10, 13), now), 'sb 10.10 13:00');
    });

    test('ustawienia kuchni z wyprzedzeniem', () {
      final c = KitchenConfig.fromJson({'kitchen_warn_minutes': 5, 'kitchen_late_minutes': 9, 'kitchen_lead_pickup_min': 15});
      expect(c.leadPickup, 15);
      expect(c.leadDelivery, 40);
    });
  });
  group('paczka 4: baza klientów i kropki', () {
    test('klient z firmą, NIP-em i adresem z zamówienia', () {
      final c = Customer.fromJson({
        'key': 'tel:777888999', 'name': 'Nowy Klient', 'phone': '+48 777 888 999', 'from_app': false,
        'company': 'Biuro XYZ', 'nip': '5423456789', 'address': 'Lipowa 14/3, Białystok', 'orders': 0,
      });
      expect(c.company, 'Biuro XYZ');
      expect(c.address, 'Lipowa 14/3, Białystok');
      expect(Customer.fromJson({'key': 'imie:x', 'name': 'X', 'company': ''}).company, isNull);
    });

    test('kropka znika po zajrzeniu do zakładki', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final news = container.read(tabNewsProvider.notifier);
      news.add(TabNews.pickup);
      news.add(TabNews.pickup);
      expect(container.read(tabNewsProvider), {TabNews.pickup});
      news.seen(TabNews.pickup);
      expect(container.read(tabNewsProvider), isEmpty);
    });
  });
}
