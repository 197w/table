import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/app/updater.dart';

void main() {
  test('nowsza wersja jest rozpoznana po każdej części numeru', () {
    expect(PanelUpdater.isNewer('0.2.0', '0.1.0'), isTrue);
    expect(PanelUpdater.isNewer('0.1.1', '0.1.0'), isTrue);
    expect(PanelUpdater.isNewer('1.0.0', '0.9.9'), isTrue);
    expect(PanelUpdater.isNewer('0.10.0', '0.9.0'), isTrue);
  });

  test('ta sama albo starsza wersja nie jest aktualizacją', () {
    expect(PanelUpdater.isNewer('0.1.0', '0.1.0'), isFalse);
    expect(PanelUpdater.isNewer('0.1.0', '0.2.0'), isFalse);
    // Numer kompilacji po plusie nie zmienia wersji.
    expect(PanelUpdater.isNewer('0.1.0+7', '0.1.0+3'), isFalse);
  });

  test('panel uruchomiony z folderu projektu się nie aktualizuje', () {
    expect(PanelUpdater.enabled, isFalse);
  });
}
