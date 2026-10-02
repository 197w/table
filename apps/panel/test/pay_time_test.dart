import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/features/fleet/fleet_screen.dart';

void main() {
  test('inwentaryzacja co miesiąc: koniec miesiąca nie przeskakuje do następnego', () {
    expect(nextInventoryDay('month', DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
    expect(nextInventoryDay('month', DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
    expect(nextInventoryDay('month', DateTime(2026, 3, 31)), DateTime(2026, 4, 30));
    expect(nextInventoryDay('month', DateTime(2026, 12, 15)), DateTime(2027, 1, 15));
    expect(monthStart(DateTime(2026, 10, 2, 13)), DateTime(2026, 10));
  });

  test('rejestracja i VIN wielkimi literami, jak przy Caps Locku', () {
    final f = UpperCaseFormatter();
    final out = f.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: 'bi 12abc', selection: TextSelection.collapsed(offset: 8)),
    );
    expect(out.text, 'BI 12ABC');
    expect(out.selection.baseOffset, 8);
  });

  test('statystyki pracownika: stawka i zarobek za miesiąc', () {
    final s = MemberStats.fromJson({'seconds': 144696, 'shifts': 6, 'rate': 3000, 'earnings': 120580});
    expect(s.rateGrosze, 3000);
    expect(s.earningsGrosze, 120580);
    final noRate = MemberStats.fromJson({'seconds': 3600, 'rate': null, 'earnings': null});
    expect(noRate.rateGrosze, isNull);
    expect(noRate.earningsGrosze, isNull);
    final team = TeamStat.fromJson({
      'member_id': 'm1', 'name': 'Anna', 'active': true, 'seconds': 7200, 'shifts': 1, 'orders_opened': 0,
      'orders_closed': 0, 'revenue': 0, 'items': 0, 'deliveries': 0, 'rate': 2500, 'earnings': 5000,
    });
    expect(team.earningsGrosze, 5000);
    expect(Vehicle.fromJson({'id': 'v', 'kind': 'car', 'name': 'Panda', 'vin': '1HGCM82633A004352'}).vin,
        '1HGCM82633A004352');
  });

  Future<TimeOfDay?> openWheel(WidgetTester tester, TimeOfDay initial, {required bool endOfDay}) async {
    TimeOfDay? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async =>
                  result = await showTimeWheel(context, initial: initial, allowEndOfDay: endOfDay),
              child: const Text('Wybierz'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Wybierz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gotowe'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('kółka godzin: 24:00 jako koniec dnia, a bez tej opcji najwyżej 23', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final midnight = await openWheel(tester, const TimeOfDay(hour: 24, minute: 0), endOfDay: true);
    expect(midnight?.hour, 24);
    expect(midnight?.minute, 0);

    final evening = await openWheel(tester, const TimeOfDay(hour: 21, minute: 30), endOfDay: false);
    expect(evening?.hour, 21);
    expect(evening?.minute, 30);

    // Bez końca dnia godzina 24 nie istnieje: 24:00 zamienia się na 23:00.
    final clamped = await openWheel(tester, const TimeOfDay(hour: 24, minute: 0), endOfDay: false);
    expect(clamped?.hour, 23);
  });
}
