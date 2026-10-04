import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/features/staff/timesheet.dart';

void main() {
  test('poprawiona zmiana: godziny sprzed poprawki i różnica', () {
    final s = StaffShift.fromJson({
      'id': 's1',
      'member_id': 'm1',
      'started_at': '2026-10-03T07:50:00Z',
      'ended_at': '2026-10-03T16:05:00Z',
      'source': 'scan',
      'original_started_at': '2026-10-03T08:00:00Z',
      'original_ended_at': '2026-10-03T16:00:00Z',
      'edited_at': '2026-10-03T18:00:00Z',
    });
    expect(s.isEdited, isTrue);
    expect(s.originalDuration, const Duration(hours: 8));
    expect(s.editDifference, const Duration(minutes: 15));
    expect(diffText(s.editDifference!), '+0:15');
    expect(diffText(const Duration(minutes: -65)), '−1:05');
    final plain = StaffShift.fromJson({'id': 's2', 'member_id': 'm1', 'started_at': '2026-10-03T08:00:00Z'});
    expect(plain.isEdited, isFalse);
    expect(plain.editDifference, isNull);
  });

  test('spis: opakowania i reszta w gramach dają razem w gramach', () {
    final line = InventoryLine.fromJson({
      'item_id': 'i1',
      'name': 'Mąka',
      'unit': 'kg',
      'capacity': 50,
      'quantity': 1.05,
      'packages': 1,
      'loose': 2500,
    });
    expect(line.packages, 1);
    expect(line.loose, 2500);
    expect(line.portionTotalText, '52\u00a0500 g');
    expect(inventoryGrouped(1234567.5), '1\u00a0234\u00a0567,5');
    final pieces = InventoryLine.fromJson({'item_id': 'i2', 'name': 'Jajka', 'unit': 'szt', 'capacity': 30, 'quantity': 2});
    expect(pieces.portionTotalText, '60 szt.');
    expect(InventoryUnit.l.portionFactor, 1000);
    expect(InventoryUnit.g.portionFactor, 1);
  });

  test('podsumowanie dnia: gotówka w kasie po petty cash', () {
    final s = DaySummary.fromJson({
      'revenue': 150000,
      'orders': 12,
      'dine_in': 10,
      'takeaway': 2,
      'cash': 60000,
      'card': 80000,
      'card_online': 10000,
      'other': 0,
      'cancelled': 1,
      'petty_out': 1250,
      'petty_in': 5000,
      'petty': [
        {'id': 'p1', 'kind': 'out', 'description': 'Cytryny', 'amount_grosze': 1250, 'author_name': 'Anna', 'created_at': '2026-10-04T10:00:00Z'},
        {'id': 'p2', 'kind': 'in', 'description': 'Drobne', 'amount_grosze': 5000, 'created_at': '2026-10-04T08:00:00Z'},
      ],
      'report': {
        'fiscal_grosze': 150000,
        'terminals': [
          {'name': 'Terminal 1', 'grosze': 50000},
          {'name': 'Terminal 2', 'grosze': 30000},
        ],
        'cash_counted_grosze': 63750,
        'updated_at': '2026-10-04T22:00:00Z',
        'updated_by_name': 'Wiktor Godlewski',
      },
    });
    expect(s.expectedCashGrosze, 63750);
    expect(s.petty.first.out, isTrue);
    expect(s.petty.last.out, isFalse);
    expect(s.report!.terminalsGrosze, 80000);
    expect(s.report!.cashCountedGrosze, s.expectedCashGrosze);
    expect(DaySummary.fromJson({'petty': []}).report, isNull);
  });

  test('rachunek: rabat od części, równy podział i płatności', () {
    final due = OrderDue.fromJson({'total': 11000, 'discount': 1100, 'due': 9900, 'discount_label': 'REVE10 (−10%)', 'discount_percent': 10});
    expect(due.forPart(4200), (420, 3780));
    final amount = OrderDue.fromJson({'total': 11000, 'discount': 2000, 'due': 9000, 'discount_label': 'X (−20,00 zł)'});
    expect(amount.forPart(4200), (0, 4200));
    expect(splitEqually(9901, 3), [3301, 3300, 3300]);
    expect(splitEqually(100, 1), [100]);
    expect(const PaymentPart(PaymentMethod.card, 3780, tipGrosze: 500).toJson(), {'method': 'card', 'amount': 3780, 'tip': 500});
    final order = PanelOrder.fromJson({
      'id': 'o1', 'opened_at': '2026-10-04T10:00:00Z', 'status': 'paid', 'discount_grosze': 680,
      'discount_label': 'REVE10 (−10%)', 'tip_grosze': 200,
      'order_payments': [
        {'method': 'cash', 'amount_grosze': 3060, 'tip_grosze': 0},
        {'method': 'card', 'amount_grosze': 3060, 'tip_grosze': 200},
      ],
    });
    expect(order.payments.length, 2);
    expect(order.payments.last.method, PaymentMethod.card);
    expect(order.tipGrosze, 200);
  });

  test('kod rabatowy: wartość i wygaśnięcie', () {
    final c = DiscountCode.fromJson({'id': 'd1', 'code': 'REVE10', 'kind': 'percent', 'value': 10, 'active': true, 'uses': 2, 'max_uses': 2});
    expect(c.valueText, '−10%');
    expect(c.expired, isTrue);
    final a = DiscountCode.fromJson({'id': 'd2', 'code': 'ZIMA', 'kind': 'amount', 'value': 2000, 'active': true, 'uses': 0, 'valid_until': '2099-01-01'});
    expect(a.valueText, '−20,00 zł');
    expect(a.expired, isFalse);
  });

  test('rezerwacja w panelu: kod i zadatek', () {
    final r = PanelReservation.fromJson({
      'id': 'r', 'starts_at': '2026-10-05T17:00:00Z', 'ends_at': '2026-10-05T19:00:00Z', 'party_size': 6,
      'status': 'confirmed', 'source': 'app', 'guest_name': 'Ola', 'created_at': '2026-10-01T10:00:00Z',
      'table_ids': [], 'table_labels': [], 'from_app': true, 'guest_visits': 0, 'guest_no_shows': 0,
      'discount_code': 'ZIMA', 'discount_kind': 'amount', 'discount_value': 2000, 'deposit_grosze': 30000, 'deposit_status': 'paid',
    });
    expect(r.discountLabel, 'ZIMA −20,00 zł');
    expect(r.depositLabel, 'opłacony');
    final due = OrderDue.fromJson({'total': 25200, 'discount': 0, 'deposit': 20000, 'due': 5200});
    expect(due.depositGrosze, 20000);
    // Część rachunku nie odejmuje zadatku: rozlicza się on przy zamknięciu całości.
    expect(due.forPart(4200), (0, 4200));
  });

  test('lista oczekujących w panelu', () {
    final e = WaitlistEntry.fromJson({
      'id': 'w', 'party_size': 4, 'time_from': '18:00:00', 'time_to': '21:00:00', 'note': 'okno', 'status': 'waiting',
      'created_at': '2026-10-04T10:00:00Z', 'guest_name': 'Ola', 'guest_phone': '+48600100200', 'guest_visits': 2,
    });
    expect(e.from, '18:00');
    expect(e.offered, isFalse);
    expect(e.guestVisits, 2);
  });
}
