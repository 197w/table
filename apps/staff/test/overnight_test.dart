import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_staff/announcements_screen.dart';
import 'package:table_staff/schedule_screen.dart';

void main() {
  test('dyspozycyjność przez północ: koniec wcześniej niż początek to następny dzień', () {
    const evening = TimeOfDay(hour: 18, minute: 0);
    expect(overnightHours(evening, const TimeOfDay(hour: 2, minute: 0)), isTrue);
    expect(overnightHours(evening, const TimeOfDay(hour: 24, minute: 0)), isFalse);
    expect(overnightHours(const TimeOfDay(hour: 10, minute: 0), evening), isFalse);
    expect(sameTime(evening, const TimeOfDay(hour: 18, minute: 0)), isTrue);
  });

  test('informacje: kiedy przyszła, dziś i wczoraj słowem', () {
    final now = DateTime(2026, 10, 10, 15);
    expect(announcementWhen(DateTime(2026, 10, 10, 9, 5), now), 'dziś, 09:05');
    expect(announcementWhen(DateTime(2026, 10, 9, 21, 0), now), 'wczoraj, 21:00');
  });
}
