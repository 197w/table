import 'package:material_ui/material_ui.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/features/profile/profile_screen.dart';
import 'package:table_panel/features/profile/schedule_conflicts.dart';

PanelReservation _res(DateTime start, {int minutes = 90}) => PanelReservation(
  id: 'r',
  startsAt: start,
  endsAt: start.add(Duration(minutes: minutes)),
  partySize: 2,
  status: ReservationStatus.confirmed,
  source: ReservationSource.phone,
  guestName: 'Anna',
  createdAt: DateTime(2026, 11, 1),
  tableIds: const [],
  tableLabels: const [],
  fromApp: false,
  guestVisits: 0,
  guestNoShows: 0,
);

void main() {
  test('zamknięcie nie później niż otwarcie to zamknięcie po północy', () {
    expect(closesNextDay(const TimeOfDay(hour: 12, minute: 0), const TimeOfDay(hour: 2, minute: 0)), isTrue);
    expect(closesNextDay(const TimeOfDay(hour: 12, minute: 0), const TimeOfDay(hour: 22, minute: 0)), isFalse);
    // 24:00 to północ tego samego dnia.
    expect(closesNextDay(const TimeOfDay(hour: 12, minute: 0), const TimeOfDay(hour: 24, minute: 0)), isFalse);
  });

  group('rezerwacje a godziny otwarcia po północy', () {
    // Piątek 27.11.2026 (ISO 5): 12:00–02:00 następnego dnia, reszta tygodnia 12:00–22:00.
    final weekly = [
      for (var d = 1; d <= 7; d++) OpeningHours(weekday: d, opens: '12:00', closes: d == 5 ? '02:00' : '22:00'),
    ];
    bool fits(DateTime start, {int minutes = 90, List<OpeningException> exceptions = const []}) =>
        reservationFitsHours(_res(start, minutes: minutes), weekly: weekly, exceptions: exceptions);

    test('wieczorem i po północy tego samego okna mieści się, po zamknięciu nie', () {
      expect(fits(DateTime(2026, 11, 27, 20)), isTrue);
      // 23:00 w piątek kończy się 00:30 w sobotę: nadal w oknie piątku.
      expect(fits(DateTime(2026, 11, 27, 23)), isTrue);
      // Sobota 00:30–02:00 to końcówka piątku.
      expect(fits(DateTime(2026, 11, 28, 0, 30)), isTrue);
      // Kończy się po 02:00: poza oknem.
      expect(fits(DateTime(2026, 11, 28, 1, 0)), isFalse);
      // Sobota rano przed otwarciem.
      expect(fits(DateTime(2026, 11, 28, 10)), isFalse);
    });

    test('zwykły dzień bez zmian, dzień zamknięty i dzień wyjątkowy po północy', () {
      // Czwartek 22:00 jest już po zamknięciu (22:00), a 20:00–21:30 w środku.
      expect(fits(DateTime(2026, 11, 26, 20)), isTrue);
      expect(fits(DateTime(2026, 11, 26, 21)), isFalse);
      final closed = [OpeningException(day: DateTime(2026, 11, 27), closed: true)];
      expect(fits(DateTime(2026, 11, 27, 20), exceptions: closed), isFalse);
      final late = [OpeningException(day: DateTime(2026, 11, 26), closed: false, opens: '18:00', closes: '01:00')];
      expect(fits(DateTime(2026, 11, 26, 23, 30), exceptions: late), isTrue);
      expect(fits(DateTime(2026, 11, 27, 0, 30), minutes: 30, exceptions: late), isTrue);
      expect(fits(DateTime(2026, 11, 27, 0, 30), exceptions: late), isFalse);
    });
  });
}
