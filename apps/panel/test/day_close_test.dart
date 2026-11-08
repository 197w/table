import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/models.dart';

DaySummary _summary({
  int card = 50000,
  int tipsCard = 2000,
  int online = 10000,
  int other = 0,
  int kaucja = 1500,
  int ordersNet = 40,
  int revenueNet = 92593,
}) => DaySummary(
  revenueGrosze: 100000,
  orders: 42,
  dineIn: 30,
  takeaway: 12,
  cashGrosze: 40000,
  cardGrosze: card,
  cardOnlineGrosze: online,
  otherGrosze: other,
  cancelled: 3,
  pettyOutGrosze: 0,
  pettyInGrosze: 0,
  petty: const [],
  tipsCardGrosze: tipsCard,
  ordersNet: ordersNet,
  revenueNetGrosze: revenueNet,
  kaucjaGrosze: kaucja,
  kaucjaCount: 30,
);

void main() {
  test('zamknięcie dnia 02:00: 01:30 to jeszcze poprzedni dzień, 02:30 już następny', () {
    const close = Duration(hours: 2);
    expect(parseDayClose('02:00'), close);
    expect(parseDayClose('00:00'), Duration.zero);
    expect(parseDayClose(null), Duration.zero);
    expect(businessDayOf(DateTime(2026, 11, 8, 1, 30), close), DateTime(2026, 11, 7));
    expect(businessDayOf(DateTime(2026, 11, 8, 2, 30), close), DateTime(2026, 11, 8));
    expect(businessDayOf(DateTime(2026, 11, 8, 1, 30), Duration.zero), DateTime(2026, 11, 8));
    expect(businessDayStart(DateTime(2026, 11, 7), close), DateTime(2026, 11, 7, 2));

    final order = UnclosedOrder(order: PanelOrder(id: 'o', openedAt: DateTime(2026, 11, 7, 23), items: const []));
    // Otwarte o 23:00, teraz 01:30: przy zamknięciu dnia 02:00 to ten sam dzień, przy północy już wcześniejszy.
    expect(order.fromEarlierDay(DateTime(2026, 11, 8, 1, 30), close), isFalse);
    expect(order.fromEarlierDay(DateTime(2026, 11, 8, 1, 30)), isTrue);
  });

  test('gotówka do koperty: raport minus online, terminale bez napiwków, inne i kaucja', () {
    final s = _summary(other: 3000);
    expect(envelopeCash(s, fiscalGrosze: null), isNull);
    // Bez wpisanych terminali: karty z panelu (50 000 + napiwki 2000) minus napiwki = 50 000.
    final fromPanel = envelopeCash(s, fiscalGrosze: 100000)!;
    expect(fromPanel.terminals, 50000);
    expect(fromPanel.total, 100000 - 10000 - 50000 - 3000 - 1500);
    // Wpisane terminale (z napiwkami kartą): odejmujemy je bez napiwków.
    final fromTerminals = envelopeCash(s, fiscalGrosze: 100000, terminalsGrosze: 53000)!;
    expect(fromTerminals.terminals, 51000);
    expect(fromTerminals.total, 100000 - 10000 - 51000 - 3000 - 1500);
  });

  test('średni rachunek: netto z raportu przez zamówienia netto, bez raportu netto z panelu', () {
    final s = _summary();
    expect(averageBill(s, fiscalNetGrosze: 80000), (grosze: 2000, fromReport: true));
    expect(averageBill(s), (grosze: 2315, fromReport: false));
    expect(averageBill(_summary(ordersNet: 0)), isNull);
  });

  test('podsumowanie dnia czyta zamówienia netto, kaucję i netto z raportu', () {
    final s = DaySummary.fromJson({
      'revenue': 1000,
      'orders': 3,
      'orders_net': 2,
      'revenue_net': 926,
      'kaucja_grosze': 150,
      'kaucja_count': 3,
      'day_close': '02:00',
      'report': {'fiscal_grosze': 1000, 'fiscal_net_grosze': 900, 'terminals': []},
    });
    expect(s.ordersNet, 2);
    expect(s.revenueNetGrosze, 926);
    expect(s.kaucjaGrosze, 150);
    expect(s.kaucjaCount, 3);
    expect(s.dayClose, '02:00');
    expect(s.report?.fiscalNetGrosze, 900);
    expect(InventoryItem.fromJson({'id': 'i', 'name': 'Cola 0,5 l', 'unit': 'szt', 'capacity': 1, 'deposit_grosze': 50}).depositGrosze, 50);
    expect(PanelRestaurant.fromJson({'id': 'r', 'name': 'REVE', 'day_close': '02:00'}).dayClose, const Duration(hours: 2));
  });
}
