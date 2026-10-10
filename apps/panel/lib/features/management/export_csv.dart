import '../../data/models.dart';

/// Dane miesiąca do eksportu: rachunki z VAT, czas pracy i petty cash (`panel_export_month`).
class MonthExport {
  const MonthExport({required this.orders, required this.hours, required this.petty});

  final List<ExportOrder> orders;
  final List<ExportHours> hours;
  final List<ExportPetty> petty;

  /// Stawki VAT, które wystąpiły w miesiącu, od najwyższej.
  List<int> get rates => ({for (final o in orders) for (final v in o.vat.keys) v}.toList()..sort((a, b) => b.compareTo(a)));

  int get revenueGrosze => orders.fold(0, (s, o) => s + o.totalGrosze);

  factory MonthExport.fromJson(Map<String, dynamic> json) => MonthExport(
    orders: [for (final o in (json['orders'] as List? ?? const [])) ExportOrder.fromJson(o as Map<String, dynamic>)],
    hours: [for (final h in (json['hours'] as List? ?? const [])) ExportHours.fromJson(h as Map<String, dynamic>)],
    petty: [for (final p in (json['petty'] as List? ?? const [])) ExportPetty.fromJson(p as Map<String, dynamic>)],
  );
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// Zamknięty rachunek: wartość brutto według stawek VAT (przed rabatem), dostawa, rabat, napiwek i płatności.
class ExportOrder {
  const ExportOrder({
    required this.closedAt,
    required this.kind,
    required this.vat,
    required this.deliveryFeeGrosze,
    required this.discountGrosze,
    required this.tipGrosze,
    required this.payments,
    this.number,
    this.table,
  });

  final DateTime closedAt;

  /// dine_in, delivery albo pickup.
  final String kind;
  final int? number;
  final String? table;

  /// Stawka VAT → brutto pozycji przed rabatem.
  final Map<int, int> vat;
  final int deliveryFeeGrosze;
  final int discountGrosze;
  final int tipGrosze;

  /// Forma → kwota bez napiwku: cash, card, card_online, other.
  final Map<String, int> payments;

  int get itemsGrosze => vat.values.fold(0, (a, b) => a + b);
  int get totalGrosze => itemsGrosze + deliveryFeeGrosze - discountGrosze;

  /// Brutto według stawek po rabacie rozłożonym proporcjonalnie (reszta groszy na ostatnią stawkę).
  Map<int, int> get vatAfterDiscount {
    if (discountGrosze == 0 || itemsGrosze == 0) return vat;
    final rates = vat.keys.toList()..sort((a, b) => b.compareTo(a));
    final result = <int, int>{};
    var left = discountGrosze;
    for (final (i, r) in rates.indexed) {
      final share = i == rates.length - 1 ? left : (discountGrosze * vat[r]! / itemsGrosze).round();
      left -= share;
      result[r] = vat[r]! - share;
    }
    return result;
  }

  String get kindLabel => switch (kind) {
    'delivery' => 'Dostawa',
    'pickup' => 'Odbiór',
    _ => 'Sala',
  };

  factory ExportOrder.fromJson(Map<String, dynamic> json) {
    final payments = <String, int>{};
    final list = json['payments'] as List? ?? const [];
    final total = [for (final v in (json['vat'] as List? ?? const [])) _int((v as Map)['gross'])].fold(0, (a, b) => a + b) +
        _int(json['delivery_fee']) -
        _int(json['discount']);
    if (list.isEmpty) {
      // Starsze rachunki i zamówienia na wynos: jedna płatność zapisana w samym zamówieniu.
      final method = json['payment_choice'] == 'card_online'
          ? 'card_online'
          : (json['payment_method'] == 'cash' || json['payment_method'] == 'card')
          ? json['payment_method'] as String
          : 'other';
      payments[method] = total;
    } else {
      for (final p in list.cast<Map<String, dynamic>>()) {
        final m = p['method'] as String? ?? 'other';
        payments[m] = (payments[m] ?? 0) + _int(p['amount']);
      }
    }
    return ExportOrder(
      closedAt: DateTime.parse(json['closed_at'] as String).toLocal(),
      kind: json['kind'] as String? ?? 'dine_in',
      number: json['number'] == null ? null : _int(json['number']),
      table: json['table'] as String?,
      vat: {for (final v in (json['vat'] as List? ?? const []).cast<Map<String, dynamic>>()) _int(v['rate']): _int(v['gross'])},
      deliveryFeeGrosze: _int(json['delivery_fee']),
      discountGrosze: _int(json['discount']),
      tipGrosze: _int(json['tip']),
      payments: payments,
    );
  }
}

class ExportHours {
  const ExportHours({required this.name, required this.contract, required this.shifts, required this.seconds, this.position, this.rateGrosze});

  final String name;
  final String? position;
  final Contract contract;
  final int? rateGrosze;
  final int shifts;
  final int seconds;

  int? get earningsGrosze => rateGrosze == null ? null : (seconds * rateGrosze! / 3600).round();

  factory ExportHours.fromJson(Map<String, dynamic> json) => ExportHours(
    name: json['name'] as String? ?? '',
    position: json['position'] as String?,
    contract: Contract.from(json['contract']),
    rateGrosze: json['rate'] == null ? null : _int(json['rate']),
    shifts: _int(json['shifts']),
    seconds: _int(json['seconds']),
  );
}

class ExportPetty {
  const ExportPetty({required this.day, required this.out, required this.description, required this.amountGrosze, required this.createdAt, this.author});

  final DateTime day;
  final bool out;
  final String description;
  final int amountGrosze;
  final DateTime createdAt;
  final String? author;

  factory ExportPetty.fromJson(Map<String, dynamic> json) => ExportPetty(
    day: DateTime.parse(json['day'] as String),
    out: json['kind'] != 'in',
    description: json['description'] as String? ?? '',
    amountGrosze: _int(json['amount']),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    author: json['author'] as String?,
  );
}

// ---------------------------------------------------------------
// CSV dla polskiego Excela: średnik, przecinek dziesiętny, UTF-8 z BOM.
// ---------------------------------------------------------------

String _two(int n) => n.toString().padLeft(2, '0');
String csvDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String csvTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// Kwota w groszach jako „1234,50”.
String csvMoney(int grosze) {
  final sign = grosze < 0 ? '-' : '';
  final a = grosze.abs();
  return '$sign${a ~/ 100},${_two(a % 100)}';
}

String _cell(Object? v) {
  final s = v?.toString() ?? '';
  return s.contains(RegExp(r'[;"\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String csv(List<List<Object?>> rows) => '﻿${rows.map((r) => r.map(_cell).join(';')).join('\r\n')}\r\n';

int _net(int gross, int rate) => (gross * 100 / (100 + rate)).round();

List<String> _vatHeader(List<int> rates) => [for (final r in rates) ...['Brutto $r%', 'Netto $r%', 'VAT $r%']];

List<String> _vatCells(Map<int, int> gross, List<int> rates) => [
  for (final r in rates) ...[
    csvMoney(gross[r] ?? 0),
    csvMoney(_net(gross[r] ?? 0, r)),
    csvMoney((gross[r] ?? 0) - _net(gross[r] ?? 0, r)),
  ],
];

const _methods = ['cash', 'card', 'card_online', 'other'];
const _methodHeader = ['Gotówka', 'Karta (terminal)', 'Karta online', 'Inne'];

/// Tabela do eksportu: ta sama dla PDF i CSV. Ostatni wiersz [footer] to suma (pogrubiona w PDF).
class ExportTable {
  const ExportTable({required this.title, required this.header, required this.rows, this.footer, this.numeric = const {}});

  final String title;
  final List<String> header;
  final List<List<String>> rows;
  final List<String>? footer;

  /// Kolumny z liczbami i kwotami (w PDF wyrównane do prawej).
  final Set<int> numeric;

  String get csvText => csv([header, ...rows, ?footer]);
}

Set<int> _from(int first, int count) => {for (var i = first; i < first + count; i++) i};

/// Każdy rachunek w osobnym wierszu, z sumą na końcu.
ExportTable salesTable(MonthExport e) {
  final rates = e.rates;
  final header = ['Data', 'Godzina', 'Rodzaj', 'Stolik / numer', ..._vatHeader(rates), 'Dostawa', 'Rabat', 'Razem', ..._methodHeader, 'Napiwek'];
  final rows = <List<String>>[];
  final sumVat = <int, int>{};
  final sumPay = <String, int>{};
  var fee = 0, discount = 0, total = 0, tips = 0;
  for (final o in e.orders) {
    final gross = o.vatAfterDiscount;
    gross.forEach((r, g) => sumVat[r] = (sumVat[r] ?? 0) + g);
    o.payments.forEach((m, a) => sumPay[m] = (sumPay[m] ?? 0) + a);
    fee += o.deliveryFeeGrosze;
    discount += o.discountGrosze;
    total += o.totalGrosze;
    tips += o.tipGrosze;
    rows.add([
      csvDate(o.closedAt),
      csvTime(o.closedAt),
      o.kindLabel,
      o.kind == 'dine_in' ? (o.table ?? '') : '#${o.number ?? ''}',
      ..._vatCells(gross, rates),
      csvMoney(o.deliveryFeeGrosze),
      csvMoney(o.discountGrosze),
      csvMoney(o.totalGrosze),
      for (final m in _methods) csvMoney(o.payments[m] ?? 0),
      csvMoney(o.tipGrosze),
    ]);
  }
  return ExportTable(
    title: 'Sprzedaż: rachunki',
    header: header,
    rows: rows,
    footer: [
      'Razem', '', '${e.orders.length} rachunków', '',
      ..._vatCells(sumVat, rates),
      csvMoney(fee), csvMoney(discount), csvMoney(total),
      for (final m in _methods) csvMoney(sumPay[m] ?? 0),
      csvMoney(tips),
    ],
    numeric: _from(4, header.length - 4),
  );
}

String salesCsv(MonthExport e) => salesTable(e).csvText;

/// Zestawienie dzienne: jeden wiersz na dzień ze sprzedażą, na końcu suma miesiąca.
ExportTable dailyTable(MonthExport e) {
  final rates = e.rates;
  final byDay = <String, List<ExportOrder>>{};
  for (final o in e.orders) {
    byDay.putIfAbsent(csvDate(o.closedAt), () => []).add(o);
  }
  final header = ['Data', 'Rachunki', ..._vatHeader(rates), 'Dostawa', 'Rabaty', 'Razem', ..._methodHeader, 'Napiwki'];
  List<String> line(String label, List<ExportOrder> list) {
    final vat = <int, int>{};
    final pay = <String, int>{};
    for (final o in list) {
      o.vatAfterDiscount.forEach((r, g) => vat[r] = (vat[r] ?? 0) + g);
      o.payments.forEach((m, a) => pay[m] = (pay[m] ?? 0) + a);
    }
    return [
      label,
      '${list.length}',
      ..._vatCells(vat, rates),
      csvMoney(list.fold(0, (s, o) => s + o.deliveryFeeGrosze)),
      csvMoney(list.fold(0, (s, o) => s + o.discountGrosze)),
      csvMoney(list.fold(0, (s, o) => s + o.totalGrosze)),
      for (final m in _methods) csvMoney(pay[m] ?? 0),
      csvMoney(list.fold(0, (s, o) => s + o.tipGrosze)),
    ];
  }

  final days = byDay.keys.toList()..sort();
  return ExportTable(
    title: 'Sprzedaż: dzień po dniu',
    header: header,
    rows: [for (final day in days) line(day, byDay[day]!)],
    footer: e.orders.isEmpty ? null : line('Razem', e.orders),
    numeric: _from(1, header.length - 1),
  );
}

String dailyCsv(MonthExport e) {
  // CSV bez wiersza sumy (jak dotąd: arkusz sam sumuje kolumny).
  final t = dailyTable(e);
  return csv([t.header, ...t.rows]);
}

/// Czas pracy i wynagrodzenia: godziny dziesiętne, stawka, zarobek brutto i szacowane netto z umowy.
ExportTable hoursTable(MonthExport e) {
  final header = ['Pracownik', 'Stanowisko', 'Umowa', 'Zmiany', 'Godziny', 'Stawka brutto za godzinę', 'Zarobek brutto', 'Zarobek netto (szacunek)'];
  final rows = <List<String>>[];
  var seconds = 0, shifts = 0, gross = 0, net = 0;
  for (final h in e.hours) {
    final earnings = h.earningsGrosze;
    seconds += h.seconds;
    shifts += h.shifts;
    if (earnings != null) {
      gross += earnings;
      net += Payroll.monthlyNet(h.contract, earnings);
    }
    rows.add([
      h.name,
      h.position ?? '',
      h.contract.label,
      '${h.shifts}',
      (h.seconds / 3600).toStringAsFixed(2).replaceAll('.', ','),
      h.rateGrosze == null ? '' : csvMoney(h.rateGrosze!),
      earnings == null ? '' : csvMoney(earnings),
      earnings == null ? '' : csvMoney(Payroll.monthlyNet(h.contract, earnings)),
    ]);
  }
  return ExportTable(
    title: 'Czas pracy i wynagrodzenia',
    header: header,
    rows: rows,
    footer: e.hours.isEmpty
        ? null
        : ['Razem', '', '', '$shifts', (seconds / 3600).toStringAsFixed(2).replaceAll('.', ','), '', csvMoney(gross), csvMoney(net)],
    numeric: {3, 4, 5, 6, 7},
  );
}

String hoursCsv(MonthExport e) {
  final t = hoursTable(e);
  return csv([t.header, ...t.rows]);
}

/// Petty cash z miesiąca: wydatki z kasy na minus, wpłaty na plus.
ExportTable pettyTable(MonthExport e) {
  final rows = <List<String>>[
    for (final p in e.petty)
      [
        csvDate(p.day),
        p.out ? 'Wydatek' : 'Wpłata',
        p.description,
        csvMoney(p.out ? -p.amountGrosze : p.amountGrosze),
        p.author ?? '',
        csvTime(p.createdAt),
      ],
  ];
  final sum = e.petty.fold(0, (s, p) => s + (p.out ? -p.amountGrosze : p.amountGrosze));
  return ExportTable(
    title: 'Petty cash',
    header: const ['Data', 'Rodzaj', 'Opis', 'Kwota', 'Wpisał', 'Godzina wpisu'],
    rows: rows,
    footer: e.petty.isEmpty ? null : ['Razem', '', '${e.petty.length} wpisów', csvMoney(sum), '', ''],
    numeric: const {3},
  );
}

String pettyCsv(MonthExport e) {
  final t = pettyTable(e);
  return csv([t.header, ...t.rows]);
}
