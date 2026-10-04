import 'package:table_core/table_core.dart';

import 'app.dart';

/// Zakładka w bocznym pasku: ścieżka, nazwa w podpowiedzi i ikona.
class PanelTab {
  const PanelTab(this.route, this.label, this.icon);

  final String route;
  final String label;
  final AppIconData icon;
}

/// Grupy zakładek w górnym pasku. Wybrana grupa pokazuje swoje zakładki w bocznym pasku.
enum PanelSection {
  reservations('Rezerwacje', AppIcons.calendarDots, [
    PanelTab(PanelRoutes.reservations, 'Rezerwacje', AppIcons.calendarDots),
    PanelTab(PanelRoutes.orders, 'Zamówienia', AppIcons.receipt),
    PanelTab(PanelRoutes.history, 'Historia zamówień', AppIcons.clockBack),
    PanelTab(PanelRoutes.serving, 'Wydanie', AppIcons.callBell),
  ]),
  kitchen('Kuchnia', AppIcons.chefHat, [
    PanelTab(PanelRoutes.kitchen, 'Kuchnia', AppIcons.chefHat),
  ]),
  deliveries('Dostawy', AppIcons.moped, [
    PanelTab(PanelRoutes.deliveries, 'Dostawy', AppIcons.moped),
    PanelTab(PanelRoutes.fleet, 'Flota', AppIcons.car),
  ]),
  staff('Pracownicy', AppIcons.usersThree, [
    PanelTab(PanelRoutes.staff, 'Pracownicy', AppIcons.usersThree),
    PanelTab(PanelRoutes.teamStats, 'Statystyki', AppIcons.chartBarHorizontal),
  ]),
  customers('Baza klientów', AppIcons.addressBook, [
    PanelTab(PanelRoutes.customers, 'Klienci', AppIcons.userList),
    PanelTab(PanelRoutes.reviews, 'Opinie', AppIcons.chatCircle),
  ]),
  // Prowadzenie lokalu: koniec dnia, godziny pracowników, menu, inwentaryzacja i wyniki.
  management('Management', AppIcons.briefcase, [
    PanelTab(PanelRoutes.daySummary, 'Podsumowanie dnia', AppIcons.cashRegister),
    PanelTab(PanelRoutes.hours, 'Godziny pracy', AppIcons.clockUser),
    PanelTab(PanelRoutes.menu, 'Menu', AppIcons.bookOpen),
    PanelTab(PanelRoutes.inventory, 'Inwentaryzacja', AppIcons.package),
    PanelTab(PanelRoutes.stats, 'Statystyki', AppIcons.chartPie),
    PanelTab(PanelRoutes.discounts, 'Kody rabatowe', AppIcons.sealPercent),
  ]);

  const PanelSection(this.label, this.icon, this.tabs);

  final String label;
  final AppIconData icon;
  final List<PanelTab> tabs;

  /// Grupa, do której należy adres. Null: strona spoza grup (np. Dane lokalu).
  static PanelSection? forRoute(String location) {
    for (final section in values) {
      if (section.tabs.any((t) => location.startsWith(t.route))) return section;
    }
    return null;
  }

  static PanelSection? byName(String? name) {
    for (final section in values) {
      if (section.name == name) return section;
    }
    return null;
  }
}

/// Zakładki lokalu na dole bocznego paska, wspólne dla wszystkich grup.
const placeTabs = [
  PanelTab(PanelRoutes.settings, 'Ustawienia lokalu', AppIcons.gear),
  PanelTab(PanelRoutes.profile, 'Dane lokalu', AppIcons.storefront),
  PanelTab(PanelRoutes.floor, 'Edycja sali', AppIcons.blueprint),
];

/// Wszystkie zakładki panelu po kolei: grupy, a potem zakładki lokalu.
List<PanelTab> get allPanelTabs => [
  for (final section in PanelSection.values) ...section.tabs,
  ...placeTabs,
];
