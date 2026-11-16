/// Okres sezonowego działu menu (0088, 16.11.2026): od dnia do dnia, opcjonalnie co roku.
///
/// Wspólne dla panelu, Table i Table for employees, żeby dział znikał i wracał w tym samym dniu wszędzie.
/// Baza liczy to samo w `private.season_active` (dzień w strefie lokalu).
library;

const _months = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Okres działu: [from] i [to] to dni (włącznie). Przy [yearly] liczy się tylko miesiąc i dzień, a okres może
/// przechodzić przez Nowy Rok (1 grudnia – 6 stycznia).
class MenuSeason {
  MenuSeason({required DateTime from, required DateTime to, this.yearly = false}) : from = _day(from), to = _day(to);

  final DateTime from;
  final DateTime to;
  final bool yearly;

  /// Z kolumn bazy (`season_from`, `season_to`, `season_yearly`). Null, gdy dział nie jest sezonowy.
  static MenuSeason? fromJson(Map<String, dynamic> json) {
    final from = parseDbDay(json['season_from']);
    final to = parseDbDay(json['season_to']);
    if (from == null || to == null) return null;
    return MenuSeason(from: from, to: to, yearly: json['season_yearly'] == true);
  }

  /// „2026-12-01” z bazy na dzień (bez strefy, żeby dzień się nie przesunął).
  static DateTime? parseDbDay(Object? value) {
    if (value is! String || value.length < 10) return null;
    final y = int.tryParse(value.substring(0, 4));
    final m = int.tryParse(value.substring(5, 7));
    final d = int.tryParse(value.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// „2026-12-01” do zapisu w bazie.
  static String dbDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  static int _md(DateTime d) => d.month * 100 + d.day;

  /// Czy dzień z [at] (lokalny czas) mieści się w okresie.
  bool contains(DateTime at) {
    final d = _day(at);
    if (!yearly) return !d.isBefore(from) && !d.isAfter(to);
    final a = _md(from);
    final b = _md(to);
    final x = _md(d);
    return a <= b ? x >= a && x <= b : x >= a || x <= b;
  }

  /// Jednorazowy okres, który już minął (przy „co roku” nigdy).
  bool endedBefore(DateTime at) => !yearly && _day(at).isAfter(to);

  /// Jednorazowy okres, który jeszcze się nie zaczął.
  bool startsAfter(DateTime at) => !yearly && _day(at).isBefore(from);

  /// „1 gru – 6 sty, co roku” albo „1 gru 2026 – 6 sty 2027”.
  String get label {
    String d(DateTime t) => '${t.day} ${_months[t.month - 1]}';
    if (yearly) return '${d(from)} – ${d(to)}, co roku';
    if (from.year == to.year) return '${d(from)} – ${d(to)} ${to.year}';
    return '${d(from)} ${from.year} – ${d(to)} ${to.year}';
  }

  /// Stan w chwili [now] do pokazania przy dziale: „W menu teraz”, „Od 1 gru”, „Poza sezonem” albo „Zakończony”.
  String statusAt(DateTime now) {
    if (contains(now)) return 'W menu teraz';
    if (endedBefore(now)) return 'Zakończony';
    if (startsAfter(now)) return 'Od ${from.day} ${_months[from.month - 1]}';
    return 'Poza sezonem';
  }

  @override
  bool operator ==(Object other) =>
      other is MenuSeason && other.from == from && other.to == to && other.yearly == yearly;

  @override
  int get hashCode => Object.hash(from, to, yearly);
}

/// Gotowy okres do jednego kliknięcia przy tworzeniu działu („Lato”, „Święta”): zawsze co roku.
class MenuSeasonPreset {
  const MenuSeasonPreset(this.name, this.season);

  final String name;
  final MenuSeason Function() season;
}

// Daty wzorcowe: zima kończy się 29 lutego (rok 2028 jest przestępny), żeby w lata przestępne dzień 29 lutego
// też należał do zimy. Rok nie ma znaczenia przy „co roku”, liczy się miesiąc i dzień.
final menuSeasonPresets = <MenuSeasonPreset>[
  MenuSeasonPreset('Wiosna', () => MenuSeason(from: DateTime(2027, 3, 1), to: DateTime(2027, 5, 31), yearly: true)),
  MenuSeasonPreset('Lato', () => MenuSeason(from: DateTime(2027, 6, 1), to: DateTime(2027, 8, 31), yearly: true)),
  MenuSeasonPreset('Jesień', () => MenuSeason(from: DateTime(2027, 9, 1), to: DateTime(2027, 11, 30), yearly: true)),
  MenuSeasonPreset('Zima', () => MenuSeason(from: DateTime(2027, 12, 1), to: DateTime(2028, 2, 29), yearly: true)),
  MenuSeasonPreset('Święta', () => MenuSeason(from: DateTime(2027, 12, 1), to: DateTime(2028, 1, 6), yearly: true)),
];
