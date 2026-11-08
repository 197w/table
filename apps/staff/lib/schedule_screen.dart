import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_core/table_core.dart';

import 'calendar_screen.dart';
import 'data.dart';
import 'ui.dart';

const _tabular = [FontFeature.tabularFigures()];
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

String _two(int n) => n.toString().padLeft(2, '0');
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

/// „Poniedziałek, 9 listopada · dziś”.
String _dayTitle(DateTime day, DateTime today) =>
    '${_weekdaysFull[day.weekday - 1]}, ${day.day} ${_monthsGenitive[day.month - 1]}${day == today ? ' · dziś' : ''}';

/// Widok miesiąca jak w Apple Calendar (9.11.2026, nagranie od użytkownika): menu w prawym górnym rogu.
enum _View {
  compact('Kompaktowy', 'calendar', AppIcons.calendarDots),
  stacked('Skumulowany', 'rectangle.split.1x2', AppIcons.rows),
  details('Szczegóły', 'rectangle.grid.1x2', AppIcons.cards),
  list('Lista', 'list.bullet.below.rectangle', AppIcons.list);

  const _View(this.label, this.symbol, this.icon);

  final String label;

  /// Symbol SF w natywnym menu i na przycisku.
  final String symbol;
  final AppIconData icon;
}

/// Wybrany widok zapisany w telefonie.
const _viewKey = 'staff_calendar_view';

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

  /// Widok miesiąca (menu w prawym górnym rogu), zapamiętany w telefonie.
  _View _view = _View.details;

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
    _loadView();
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

  Future<void> _loadView() async {
    try {
      final saved = await SharedPreferencesAsync().getString(_viewKey);
      final view = _View.values.where((v) => v.name == saved).firstOrNull;
      if (view != null && mounted) setState(() => _view = view);
    } catch (_) {
      // Brak zapisu: widok domyślny.
    }
  }

  Future<void> _setView(_View view) async {
    if (view == _view) return;
    setState(() => _view = view);
    try {
      await SharedPreferencesAsync().setString(_viewKey, view.name);
    } catch (_) {
      // Widok działa do zamknięcia aplikacji, nawet jeśli zapis się nie udał.
    }
  }

  /// Wybór widoku poza iOS 26: okno od dołu z tymi samymi opcjami.
  Future<void> _pickView() async {
    final view = await showOptionSheet<_View>(
      context: context,
      title: 'Widok kalendarza',
      options: [
        for (final v in _View.values)
          SheetOption(
            value: v,
            icon: v.icon,
            title: v.label,
            subtitle: v == _view ? 'Wybrany' : null,
          ),
      ],
    );
    if (view != null) await _setView(view);
  }

  /// Dzień z siatki (widoki poza „Lista”): moje godziny (stuknięcie otwiera zgłoszenie) i wydarzenia lokali.
  Future<void> _openDay({
    required List<Job> jobs,
    required DateTime day,
    required PlannedShift? entry,
    required ScheduleWindow? window,
    required List<StaffEvent> events,
    required bool canEnter,
    required Map<String, String> names,
  }) async {
    final today = _day(DateTime.now());
    await showTableSheet<void>(
      context: context,
      builder: (context) {
        final system = MediaQuery.viewPaddingOf(context).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + system),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(_dayTitle(day, today), style: Theme.of(context).textTheme.titleLarge),
                ),
                if (jobs.isNotEmpty)
                  _DayRow(
                    day: day,
                    today: today,
                    entry: entry,
                    closed: window != null && day.isBefore(window.from),
                    later: window != null && day.isAfter(window.to),
                    canEnter: canEnter,
                    onTap: () {
                      Navigator.pop(context);
                      _open(jobs, day, entry, window);
                    },
                  ),
                for (final e in events)
                  CalendarEventTile(event: e, day: day, restaurant: names.length > 1 ? names[e.restaurantId] : null),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final jobs = ref.watch(jobsProvider).value ?? const <Job>[];
    final now = DateTime.now();
    final today = _day(now);
    final start = _gridStart;
    final grid = [for (var i = 0; i < 42; i++) DateTime(start.year, start.month, start.day + i)];
    final last = grid.last;
    // Tylko tyle tygodni, ile ma miesiąc (jak w Apple Calendar), bez pustego szóstego rzędu.
    final weeks = grid.sublist(35).any((d) => d.month == _month.month) ? 6 : (grid[28].month == _month.month ? 5 : 4);

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
    final monday = DateTime(_selected.year, _selected.month, _selected.day - (_selected.weekday - 1));
    final notes = ref.watch(weekNotesProvider((from: start, to: last))).value ?? const <DateTime, String>{};

    void tapDay(DateTime day) {
      final entry = byDay[day];
      final dayEvents = eventsOn(day);
      if (_view == _View.list) {
        // Lista: pierwsze stuknięcie zaznacza dzień (szczegóły pod siatką), drugie otwiera godziny.
        if (day == _selected) {
          _open(jobs, day, entry, window);
          return;
        }
        setState(() {
          _selected = day;
          if (day.month != _month.month) _month = DateTime(day.year, day.month);
        });
        return;
      }
      setState(() {
        _selected = day;
        if (day.month != _month.month) _month = DateTime(day.year, day.month);
      });
      if (canEnter(day) && dayEvents.isEmpty) {
        _hours(jobs, day);
      } else if (entry != null || dayEvents.isNotEmpty || (!day.isBefore(today) && jobs.isNotEmpty)) {
        _openDay(
          jobs: jobs,
          day: day,
          entry: entry,
          window: window,
          events: dayEvents,
          canEnter: canEnter(day),
          names: names,
        );
      }
    }

    final month = ListView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 32),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    _months[_month.month - 1],
                    style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
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
              for (final (i, d) in _weekdaysMini.indexed)
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: text.labelSmall?.copyWith(color: i >= 5 ? AppColors.textMuted : AppColors.text),
                    ),
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
              for (var w = 0; w < weeks; w++) ...[
                // Cienka kreska nad każdym tygodniem, jak w Apple Calendar.
                Divider(height: 1, thickness: 0.5, color: AppColors.ring),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final day in grid.sublist(w * 7, w * 7 + 7))
                      Expanded(
                        child: _DayCell(
                          view: _view,
                          day: day,
                          inMonth: day.month == _month.month,
                          today: today,
                          selected: _view == _View.list && day == _selected,
                          entry: byDay[day],
                          canEnter: canEnter(day),
                          events: eventsOn(day),
                          onTap: () => tapDay(day),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        // Lista: wybrany dzień pod siatką (moje godziny i wydarzenia).
        if (_view == _View.list) ...[
          Divider(height: 1, thickness: 0.5, color: AppColors.ring),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 10),
            child: Text(_dayTitle(_selected, today), style: text.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (async.hasError && !async.hasValue)
                  ErrorView(error: async.error!, onRetry: () => ref.invalidate(schedulePeriodProvider))
                else if (!loaded)
                  const ExcludeSemantics(child: SkeletonBox(width: double.infinity, height: 68, radius: 16))
                else if (jobs.isNotEmpty)
                  _DayRow(
                    day: _selected,
                    today: today,
                    entry: byDay[_selected],
                    closed: period != null && _selected.isBefore(period.from),
                    later: period != null && _selected.isAfter(period.to),
                    canEnter: canEnter(_selected),
                    onTap: () => _open(jobs, _selected, byDay[_selected], window),
                  ),
                for (final e in eventsOn(_selected))
                  CalendarEventTile(event: e, day: _selected, restaurant: ids.length > 1 ? names[e.restaurantId] : null),
              ],
            ),
          ),
        ],
        // Moja uwaga na tydzień dla przełożonego (tydzień wybranego dnia).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _WeekNoteRow(
            week: monday,
            note: notes[monday],
            onTap: jobs.isEmpty ? null : () => _weekNote(jobs, monday, notes[monday]),
          ),
        ),
      ],
    );

    void goToday() => _goTo(today);
    return Scaffold(
      // Jak w Apple Calendar: „‹ 2026” wraca do całego roku, po prawej widok, „Dzisiaj” i „+”, wszystko na
      // Liquid Glass.
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: _yearView ? 0 : 132,
        leading: _yearView
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  // Strzałka to znak symbolu SF „chevron.left” w napisie natywnego przycisku (U+100189).
                  child: GlassTextButton(
                    label: '\u{100189} ${_month.year}',
                    semanticLabel: 'Cały rok ${_month.year}',
                    onTap: _openYear,
                    fallback: _YearPill(year: _month.year, onTap: _openYear),
                  ),
                ),
              ),
        actions: [
          if (!_yearView)
            GlassMenuButton(
              symbol: _view.symbol,
              items: [
                for (final v in _View.values)
                  (
                    label: v.label,
                    symbol: v.symbol,
                    icon: v.icon,
                    selected: v == _view,
                    dividerBefore: v == _View.list,
                  ),
              ],
              onSelected: (i) => _setView(_View.values[i]),
              fallback: IconButton(
                tooltip: 'Widok: ${_view.label}',
                onPressed: _pickView,
                icon: Glyph(_view.icon),
              ),
            ),
          GlassTextButton(
            label: 'Dzisiaj',
            onTap: goToday,
            fallback: TextButton(onPressed: goToday, child: const Text('Dzisiaj')),
          ),
          if (canAdd.isNotEmpty) ...[
            const SizedBox(width: 2),
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

/// „‹ 2026” poza iOS 26: ciemna pigułka ze strzałką i rokiem, jak natywna na iPhonie.
class _YearPill extends StatelessWidget {
  const _YearPill({required this.year, required this.onTap});

  final int year;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Cały rok $year',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surfaceRaised,
        shape: StadiumBorder(side: BorderSide(color: AppColors.ring)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 16, 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Glyph(AppIcons.caretLeft, size: 18, color: AppColors.text),
                const SizedBox(width: 6),
                Text(
                  '$year',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                    fontFeatures: _tabular,
                  ),
                ),
              ],
            ),
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

/// Dzień w siatce miesiąca w wybranym widoku (jak w Apple Calendar):
/// - Kompaktowy i Lista: numer, pod nim kreska grafiku w kolorze stanu i kropki wydarzeń;
/// - Skumulowany: pod numerem paski (grafik w kolorze stanu, wydarzenia w swoich kolorach);
/// - Szczegóły: wysoki dzień z etykietami (moje godziny i nazwy wydarzeń).
/// Dziś na czerwono, wybrany dzień (w Liście) w kółku. Dzień okna zgłaszania, w który mogę jeszcze wpisać godziny,
/// jest zielonym polem.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.view,
    required this.day,
    required this.inMonth,
    required this.today,
    required this.selected,
    required this.entry,
    required this.canEnter,
    required this.events,
    required this.onTap,
  });

  final _View view;
  final DateTime day;
  final bool inMonth;
  final DateTime today;
  final bool selected;
  final PlannedShift? entry;
  final bool canEnter;
  final List<StaffEvent> events;
  final VoidCallback onTap;

  /// Godziny krótko: „10–18”, „10:30–18”.
  static String _short(String hm) => hm.endsWith(':00') ? hm.substring(0, hm.length - 3).replaceFirst(RegExp('^0'), '') : hm;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isToday = day == today;
    final e = entry;
    final mark = e == null ? null : _dayStatus(e, past: day.isBefore(today));
    final hours = e != null && !e.off && !e.unavailable ? '${e.starts}–${e.ends}' : null;
    final height = switch (view) {
      _View.details => 104.0,
      _View.stacked => 74.0,
      _ => 56.0,
    };
    final top = view == _View.details || view == _View.stacked;

    final number = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isToday ? _red : (selected ? AppColors.text : null),
      ),
      child: Text(
        '${day.day}',
        style: text.titleSmall?.copyWith(
          fontFeatures: _tabular,
          fontWeight: selected || isToday || canEnter ? FontWeight.w600 : FontWeight.w400,
          color: isToday
              ? Colors.white
              : selected
              ? AppColors.background
              : canEnter
              ? AppColors.accent
              : (inMonth ? AppColors.text : AppColors.textMuted),
        ),
      ),
    );

    // Co jest w dniu: moje godziny (kolor stanu) i wydarzenia (ich kolory).
    final items = <({String label, Color color})>[
      if (e != null && mark != null)
        (label: hours != null ? '${_short(e.starts)}–${_short(e.ends)}' : mark.label, color: mark.color),
      for (final ev in events) (label: ev.title, color: eventColor(ev)),
    ];

    final Widget marks = switch (view) {
      _View.compact || _View.list => SizedBox(
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
      _View.stacked => Column(
        children: [
          for (final item in items.take(4))
            Container(
              height: 5,
              margin: const EdgeInsets.fromLTRB(3, 1.5, 3, 1.5),
              decoration: BoxDecoration(color: item.color, borderRadius: BorderRadius.circular(3)),
            ),
        ],
      ),
      _View.details => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items.take(items.length > 3 ? 2 : 3)) _Chip(label: item.label, color: item.color),
          if (items.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 1),
              child: Text(
                '+${items.length - 2}',
                textScaler: TextScaler.noScaling,
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    };

    return Semantics(
      button: true,
      selected: selected,
      label: [
        '${day.day} ${_monthsGenitive[day.month - 1]}',
        if (isToday) 'dziś',
        ?hours,
        if (mark != null) mark.label,
        if (canEnter) 'możesz wpisać godziny',
        for (final ev in events) ev.title,
      ].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Material(
          color: canEnter ? AppColors.accentTint : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: canEnter ? BorderSide(color: AppColors.accent.withValues(alpha: 0.45)) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Column(
                mainAxisAlignment: top ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  if (top) const SizedBox(height: 4),
                  number,
                  SizedBox(height: top ? 4 : 3),
                  marks,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Etykieta w widoku Szczegóły: kropka w kolorze i nazwa na lekko zabarwionym tle.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      margin: const EdgeInsets.fromLTRB(2, 1, 2, 1),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 9.5,
                height: 1.1,
                fontWeight: FontWeight.w600,
                fontFeatures: _tabular,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
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
