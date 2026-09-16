import 'package:intl/intl.dart';

import 'units.dart';

export 'units.dart';

abstract final class Fmt {
  static final _price = NumberFormat.currency(
    locale: 'pl_PL',
    symbol: 'zł',
    decimalDigits: 2,
  );
  static final _time = DateFormat.Hm('pl_PL');
  static final _dayShort = DateFormat('EEE d MMM', 'pl_PL');
  static final _dayLong = DateFormat('EEEE, d MMMM', 'pl_PL');
  static final _monthYear = DateFormat('LLLL yyyy', 'pl_PL');
  static final _weekdayShort = DateFormat('EEE', 'pl_PL');
  static final _rating = NumberFormat('0.0', 'pl_PL');

  static String price(int grosze) => _price.format(grosze / 100);

  static String time(DateTime value) => _time.format(value.toLocal());

  static String dayShort(DateTime value) => _dayShort.format(value.toLocal());

  static String dayLong(DateTime value) => _dayLong.format(value.toLocal());

  static String dateTime(DateTime value) => '${dayLong(value)}, ${time(value)}';

  static String monthYear(DateTime value) =>
      capitalize(_monthYear.format(value.toLocal()));

  static String weekdayShort(DateTime value) =>
      capitalize(_weekdayShort.format(value.toLocal()).replaceAll('.', ''));

  static String rating(double value) => _rating.format(value);

  static final _oneDecimal = NumberFormat('0.0', 'pl_PL');

  static String distance(
    double meters, [
    DistanceUnit unit = DistanceUnit.kilometers,
  ]) {
    switch (unit) {
      case DistanceUnit.kilometers:
        if (meters < 1000) return '${(meters / 10).round() * 10} m';
        return '${_oneDecimal.format(meters / 1000)} km';
      case DistanceUnit.miles:
        final miles = meters / 1609.344;
        if (miles < 0.1) return '${(meters * 3.28084 / 10).round() * 10} ft';
        return '${_oneDecimal.format(miles)} mi';
    }
  }

  /// Promień wyszukiwania podany w kilometrach, pokazany w wybranych jednostkach.
  static String radius(int kilometers, DistanceUnit unit) =>
      unit == DistanceUnit.kilometers
      ? '$kilometers km'
      : '${_oneDecimal.format(kilometers / 1.609344)} mi';

  /// Numer z bazy, na przykład 48511448098, w postaci +48 511 448 098.
  static String phone(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '–';
    if (digits.length == 11 && digits.startsWith('48')) {
      return '+48 ${digits.substring(2, 5)} ${digits.substring(5, 8)} ${digits.substring(8)}';
    }
    return '+$digits';
  }

  /// Poziom cen od $ do $$$$. Wartość pochodzi z kolumny price_level lokalu.
  static String priceLevel(int level) => r'$' * level.clamp(1, 4);

  static String capitalize(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  /// Liczebniki: 1 osoba, 2–4 osoby, 5+ osób, 12–14 osób.
  static String people(int count) =>
      _plural(count, one: 'osoba', few: 'osoby', many: 'osób');

  /// Biernik: na 1 osobę, na 2 osoby, na 5 osób.
  static String peopleAccusative(int count) =>
      _plural(count, one: 'osobę', few: 'osoby', many: 'osób');

  static String reviews(int count) =>
      _plural(count, one: 'opinia', few: 'opinie', many: 'opinii');

  static String restaurants(int count) =>
      _plural(count, one: 'lokal', few: 'lokale', many: 'lokali');

  static String _plural(
    int count, {
    required String one,
    required String few,
    required String many,
  }) {
    if (count == 1) return '1 $one';
    final lastTwo = count % 100;
    final last = count % 10;
    if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
      return '$count $few';
    }
    return '$count $many';
  }
}
