import 'package:flutter_test/flutter_test.dart';
import 'package:table/data/models.dart';

void main() {
  MenuSection section(Map<String, dynamic> extra) => MenuSection.fromJson({
    'id': 's1',
    'name': 'Dział',
    'position': 0,
    'menu_items': const [],
    ...extra,
  });

  test('dział sezonowy jest w menu tylko w swoim okresie, co roku albo jednorazowo', () {
    final christmas = section({'season_from': '2026-12-01', 'season_to': '2027-01-06', 'season_yearly': true});
    expect(christmas.visibleAt(DateTime(2026, 12, 24, 19)), isTrue);
    expect(christmas.visibleAt(DateTime(2031, 1, 3)), isTrue);
    expect(christmas.visibleAt(DateTime(2031, 7, 15)), isFalse);

    final once = section({'season_from': '2026-06-01', 'season_to': '2026-08-31', 'season_yearly': false});
    expect(once.visibleAt(DateTime(2026, 8, 31, 23, 59)), isTrue);
    expect(once.visibleAt(DateTime(2027, 7, 1)), isFalse);
  });

  test('zwykły dział jest zawsze, a dział na wydarzenie tylko w jego czasie', () {
    expect(section({}).visibleAt(DateTime(2026, 7, 1)), isTrue);
    final event = section({
      'event_id': 'e1',
      'event': {'starts_at': '2026-11-20T17:00:00Z', 'ends_at': '2026-11-20T21:00:00Z'},
    });
    expect(event.visibleAt(DateTime.utc(2026, 11, 20, 18)), isTrue);
    expect(event.visibleAt(DateTime.utc(2026, 11, 21)), isFalse);
  });
}
