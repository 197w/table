import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/app/shell.dart';

void main() {
  test('kwadrat z ikoną jedzie w jedną stronę, bez wychylenia', () {
    expect(railSlot(0), kRailInner);
    expect(railSlot(1), 40);

    var previous = railSlot(0);
    for (var i = 1; i <= 100; i++) {
      final value = railSlot(i / 100);
      expect(value, lessThanOrEqualTo(previous));
      previous = value;
    }
  });
}
