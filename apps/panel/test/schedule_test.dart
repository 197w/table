import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/features/staff/timesheet.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pl_PL'));

  group('okres grafiku', () {
    final now = DateTime(2026, 10, 5, 12); // poniedziałek

    test('tydzień od poniedziałku', () {
      final p = schedulePeriod('week', 0, now);
      expect(p.from, DateTime(2026, 10, 5));
      expect(p.to, DateTime(2026, 10, 11));
      expect(schedulePeriod('week', 1, now).from, DateTime(2026, 10, 12));
    });

    test('2 tygodnie liczone od 5.01.2026, tak jak w aplikacji pracownika', () {
      final p = schedulePeriod('two_weeks', 0, now);
      // 5.10.2026 to 273 dni po 5.01.2026: 19 pełnych par tygodni i 7 dni, więc para zaczęła się 28.09.
      expect(p.from, DateTime(2026, 9, 28));
      expect(p.to, DateTime(2026, 10, 11));
      expect(periodWeeks(p), [DateTime(2026, 9, 28), DateTime(2026, 10, 5)]);
      expect(schedulePeriod('two_weeks', 1, now).from, DateTime(2026, 10, 12));
    });

    test('miesiąc to cały miesiąc w tygodniach od poniedziałku', () {
      final p = schedulePeriod('month', 0, now);
      expect(p.from, DateTime(2026, 10, 1));
      expect(p.to, DateTime(2026, 10, 31));
      final weeks = periodWeeks(p);
      expect(weeks.first, DateTime(2026, 9, 28));
      expect(weeks.last, DateTime(2026, 10, 26));
      expect(weeks, hasLength(5));
      expect(schedulePeriod('month', 3, now).from, DateTime(2027, 1, 1));
    });
  });

  group('niezapisane zmiany w grafiku', () {
    final day = DateTime(2026, 10, 12);
    final pending = PlannedShift(
      id: 's1',
      memberId: 'm1',
      day: day,
      starts: '10:00',
      ends: '18:00',
      status: PlannedShiftStatus.pending,
      requestedStarts: '10:00',
      requestedEnds: '18:00',
    );

    test('przyjęcie ze zmienionymi godzinami', () {
      final c = ScheduleChange(ScheduleAction.accept, memberId: 'm1', day: day, id: 's1', starts: '11:00', ends: '24:00');
      final shown = c.apply(pending)!;
      expect(shown.status, PlannedShiftStatus.accepted);
      expect(shown.changed, isTrue);
      expect('${shown.starts}–${shown.ends}', '11:00–24:00');
      expect(c.toJson(), containsPair('day', '2026-10-12'));
      expect(c.toJson(), containsPair('action', 'accept'));
    });

    test('odrzucenie, wolne i usunięcie', () {
      expect(ScheduleChange(ScheduleAction.reject, memberId: 'm1', day: day, id: 's1').apply(pending)!.status,
          PlannedShiftStatus.rejected);
      expect(ScheduleChange(ScheduleAction.off, memberId: 'm1', day: day).apply(null)!.off, isTrue);
      expect(ScheduleChange(ScheduleAction.delete, memberId: 'm1', day: day, id: 's1').apply(pending), isNull);
    });

    test('pusta odpowiedź nie idzie do bazy', () {
      final c = ScheduleChange(ScheduleAction.add, memberId: 'm1', day: day, starts: '9:00', ends: '17:00', answer: '  ');
      expect(c.toJson()['answer'], isNull);
      expect(c.key, scheduleKey('m1', DateTime(2026, 10, 12, 15)));
    });
  });

  testWidgets('poprawka zmiany dłuższej niż doba bierze dzień końca z bazy', (tester) async {
    // Zmiana od 1.10 0:15 do 2.10 18:09: wcześniej okno liczyło koniec od dnia początku (−24 h).
    final shift = StaffShift(
      id: 'x',
      memberId: 'm1',
      startedAt: DateTime(2026, 10, 1, 0, 15),
      endedAt: DateTime(2026, 10, 2, 18, 9),
    );
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ShiftDialog(
              members: const [StaffMember(id: 'm1', name: 'Anna Kowalska', color: 0, active: true)],
              shift: shift,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Czas zmiany: 41:54 h'), findsOneWidget);
    expect(find.text('18:09'), findsOneWidget);
  });
}
