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
}
