import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/features/management/export_csv.dart';

void main() {
  final month = MonthExport.fromJson({
    'orders': [
      {
        'closed_at': '2026-10-02T15:40:00Z',
        'kind': 'dine_in',
        'table': '11',
        'payment_method': 'cash',
        'delivery_fee': 0,
        'discount': 2050,
        'tip': 0,
        'vat': [
          {'rate': 23, 'gross': 2100},
          {'rate': 8, 'gross': 18400},
        ],
        'payments': [],
      },
      {
        'closed_at': '2026-10-02T18:00:00Z',
        'kind': 'delivery',
        'number': 7,
        'payment_choice': 'card_online',
        'payment_method': 'card',
        'delivery_fee': 900,
        'discount': 0,
        'tip': 300,
        'vat': [
          {'rate': 8, 'gross': 5000},
        ],
        'payments': [
          {'method': 'card', 'amount': 3000, 'tip': 300},
          {'method': 'cash', 'amount': 2900, 'tip': 0},
        ],
      },
    ],
    'hours': [
      {'name': 'Anna "Ania" Kowalska', 'position': 'Kelner', 'contract': 'zlecenie', 'rate': 3000, 'shifts': 2, 'seconds': 27000},
    ],
    'petty': [
      {'day': '2026-10-02', 'kind': 'out', 'description': 'Cytryny; limonki', 'amount': 1250, 'author': 'Anna', 'created_at': '2026-10-02T11:00:00Z'},
    ],
  });

  test('rabat rozkłada się na stawki VAT proporcjonalnie', () {
    final o = month.orders.first;
    expect(o.totalGrosze, 18450);
    final after = o.vatAfterDiscount;
    expect(after[23]! + after[8]!, 18450);
    expect(after[23], 2100 - 210);
    expect(month.rates, [23, 8]);
  });

  test('kwoty z przecinkiem i pola z cudzysłowem', () {
    expect(csvMoney(123450), '1234,50');
    expect(csvMoney(-1250), '-12,50');
    expect(csvMoney(5), '0,05');
    final petty = pettyCsv(month);
    expect(petty.startsWith('﻿'), isTrue);
    expect(petty, contains('"Cytryny; limonki";-12,50'));
    final hours = hoursCsv(month);
    expect(hours, contains('"Anna ""Ania"" Kowalska";Kelner;Umowa zlecenie;2;7,50;30,00;225,00;'));
  });

  test('sprzedaż: płatności według form i suma na końcu', () {
    final sales = salesCsv(month).split('\r\n');
    expect(sales.first, contains('Brutto 23%;Netto 23%;VAT 23%;Brutto 8%'));
    // Starszy rachunek bez listy płatności: cała kwota gotówką.
    expect(sales[1], contains('Sala;11;'));
    expect(sales[1], endsWith(';184,50;184,50;0,00;0,00;0,00;0,00'));
    expect(sales[2], contains('Dostawa;#7;'));
    expect(sales[2], endsWith(';59,00;29,00;30,00;0,00;0,00;3,00'));
    expect(sales[3], startsWith('Razem;;2 rachunków;'));
    final daily = dailyCsv(month).split('\r\n');
    expect(daily.length, 3); // nagłówek, jeden dzień i pusty koniec po ostatnim wierszu
    expect(daily[1], startsWith('2026-10-02;2;'));
  });
}
