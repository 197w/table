import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'calendar_screen.dart';
import 'data.dart';
import 'ui.dart';

const _tabular = [FontFeature.tabularFigures()];
const _weekdays = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];
const _weekdaysMini = ['P', 'W', 'Ś', 'C', 'P', 'S', 'N'];
const _weekdaysFull = ['Poniedziałek', 'Wtorek', 'Środa', 'Czwartek', 'Piątek', 'Sobota', 'Niedziela'];
const _months = [
  'Styczeń', 'Luty', 'Marzec', 'Kwiecień', 'Maj', 'Czerwiec',
  'Lipiec', 'Sierpień', 'Wrzesień', 'Październik', 'Listopad', 'Grudzień',
];
const _monthsShort = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];
const _monthsGenitive = [
  'stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca',
  'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia',
];

/// Dziś na czerwono, jak w Apple Calendar.
const _red = Color(0xFFEB5757);

/// Kolor zgłoszenia, które czeka na decyzję przełożonego (czytelny w obu motywach).
Color get _pending => StaffColors.pending;

/// Kolor wolnego dnia (daje go przełożony w panelu).
Color get _off => StaffColors.info;

/// Kolor propozycji przełożonego, na którą czeka moja odpowiedź.
Color get _proposed => StaffColors.proposal;

/// Stan dnia w grafiku: słowo, ikona i kolor (nie sam kolor). Dzień bez zgłoszenia przed oknem zgłaszania
/// ([closed]) jest „Niedostępny”, po nim ([later]) zgłasza się go później.
({String label, AppIconData icon, Color color}) _dayStatus(
  PlannedShift? e, {
  required bool past,
  bool closed = false,
  bool later = false,
}) => switch (e) {
  null when past => (label: 'Brak godzin', icon: AppIcons.minus, color: AppColors.textMuted),
  null when later => (label: 'Zgłaszanie później', icon: AppIcons.hourglass, color: AppColors.textMuted),
  null when closed => (label: 'Niedostępny', icon: AppIcons.lock, color: AppColors.textMuted),
  null => (label: 'Możesz wpisać godziny', icon: AppIcons.calendarPlus, color: AppColors.accent),
  final e when e.accepted => (
    label: e.changed ? 'Przyjęte ze zmianą' : 'Przyjęte',
    icon: AppIcons.checkCircle,
    color: AppColors.accent,
  ),
  final e when e.rejected => (label: 'Odrzucone', icon: AppIcons.prohibit, color: AppColors.error),
  final e when e.off => (label: 'Wolne', icon: AppIcons.sun, color: _off),
  final e when e.proposed => (label: 'Propozycja: odpowiedz', icon: AppIcons.send, color: _proposed),
  final e when e.unavailable => (label: 'Nie mogę', icon: AppIcons.userMinus, color: AppColors.textMuted),
  _ => (label: 'Czeka na decyzję', icon: AppIcons.hourglass, color: _pending),
};

const _weekdaysLong = ['pon.', 'wt.', 'śr.', 'czw.', 'pt.', 'sob.', 'niedz.'];

/// Termin jak „czw. 8.10, 20:00”.
String _deadlineText(DateTime d) => '${_weekdaysLong[d.weekday - 1]} ${d.day}.${_two(d.month)}, ${_hm(d)}';

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
String _lowerFirst(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// Czas trwania jako „7:45”.
String _hoursText(Duration d) => '${d.inMinutes ~/ 60}:${_two(d.inMinutes % 60)}';

/// Godziny przez północ: koniec wcześniej niż początek oznacza następny dzień (np. 18:00–02:00).
bool overnightHours(TimeOfDay starts, TimeOfDay ends) => ends.hour * 60 + ends.minute < starts.hour * 60 + starts.minute;

/// Początek i koniec w tej samej minucie: takich godzin nie da się zgłosić.
bool sameTime(TimeOfDay a, TimeOfDay b) => a.hour * 60 + a.minute == b.hour * 60 + b.minute;

/// Okres grafiku lokalu (tydzień, 2 tygodnie, miesiąc), przesunięty o [offset] okresów od dziś.
({DateTime from, DateTime to}) periodFor(String kind, int offset) {
  final today = _day(DateTime.now());
  final current = periodOf(kind, today);
  switch (kind) {
    case 'month':
      final from = DateTime(current.from.year, current.from.month + offset);
      return (from: from, to: DateTime(from.year, from.month + 1, 0));
    case 'two_weeks':
      final from = DateTime(current.from.year, current.from.month, current.from.day + offset * 14);
      return (from: from, to: DateTime(from.year, from.month, from.day + 13));
    default:
      final from = DateTime(current.from.year, current.from.month, current.from.day + offset * 7);
      return (from: from, to: DateTime(from.year, from.month, from.day + 6));
  }
}

/// Okres grafiku lokalu (tydzień, 2 tygodnie, miesiąc), w którym jest [day].
({DateTime from, DateTime to}) periodOf(String kind, DateTime day) {
  final d = _day(day);
  final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  switch (kind) {
    case 'month':
      return (from: DateTime(d.year, d.month), to: DateTime(d.year, d.month + 1, 0));
    case 'two_weeks':
      // Pary tygodni liczone od stałego poniedziałku, żeby okres był ten sam dla całego lokalu.
      // Dni liczone w UTC, bo przejście na czas letni skraca lokalną różnicę o godzinę.
      final days = DateTime.utc(monday.year, monday.month, monday.day).difference(DateTime.utc(2026, 1, 5)).inDays;
      final from = DateTime(2026, 1, 5 + (days / 14).floor() * 14);
      return (from: from, to: DateTime(from.year, from.month, from.day + 13));
    default:
      return (from: monday, to: DateTime(monday.year, monday.month, monday.day + 6));
  }
}

String _periodLabel(String kind, ({DateTime from, DateTime to}) p) {
  if (kind == 'month') return '${_months[p.from.month - 1]} ${p.from.year}';
  final sameMonth = p.from.month == p.to.month;
  return sameMonth
      ? '${p.from.day}–${p.to.day} ${_monthsShort[p.to.month - 1]}'
      : '${p.from.day} ${_monthsShort[p.from.month - 1]} – ${p.to.day} ${_monthsShort[p.to.month - 1]}';
}

/// „Tydzień 9–15 lis”, „2 tygodnie 9–22 lis”, „Listopad 2026”.
String _periodName(String kind, ({DateTime from, DateTime to}) p) => switch (kind) {
  'month' => _periodLabel(kind, p),
  'two_weeks' => '2 tygodnie ${_periodLabel(kind, p)}',
  _ => 'Tydzień ${_periodLabel(kind, p)}',
};

/// Zakładka „Kalendarz” (dawniej Grafik, 8.11.2026): miesiąc jak w Apple Calendar, w nim mój grafik i wydarzenia
/// lokali. „‹ 2026” w lewym górnym rogu wraca do całego roku, „Dziś” i „+” (nowe wydarzenie) po prawej, wszystkie
/// na Liquid Glass. Zielone pola to dni okna zgłaszania (0081): jedyny okres lokalu (tydzień, 2 tygodnie albo
/// miesiąc z „Okres zgłaszania”), na który mogę teraz wpisać dyspozycyjność; ani wcześniej, ani później. Pod
/// każdym dniem kreska w kolorze stanu zgłoszenia i kropki wydarzeń. Pod siatką wybrany dzień: godziny i stan,
/// wydarzenia, uwaga na tydzień.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = _day(DateTime.now());

  /// Cały rok (po „‹ 2026”), jak w Apple Calendar.
  bool _yearView = false;
  late int _year = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    // Okres grafiku (tydzień, 2 tygodnie, miesiąc) mógł się zmienić w panelu: pobieramy go od nowa.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
          ..invalidate(jobsProvider)
          ..invalidate(scheduleWindowProvider);
      }
    });
  }

  /// Pierwszy poniedziałek siatki (6 tygodni).
  DateTime get _gridStart {
    final first = DateTime(_month.year, _month.month);
    return DateTime(first.year, first.month, first.day - (first.weekday - 1));
  }

  /// Inny miesiąc: zaznaczony jest dziś (w bieżącym miesiącu) albo pierwszy dzień miesiąca.
  void _goTo(DateTime month, {DateTime? select}) {
    final today = _day(DateTime.now());
    setState(() {
      _yearView = false;
      _month = DateTime(month.year, month.month);
      _selected = select ?? (today.year == _month.year && today.month == _month.month ? today : _month);
    });
  }

  void _openYear() => setState(() {
    _yearView = true;
    _year = _month.year;
  });

  Future<void> _hours(List<Job> jobs, DateTime day, [PlannedShift? existing]) async {
    final saved = await showTableSheet<bool>(
      context: context,
      builder: (_) => HoursSheet(jobs: jobs, day: day, existing: existing),
    );
    if (saved != null) ref.invalidate(schedulePeriodProvider);
    if (saved == true && mounted) {
      showMessage(context, 'Zgłoszone. Przełożony przyjmie godziny, zmieni je albo odrzuci.');
    } else if (saved == false && mounted) {
      showMessage(context, 'Zapisane: nie możesz pracować w tym dniu.');
    }
  }

  Future<void> _whole(List<Job> jobs, List<DateTime> days, Map<DateTime, PlannedShift> byDay) async {
    final count = await showTableSheet<int>(
      context: context,
      builder: (_) => _PeriodSheet(jobs: jobs, days: days, existing: byDay),
    );
    if (count != null && count > 0) {
      ref.invalidate(schedulePeriodProvider);
      if (mounted) showMessage(context, 'Zapisane dni: $count. Przełożony przyjmie godziny, zmieni je albo odrzuci.');
    }
  }

  Future<void> _delete(PlannedShift shift) async {
    try {
      await ref.read(staffRepositoryProvider).deleteHours(shift.id);
      ref.invalidate(schedulePeriodProvider);
      if (mounted) showMessage(context, 'Zgłoszenie wycofane.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Odpowiedź na propozycję przełożonego.
  Future<void> _answer(PlannedShift entry, bool accept) async {
    try {
      await ref.read(staffRepositoryProvider).answerProposal(entry.id, accept: accept);
      ref.invalidate(schedulePeriodProvider);
      if (mounted) {
        showMessage(
          context,
          accept ? 'Przyjęte: ${entry.starts}–${entry.ends}. Dzień jest w Twoim kalendarzu.' : 'Przełożony zobaczy, że nie możesz.',
          tone: accept ? ToastTone.success : ToastTone.info,
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Uwaga na tydzień dla przełożonego (np. „w środę egzamin”).
  Future<void> _weekNote(List<Job> jobs, DateTime week, String? current) async {
    final note = await showTextSheet(
      context: context,
      title: 'Uwaga na tydzień ${week.day}.${_two(week.month)}',
      message: 'Przełożony zobaczy ją w grafiku.',
      label: 'Uwaga',
      hint: 'Na przykład: w środę mam egzamin',
      initial: current ?? '',
    );
    if (note == null || jobs.isEmpty) return;
    try {
      await ref.read(staffRepositoryProvider).setWeekNote(jobs.first.memberId, week, note);
      ref.invalidate(weekNotesProvider);
      if (mounted) showMessage(context, note.isEmpty ? 'Uwaga usunięta.' : 'Uwaga zapisana. Przełożony zobaczy ją w grafiku.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _open(List<Job> jobs, DateTime day, PlannedShift? entry, ScheduleWindow? window) async {
    final today = _day(DateTime.now());
    final past = day.isBefore(today);
    final kind = jobs.isEmpty ? 'week' : jobs.first.schedulePeriod;
    final inWindow = window != null && !day.isBefore(window.from) && !day.isAfter(window.to);
    if (entry == null) {
      if (past || jobs.isEmpty || window == null) return;
      if (day.isBefore(window.from)) {
        showMessage(context, 'Zgłaszanie na ten dzień jest już zamknięte. Zapytaj przełożonego.');
        return;
      }
      if (day.isAfter(window.to)) {
        showMessage(
          context,
          'Na ten dzień zgłosisz godziny później. Teraz: ${_lowerFirst(_periodName(kind, (from: window.from, to: window.to)))}.',
        );
        return;
      }
      await _hours(jobs, day);
      return;
    }
    final mine = entry.pending || entry.unavailable;
    // Zmienić można tylko w oknie zgłaszania; wycofać także później zgłoszony dzień, ale nie zamknięty.
    final editable = mine && !past && inWindow;
    final withdrawable = mine && !past && window != null && !day.isBefore(window.from);
    final answerable = entry.proposed && !past;
    await showTableSheet<void>(
      context: context,
      builder: (context) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final system = MediaQuery.viewPaddingOf(context).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + (keyboard > system ? keyboard : system)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(Fmt.capitalize(Fmt.dayLong(day)), style: Theme.of(context).textTheme.titleLarge),
              ),
              _EntryCard(
                entry: entry,
                onEdit: editable
                    ? () {
                        Navigator.pop(context);
                        _hours(jobs, day, entry.unavailable ? null : entry);
                      }
                    : null,
                onDelete: withdrawable
                    ? () {
                        Navigator.pop(context);
                        _delete(entry);
                      }
                    : null,
                onAccept: answerable
                    ? () {
                        Navigator.pop(context);
                        _answer(entry, true);
                      }
                    : null,
                onDecline: answerable
                    ? () {
                        Navigator.pop(context);
                        _answer(entry, false);
                      }
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Nowe wydarzenie w Kalendarzu lokalu (uprawnienie „Kalendarz”).
  Future<void> _addEvent(List<Job> jobs) async {
    final saved = await showTableSheet<bool>(
      context: context,
      builder: (_) => AddEventSheet(jobs: jobs, day: _selected),
    );
    if (saved == true) ref.invalidate(staffCalendarProvider);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final jobs = ref.watch(jobsProvider).value ?? const <Job>[];
    final kind = jobs.isEmpty ? 'week' : jobs.first.schedulePeriod;
    final now = DateTime.now();
    final today = _day(now);
    final start = _gridStart;
    final grid = [for (var i = 0; i < 42; i++) DateTime(start.year, start.month, start.day + i)];
    final last = grid.last;

    // Okno zgłaszania: jedyny okres, na który mogę teraz wpisać dyspozycyjność.
    final window = jobs.isEmpty ? null : ref.watch(scheduleWindowProvider(jobs.first.memberId)).value;
    final period = window == null ? null : (from: window.from, to: window.to);
    bool inWindow(DateTime d) => period != null && !d.isBefore(period.from) && !d.isAfter(period.to);

    // Mój grafik w siatce i w oknie zgłaszania (okno może leżeć w innym miesiącu niż oglądany).
    final async = ref.watch(schedulePeriodProvider((from: start, to: last)));
    final windowAsync = period == null ? null : ref.watch(schedulePeriodProvider(period));
    final loaded = async.hasValue && (windowAsync?.hasValue ?? true);
    final byDay = {
      for (final e in windowAsync?.value ?? const <PlannedShift>[]) _day(e.day): e,
      for (final e in async.value ?? const <PlannedShift>[]) _day(e.day): e,
    };

    // Zielone pole: dzień okna zgłaszania bez zgłoszenia, który jeszcze nie minął.
    bool canEnter(DateTime d) => loaded && inWindow(d) && byDay[d] == null && !d.isBefore(today);

    // Wydarzenia lokali pracownika w siatce (lokale po przecinku, żeby klucz rodziny był porównywalny).
    final ids = {for (final j in jobs) j.restaurantId}.toList()..sort();
    final names = {for (final j in jobs) j.restaurantId: j.restaurantName};
    final eventsQuery = (restaurants: ids.join(','), from: start, to: DateTime(last.year, last.month, last.day + 1));
    final events = ref.watch(staffCalendarProvider(eventsQuery)).value ?? const <StaffEvent>[];
    List<StaffEvent> eventsOn(DateTime d) => [
      for (final e in events)
        if (e.overlaps(d, DateTime(d.year, d.month, d.day + 1))) e,
    ];
    final canAdd = [
      for (final j in jobs)
        if (j.permissions.contains('calendar')) j,
    ];

    // Dni okna do zgłoszenia naraz (bez decyzji przełożonego).
    final open = period == null || !loaded
        ? const <DateTime>[]
        : [
            for (var d = period.from; !d.isAfter(period.to); d = DateTime(d.year, d.month, d.day + 1))
              if (!d.isBefore(today) && (byDay[d] == null || byDay[d]!.pending || byDay[d]!.unavailable)) d,
          ];
    final entry = byDay[_selected];
    final monday = DateTime(_selected.year, _selected.month, _selected.day - (_selected.weekday - 1));
    final notes = ref.watch(weekNotesProvider((from: start, to: last))).value ?? const <DateTime, String>{};

    // Legenda z liczbami w tym miesiącu.
    final monthDays = grid.where((d) => d.month == _month.month).toList();
    int count(bool Function(PlannedShift e) test) => monthDays.where((d) => byDay[d] != null && test(byDay[d]!)).length;
    final toEnter = monthDays.where(canEnter).length;
    final accepted = count((e) => e.accepted);
    final waiting = count((e) => e.pending);
    final rejected = count((e) => e.rejected);
    final free = count((e) => e.off);
    final proposals = count((e) => e.proposed);
    // Krótki napis: przy czcionce telefonu +15% dłuższy się łamał.
    final submitLabel = switch (kind) {
      'month' => 'Zgłoś godziny na miesiąc',
      'two_weeks' => 'Zgłoś godziny na 2 tygodnie',
      _ => 'Zgłoś godziny na tydzień',
    };
    final windowName = period == null ? null : _lowerFirst(_periodName(kind, period));

    Widget dayCell(DateTime day) => _DayCell(
      day: day,
      inMonth: day.month == _month.month,
      today: today,
      selected: day == _selected,
      entry: byDay[day],
      canEnter: canEnter(day),
      events: eventsOn(day),
      onTap: () {
        // Drugie stuknięcie w zaznaczony dzień od razu otwiera godziny.
        if (day == _selected) {
          _open(jobs, day, byDay[day], window);
          return;
        }
        setState(() {
          _selected = day;
          if (day.month != _month.month) _month = DateTime(day.year, day.month);
        });
      },
    );

    final month = ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    _months[_month.month - 1],
                    style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Poprzedni miesiąc',
                onPressed: () => _goTo(DateTime(_month.year, _month.month - 1)),
                icon: const Glyph(AppIcons.caretLeft),
              ),
              IconButton(
                tooltip: 'Następny miesiąc',
                onPressed: () => _goTo(DateTime(_month.year, _month.month + 1)),
                icon: const Glyph(AppIcons.caretRight),
              ),
            ],
          ),
        ),
        ExcludeSemantics(
          child: Row(
            children: [
              for (final d in _weekdaysMini)
                Expanded(
                  child: Center(
                    child: Text(d, style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() > 250) _goTo(DateTime(_month.year, _month.month + (v < 0 ? 1 : -1)));
          },
          child: Column(
            children: [
              for (var w = 0; w < 6; w++)
                Row(
                  children: [
                    for (final day in grid.sublist(w * 7, w * 7 + 7)) Expanded(child: dayCell(day)),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              if (toEnter > 0) _Legend(field: true, color: AppColors.accent, label: 'Do wpisania: $toEnter'),
              _Legend(color: AppColors.accent, label: 'Przyjęte: $accepted'),
              _Legend(color: _pending, label: 'Czeka: $waiting'),
              if (rejected > 0) _Legend(color: AppColors.error, label: 'Odrzucone: $rejected'),
              if (free > 0) _Legend(color: _off, label: 'Wolne: $free'),
              if (proposals > 0) _Legend(color: _proposed, label: 'Propozycje: $proposals'),
            ],
          ),
        ),
        // Okno zgłaszania: na jaki okres i do kiedy. Stuknięcie pokazuje te dni w kalendarzu.
        if (period != null && windowName != null) ...[
          const SizedBox(height: 10),
          Semantics(
            button: true,
            hint: 'Pokaż te dni w kalendarzu',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _goTo(period.from, select: period.from),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Glyph(window!.deadline == null ? AppIcons.calendarPlus : AppIcons.alarm, size: 16, color: AppColors.accent),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        window.deadline == null
                            ? 'Dyspozycyjność zgłaszasz teraz na $windowName. Inne dni są zamknięte.'
                            : 'Zgłoś dyspozycyjność na $windowName do ${_deadlineText(window.deadline!)}. '
                                  'Inne dni są zamknięte.',
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (open.isNotEmpty && jobs.isNotEmpty) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => _whole(jobs, open, byDay),
            icon: const Glyph(AppIcons.calendarPlus, size: 20),
            label: Text(submitLabel, semanticsLabel: '$submitLabel, $windowName'),
          ),
        ],
        const SizedBox(height: 16),
        Divider(height: 1, color: AppColors.ring),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
          child: Text(
            '${_weekdaysFull[_selected.weekday - 1]}, ${_selected.day} ${_monthsGenitive[_selected.month - 1]}'
            '${_selected == today ? ' · dziś' : ''}',
            style: text.titleMedium,
          ),
        ),
        if (async.hasError && !async.hasValue)
          ErrorView(error: async.error!, onRetry: () => ref.invalidate(schedulePeriodProvider))
        else if (!loaded)
          const ExcludeSemantics(child: SkeletonBox(width: double.infinity, height: 68, radius: 16))
        else
          _DayRow(
            day: _selected,
            today: today,
            entry: entry,
            closed: period != null && _selected.isBefore(period.from),
            later: period != null && _selected.isAfter(period.to),
            canEnter: canEnter(_selected),
            onTap: () => _open(jobs, _selected, entry, window),
          ),
        // Wydarzenia lokali w tym dniu (specjalne i dla pracowników).
        for (final e in eventsOn(_selected))
          CalendarEventTile(event: e, day: _selected, restaurant: ids.length > 1 ? names[e.restaurantId] : null),
        // Moja uwaga na ten tydzień dla przełożonego.
        _WeekNoteRow(
          week: monday,
          note: notes[monday],
          onTap: jobs.isEmpty ? null : () => _weekNote(jobs, monday, notes[monday]),
        ),
      ],
    );

    return Scaffold(
      // Jak w Apple Calendar: „‹ 2026” wraca do całego roku, „Dziś” i „+” po prawej, wszystko na Liquid Glass.
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: _yearView ? 0 : 128,
        leading: _yearView
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GlassTextButton(
                    label: '‹ ${_month.year}',
                    semanticLabel: 'Cały rok ${_month.year}',
                    color: _red,
                    onTap: _openYear,
                    fallback: TextButton.icon(
                      onPressed: _openYear,
                      icon: const Glyph(AppIcons.caretLeft, size: 18, color: _red),
                      label: Text('${_month.year}', style: const TextStyle(color: _red, fontSize: 17)),
                    ),
                  ),
                ),
              ),
        actions: [
          GlassTextButton(
            label: 'Dziś',
            onTap: () => _goTo(today),
            fallback: TextButton(onPressed: () => _goTo(today), child: const Text('Dziś')),
          ),
          if (canAdd.isNotEmpty) ...[
            const SizedBox(width: 4),
            GlassIconButton(
              symbol: 'plus',
              icon: AppIcons.plus,
              native: true,
              label: 'Nowe wydarzenie',
              onTap: () => _addEvent(canAdd),
              fallback: IconButton(
                tooltip: 'Nowe wydarzenie',
                onPressed: () => _addEvent(canAdd),
                icon: const Glyph(AppIcons.plus),
              ),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref
          ..invalidate(jobsProvider)
          ..invalidate(scheduleWindowProvider)
          ..invalidate(schedulePeriodProvider)
          ..invalidate(weekNotesProvider)
          ..invalidate(staffCalendarProvider),
        child: ContentWidth(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            child: _yearView
                ? _YearView(
                    key: ValueKey('rok-$_year'),
                    year: _year,
                    today: today,
                    green: canEnter,
                    onMonth: (m) => _goTo(m),
                    onYear: (y) => setState(() => _year = y),
                  )
                : KeyedSubtree(key: const ValueKey('miesiac'), child: month),
          ),
        ),
      ),
    );
  }
}

/// Cały rok jak w Apple Calendar: rok u góry (bieżący na czerwono), 12 małych miesięcy z dziś w czerwonym kółku
/// i zielonymi dniami okna zgłaszania. Stuknięcie w miesiąc otwiera go, przesunięcie palcem zmienia rok.
class _YearView extends StatelessWidget {
  const _YearView({
    super.key,
    required this.year,
    required this.today,
    required this.green,
    required this.onMonth,
    required this.onYear,
  });

  final int year;
  final DateTime today;
  final bool Function(DateTime day) green;
  final ValueChanged<DateTime> onMonth;
  final ValueChanged<int> onYear;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() > 250) onYear(year + (v < 0 ? 1 : -1));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    '$year',
                    style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: _tabular,
                      color: year == today.year ? _red : AppColors.text,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Poprzedni rok',
                onPressed: () => onYear(year - 1),
                icon: const Glyph(AppIcons.caretLeft),
              ),
              IconButton(
                tooltip: 'Następny rok',
                onPressed: () => onYear(year + 1),
                icon: const Glyph(AppIcons.caretRight),
              ),
            ],
          ),
          Divider(height: 20, color: AppColors.ring),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 600 ? 4 : 3;
              const gap = 14.0;
              final width = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: 20,
                children: [
                  for (var m = 1; m <= 12; m++)
                    SizedBox(
                      width: width,
                      child: _MiniMonth(
                        month: DateTime(year, m),
                        today: today,
                        green: green,
                        onTap: () => onMonth(DateTime(year, m)),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Mały miesiąc w widoku roku: nazwa i dni (dziś w czerwonym kółku, dni okna zgłaszania na zielono).
class _MiniMonth extends StatelessWidget {
  const _MiniMonth({required this.month, required this.today, required this.green, required this.onTap});

  final DateTime month;
  final DateTime today;
  final bool Function(DateTime day) green;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final current = month.year == today.year && month.month == today.month;
    final start = DateTime(month.year, month.month, 1 - (month.weekday - 1));
    final days = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((month.weekday - 1 + days) / 7).ceil();
    return Semantics(
      button: true,
      label: '${_months[month.month - 1]} ${month.year}${current ? ', bieżący miesiąc' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _months[month.month - 1],
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: current ? _red : AppColors.text),
              ),
              const SizedBox(height: 4),
              for (var r = 0; r < rows; r++)
                Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final d = DateTime(start.year, start.month, start.day + r * 7 + i);
                            if (d.month != month.month) return const SizedBox(height: 17);
                            final isToday = d == today;
                            final g = !isToday && green(d);
                            return SizedBox(
                              height: 17,
                              child: Center(
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  alignment: Alignment.center,
                                  decoration: isToday
                                      ? const BoxDecoration(color: _red, shape: BoxShape.circle)
                                      : g
                                      ? BoxDecoration(color: AppColors.accentTint, borderRadius: BorderRadius.circular(4))
                                      : null,
                                  child: Text(
                                    '${d.day}',
                                    textScaler: TextScaler.noScaling,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontFeatures: _tabular,
                                      fontWeight: isToday || g ? FontWeight.w700 : FontWeight.w500,
                                      color: isToday ? Colors.white : (g ? AppColors.accent : AppColors.text),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dzień w siatce miesiąca: numer (dziś na czerwono, wybrany w kółku), pod nim kreska grafiku w kolorze stanu
/// zgłoszenia i kropki wydarzeń. Dzień okna zgłaszania, w który mogę jeszcze wpisać godziny, jest zielonym polem.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.selected,
    required this.entry,
    required this.canEnter,
    required this.events,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final DateTime today;
  final bool selected;
  final PlannedShift? entry;
  final bool canEnter;
  final List<StaffEvent> events;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isToday = day == today;
    final e = entry;
    final mark = e == null ? null : _dayStatus(e, past: day.isBefore(today));
    final hours = e != null && !e.off && !e.unavailable ? '${e.starts}–${e.ends}' : null;
    return Semantics(
      button: true,
      selected: selected,
      label: [
        '${day.day} ${_monthsGenitive[day.month - 1]}',
        if (isToday) 'dziś',
        ?hours,
        if (mark != null) mark.label,
        if (canEnter) 'możesz wpisać godziny',
        if (events.isNotEmpty) 'wydarzeń: ${events.length}',
      ].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: canEnter ? AppColors.accentTint : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: canEnter ? BorderSide(color: AppColors.accent.withValues(alpha: 0.45)) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 54,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? (isToday ? _red : AppColors.text) : null,
                    ),
                    child: Text(
                      '${day.day}',
                      style: text.titleSmall?.copyWith(
                        fontFeatures: _tabular,
                        fontWeight: selected || isToday || canEnter ? FontWeight.w600 : FontWeight.w400,
                        color: selected
                            ? (isToday ? Colors.white : AppColors.background)
                            : isToday
                            ? _red
                            : canEnter
                            ? AppColors.accent
                            : (inMonth ? AppColors.text : AppColors.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 5,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (mark != null)
                          Container(
                            width: 14,
                            height: 4,
                            decoration: BoxDecoration(color: mark.color, borderRadius: BorderRadius.circular(2)),
                          ),
                        if (mark != null && events.isNotEmpty) const SizedBox(width: 3),
                        for (final ev in events.take(mark == null ? 3 : 2))
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(color: eventColor(ev), shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pozycja legendy pod siatką: zielone pole (dni do wpisania) albo kreska w kolorze stanu, z liczbą.
class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.field = false});

  final Color color;
  final String label;
  final bool field;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (field)
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
          )
        else
          Container(
            width: 14,
            height: 4,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
        ),
      ],
    );
  }
}

/// Uwaga na tydzień: dotknięcie dodaje albo zmienia. Cały wiersz ma co najmniej 48 dp.
class _WeekNoteRow extends StatelessWidget {
  const _WeekNoteRow({required this.week, required this.note, required this.onTap});

  final DateTime week;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final end = week.add(const Duration(days: 6));
    final range = '${week.day}.${_two(week.month)}–${end.day}.${_two(end.month)}';
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Semantics(
        button: onTap != null,
        label: 'Tydzień $range. ${note == null ? 'Dodaj uwagę dla przełożonego' : 'Twoja uwaga: $note. Zmień'}',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              // Uwaga pod nazwą tygodnia, żeby przy dużej czcionce nie ucinała się obok daty.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Tydzień $range', style: text.titleSmall?.copyWith(fontFeatures: _tabular)),
                      ),
                      Glyph(note == null ? AppIcons.plus : AppIcons.pencil, size: 15, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Text(note == null ? 'Dodaj uwagę' : 'Zmień', style: text.bodyMedium?.copyWith(color: AppColors.accent)),
                    ],
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Glyph(AppIcons.chatText, size: 15, color: _pending),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            note!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(color: _pending),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wybrany dzień w grafiku: godziny i stan zgłoszenia słowem z ikoną. Dzień okna zgłaszania, w który mogę jeszcze
/// wpisać godziny pracy, jest zieloną kartą. Minione dni są przygaszone kolorem tekstu, nie przezroczystością.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.today,
    required this.entry,
    required this.onTap,
    this.closed = false,
    this.later = false,
    this.canEnter = false,
  });

  final DateTime day;
  final DateTime today;
  final PlannedShift? entry;
  final VoidCallback onTap;

  /// Dzień przed oknem zgłaszania: bez zgłoszenia to „Niedostępny”.
  final bool closed;

  /// Dzień po oknie zgłaszania: zgłasza się go później.
  final bool later;

  /// Dzień okna zgłaszania bez zgłoszenia (zielona karta).
  final bool canEnter;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = entry;
    final past = day.isBefore(today);
    final status = _dayStatus(e, past: past, closed: closed, later: later);
    final hours = e != null && !e.off && !e.unavailable
        ? '${e.starts}–${e.ends}${e.positionName == null ? '' : ' · ${e.positionName}'}'
        : null;
    final tappable = !past || e != null;
    final title = hours ?? (canEnter ? 'Wpisz godziny pracy' : status.label);
    final hint = e != null
        ? null
        : canEnter
        ? 'Przełożony przyjmie je, zmieni albo odrzuci.'
        : past
        ? null
        : later
        ? 'Ten okres jeszcze nie jest otwarty do zgłaszania.'
        : closed
        ? 'Zgłaszanie na ten okres jest zamknięte.'
        : null;
    final border = canEnter ? AppColors.accent.withValues(alpha: 0.45) : AppColors.ring;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: tappable,
        label: [
          'Grafik',
          ?hours,
          status.label,
          ?hint,
          if (e?.answer != null) 'przełożony: ${e!.answer}',
        ].join(', '),
        excludeSemantics: true,
        child: Material(
          color: canEnter ? AppColors.accentTint : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: tappable ? onTap : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 68),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: canEnter ? AppColors.accent.withValues(alpha: 0.14) : AppColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Glyph(
                      hours != null ? AppIcons.clock : status.icon,
                      size: 22,
                      color: hours != null ? (past ? AppColors.textMuted : AppColors.text) : status.color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: text.titleMedium?.copyWith(
                            fontFeatures: _tabular,
                            color: canEnter
                                ? AppColors.accent
                                : past || (e?.rejected ?? false)
                                ? AppColors.textMuted
                                : AppColors.text,
                            decoration: hours != null && e!.rejected ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (hours != null) ...[
                          const SizedBox(height: 4),
                          StatusChip(label: status.label, icon: status.icon, color: status.color),
                        ] else if (hint != null) ...[
                          const SizedBox(height: 2),
                          Text(hint, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                        ],
                        if (e?.answer != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Przełożony: ${e!.answer}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (tappable)
                    Glyph(AppIcons.caretRight, size: 16, color: canEnter ? AppColors.accent : AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Zgłoszenie godzin na cały okres: przy każdym dniu przełącznik „mogę pracować” i godziny.
class _PeriodSheet extends ConsumerStatefulWidget {
  const _PeriodSheet({required this.jobs, required this.days, required this.existing});

  final List<Job> jobs;

  /// Dni od dziś, o których przełożony jeszcze nie zdecydował.
  final List<DateTime> days;
  final Map<DateTime, PlannedShift> existing;

  @override
  ConsumerState<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends ConsumerState<_PeriodSheet> {
  late final Map<DateTime, bool> _on = {for (final d in widget.days) d: _hoursOf(d) != null};
  late final Map<DateTime, TimeOfDay> _starts = {
    for (final d in widget.days) d: _parse(_hoursOf(d)?.starts ?? '10:00'),
  };
  late final Map<DateTime, TimeOfDay> _ends = {
    for (final d in widget.days) d: _parse(_hoursOf(d)?.ends ?? '18:00'),
  };
  late String _memberId = widget.jobs.first.memberId;
  bool _busy = false;

  static TimeOfDay _parse(String hm) {
    final p = hm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static String _fmt(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  /// Zgłoszenie z godzinami w tym dniu. „Nie mogę” nie ma godzin (puste `starts`), więc liczy się jak dzień
  /// bez zgłoszenia: wyłączony, z domyślnymi godzinami. Wcześniej puste godziny wywracały okno (szary prostokąt
  /// na iPhonie, 1.11.2026).
  PlannedShift? _hoursOf(DateTime day) => switch (widget.existing[day]) {
    final e? when !e.unavailable => e,
    _ => null,
  };

  Future<void> _pick(DateTime day, bool start) async {
    final picked = await showTimeWheel(
      context,
      initial: start ? _starts[day]! : _ends[day]!,
      minuteStep: 15,
      allowEndOfDay: !start,
      title: start ? 'Od' : 'Do',
    );
    if (picked == null) return;
    setState(() {
      (start ? _starts : _ends)[day] = picked;
      _on[day] = true;
    });
  }

  Future<void> _send() async {
    final chosen = widget.days.where((d) => _on[d] ?? false).toList();
    for (final d in chosen) {
      final s = _starts[d]!;
      final e = _ends[d]!;
      if (sameTime(s, e)) {
        showMessage(context, '${Fmt.capitalize(Fmt.dayShort(d))}: początek i koniec nie mogą być takie same.');
        return;
      }
    }
    // Wyłączony dzień ze zgłoszeniem wycofuje je („Nie mogę” zostaje). Niezmienionych dni nie wysyłamy drugi raz.
    final withdrawn = [
      for (final d in widget.days)
        if (!(_on[d] ?? false)) ?_hoursOf(d),
    ];
    final changed = [
      for (final d in chosen)
        if (_hoursOf(d) case final e when e == null || e.starts != _fmt(_starts[d]!) || e.ends != _fmt(_ends[d]!)) d,
    ];
    if (chosen.isEmpty && withdrawn.isEmpty) {
      showMessage(context, 'Zaznacz dni, w które możesz pracować.');
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(staffRepositoryProvider);
    var done = 0;
    try {
      for (final e in withdrawn) {
        await repo.deleteHours(e.id);
        done++;
      }
      for (final d in changed) {
        await repo.submitHours(
          memberId: widget.existing[d]?.memberId ?? _memberId,
          day: d,
          starts: _fmt(_starts[d]!),
          ends: _fmt(_ends[d]!),
          note: widget.existing[d]?.note,
        );
        done++;
      }
      if (mounted) Navigator.pop(context, done);
    } catch (e) {
      if (mounted) showMessage(context, done == 0 ? errorText(e) : 'Zapisano $done dni. ${errorText(e)}', tone: ToastTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final system = MediaQuery.viewPaddingOf(context).bottom;
    final count = _on.values.where((v) => v).length;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + (keyboard > system ? keyboard : system)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Kiedy możesz pracować?', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Zaznacz dni i godziny. Przełożony przyjmie je, zmieni albo odrzuci.',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          if (widget.jobs.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _memberId,
              decoration: const InputDecoration(labelText: 'Lokal'),
              items: [
                for (final j in widget.jobs) DropdownMenuItem(value: j.memberId, child: Text(j.restaurantName)),
              ],
              onChanged: (v) => setState(() => _memberId = v ?? _memberId),
            ),
          ],
          const SizedBox(height: 10),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final d in widget.days)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.ring))),
                    child: Row(
                      children: [
                        Switch(value: _on[d] ?? false, onChanged: (v) => setState(() => _on[d] = v)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_weekdays[d.weekday - 1]} ${d.day}.${_two(d.month)}',
                            style: text.titleSmall?.copyWith(
                              fontFeatures: _tabular,
                              color: (_on[d] ?? false) ? AppColors.text : AppColors.textMuted,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _pick(d, true),
                          child: Text(_fmt(_starts[d]!), style: const TextStyle(fontFeatures: _tabular, fontSize: 16)),
                        ),
                        Text('–', style: text.titleMedium),
                        TextButton(
                          onPressed: () => _pick(d, false),
                          child: Text(
                            // Koniec po północy: „02:00+1”, czyli następnego dnia.
                            '${_fmt(_ends[d]!)}${overnightHours(_starts[d]!, _ends[d]!) ? '+1' : ''}',
                            semanticsLabel: overnightHours(_starts[d]!, _ends[d]!)
                                ? 'do ${_fmt(_ends[d]!)} następnego dnia'
                                : null,
                            style: const TextStyle(fontFeatures: _tabular, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _send,
            child: Text(count == 0 ? 'Zapisz' : 'Zgłoś ($count ${count == 1 ? 'dzień' : 'dni'})'),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
    this.onAccept,
    this.onDecline,
  });

  final PlannedShift entry;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Propozycja przełożonego: przyjmuję albo nie mogę.
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = entry;
    final (Color color, AppIconData icon, String status) = e.accepted
        ? (AppColors.accent, AppIcons.checkCircle, e.changed ? 'Przyjęte ze zmianą' : 'Przyjęte')
        : e.rejected
        ? (AppColors.error, AppIcons.prohibit, 'Odrzucone')
        : e.off
        ? (_off, AppIcons.sun, 'Wolne')
        : e.proposed
        ? (_proposed, AppIcons.send, 'Propozycja przełożonego')
        : e.unavailable
        ? (AppColors.textMuted, AppIcons.userMinus, 'Nie mogę pracować')
        : (_pending, AppIcons.hourglass, 'Czeka na decyzję przełożonego');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Glyph(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(status, style: text.titleSmall?.copyWith(color: color))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              e.off ? 'Masz wolne' : (e.unavailable ? 'Niedostępny' : '${e.starts}–${e.ends}'),
              style: text.headlineSmall?.copyWith(
                fontFeatures: _tabular,
                decoration: e.rejected ? TextDecoration.lineThrough : null,
              ),
            ),
            Text(
              [e.restaurantName, ?e.positionName].join(' · '),
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            if (e.changed || (e.off && e.requestedStarts != null))
              Text(
                'Zgłaszałeś ${e.requestedStarts}–${e.requestedEnds}',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
              ),
            if (e.note != null) ...[
              const SizedBox(height: 6),
              Text('Twoje uwagi: ${e.note}', style: text.bodySmall),
            ],
            if (e.answer != null) ...[
              const SizedBox(height: 6),
              Text('Przełożony: ${e.answer}', style: text.bodyMedium),
            ],
            if (onAccept != null || onDecline != null) ...[
              const SizedBox(height: 12),
              ButtonPair(
                first: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: AppColors.error),
                  onPressed: onDecline,
                  child: const Text('Nie mogę'),
                ),
                second: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: onAccept,
                  child: const Text('Przyjmuję'),
                ),
              ),
            ] else if (onEdit != null || onDelete != null) ...[
              const SizedBox(height: 12),
              ButtonPair(
                first: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: onEdit,
                  child: Text(e.unavailable ? 'Mogę jednak' : 'Zmień'),
                ),
                second: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: AppColors.error),
                  onPressed: onDelete,
                  child: const Text('Wycofaj'),
                ),
              ),
            ] else if (e.pending) ...[
              const SizedBox(height: 6),
              Text('Tego dnia nie można już zmienić.', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Zgłoszenie godzin w wybranym dniu: od–do i uwagi.
class HoursSheet extends ConsumerStatefulWidget {
  const HoursSheet({super.key, required this.jobs, required this.day, this.existing});

  final List<Job> jobs;
  final DateTime day;
  final PlannedShift? existing;

  @override
  ConsumerState<HoursSheet> createState() => _HoursSheetState();
}

class _HoursSheetState extends ConsumerState<HoursSheet> {
  late TimeOfDay _starts = _parse(widget.existing?.starts ?? '10:00');
  late TimeOfDay _ends = _parse(widget.existing?.ends ?? '18:00');
  late String _memberId = widget.existing?.memberId ?? widget.jobs.first.memberId;
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  bool _busy = false;

  static TimeOfDay _parse(String hm) {
    final p = hm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static String _fmt(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final picked = await showTimeWheel(
      context,
      initial: start ? _starts : _ends,
      minuteStep: 15,
      allowEndOfDay: !start,
      title: start ? 'Od' : 'Do',
    );
    if (picked != null) setState(() => start ? _starts = picked : _ends = picked);
  }

  Future<void> _send() async {
    if (sameTime(_starts, _ends)) {
      showMessage(context, 'Początek i koniec nie mogą być takie same.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(staffRepositoryProvider).submitHours(
        memberId: _memberId,
        day: widget.day,
        starts: _fmt(_starts),
        ends: _fmt(_ends),
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Nie mogę pracować w tym dniu.
  Future<void> _unavailable() async {
    setState(() => _busy = true);
    try {
      await ref.read(staffRepositoryProvider).markUnavailable(memberId: _memberId, day: widget.day, note: _note.text);
      if (mounted) Navigator.pop(context, false);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Klawiatura albo przyciski systemu Androida: okno kończy się nad tym, co jest wyżej.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final system = MediaQuery.viewPaddingOf(context).bottom;
    Widget time(TimeOfDay t, bool start) => Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
        onPressed: () => _pick(start),
        child: Text(_fmt(t), style: const TextStyle(fontSize: 18, fontFeatures: _tabular)),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + (keyboard > system ? keyboard : system)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Zgłoś godziny' : 'Zmień zgłoszenie', style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${Fmt.capitalize(Fmt.dayLong(widget.day))}. Przełożony przyjmie godziny, zmieni je albo odrzuci. '
              'Po jego decyzji nie zmienisz już tego dnia.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            if (widget.jobs.length > 1 && widget.existing == null) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _memberId,
                decoration: const InputDecoration(labelText: 'Lokal'),
                items: [
                  for (final j in widget.jobs) DropdownMenuItem(value: j.memberId, child: Text(j.restaurantName)),
                ],
                onChanged: (v) => setState(() => _memberId = v ?? _memberId),
              ),
            ],
            const SizedBox(height: 16),
            Text('Mogę pracować', style: text.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                time(_starts, true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('–', style: text.titleMedium),
                ),
                time(_ends, false),
              ],
            ),
            if (overnightHours(_starts, _ends)) ...[
              const SizedBox(height: 6),
              Text(
                'Do ${_fmt(_ends)} następnego dnia (${_hoursText(Duration(minutes: (_ends.hour - _starts.hour) * 60 + _ends.minute - _starts.minute + 24 * 60))} h).',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Uwagi (opcjonalnie)', hintText: 'Na przykład: rano mam zajęcia'),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy ? null : _send, child: const Text('Zgłoś')),
            const SizedBox(height: 4),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _busy ? null : _unavailable,
              child: const Text('Nie mogę w tym dniu'),
            ),
          ],
        ),
      ),
    );
  }
}
