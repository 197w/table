import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/app/app.dart';
import 'package:table_panel/app/sections.dart';

void main() {
  test('każda zakładka grupy i lokalu ma uprawnienie, nazwę i jedną grupę', () {
    for (final tab in allPanelTabs) {
      expect(permissionsForRoute(tab.route), isNotNull, reason: tab.route);
      expect(panelTabLabels[tab.route], isNotNull, reason: tab.route);
      expect(tabForRoute(tab.route), tab.route, reason: 'ścieżka ${tab.route} nie może zaczynać innej');
    }
    expect(PanelSection.forRoute(PanelRoutes.orders), PanelSection.reservations);
    expect(PanelSection.forRoute(PanelRoutes.inventory), PanelSection.management);
    expect(PanelSection.forRoute(PanelRoutes.menu), PanelSection.management);
    expect(PanelSection.forRoute(PanelRoutes.stats), PanelSection.management);
    expect(PanelSection.forRoute(PanelRoutes.daySummary), PanelSection.management);
    expect(PanelSection.forRoute(PanelRoutes.hours), PanelSection.management);
    expect(canOpenRoute(PanelRoutes.hours, {'timesheet'}), isTrue);
    expect(canOpenRoute(PanelRoutes.daySummary, {'orders'}), isFalse);
    expect(PanelSection.forRoute(PanelRoutes.fleet), PanelSection.deliveries);
    expect(PanelSection.forRoute(PanelRoutes.teamStats), PanelSection.staff);
    expect(PanelSection.forRoute(PanelRoutes.reviews), PanelSection.customers);
    expect(PanelSection.forRoute(PanelRoutes.profile), isNull);
    expect(placeTabs.map((t) => t.label), ['Ustawienia lokalu', 'Dane lokalu', 'Edycja sali']);
  });

  test('grupy według uprawnień: flota i klienci mają własne', () {
    expect(canOpenRoute(PanelRoutes.fleet, {'orders'}), isFalse);
    expect(canOpenRoute(PanelRoutes.fleet, {'fleet'}), isTrue);
    expect(canOpenRoute(PanelRoutes.customers, {'stats'}), isFalse);
    expect(canOpenRoute(PanelRoutes.customers, {'customers'}), isTrue);
    expect(canOpenRoute(PanelRoutes.teamStats, {'stats'}), isTrue);
    expect(canOpenRoute(PanelRoutes.settings, {'profile'}), isTrue);
  });
}
