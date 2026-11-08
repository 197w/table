import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../../shared/side_panel.dart';

// Management → Kalendarz (0080, 8.11.2026, prośba użytkownika: wygląd jak Notion Calendar, działanie z zadania
// „Kalendarz” w Todoist). Po lewej zwijany panel z mini kalendarzem miesiąca i kalendarzami do włączania,
// u góry miesiąc, „Dziś”, strzałki i widok Dzień / Tydzień / Miesiąc, siatka godzin z paskiem „cały dzień” i czerwoną
// linią „teraz”, po prawej panel wydarzenia. Zaznaczenie wolnego miejsca tworzy wydarzenie, blok przesuwa się
// przeciąganiem, dolna krawędź zmienia długość (co 15 min). Skróty: T dziś, D / W / M widok, J / K albo strzałki.

const _tabular = [FontFeature.tabularFigures()];

/// Dziś i linia „teraz” na czerwono, jak w Notion Calendar.
const _red = Color(0xFFEB5757);
const _hourHeight = 48.0;
const _gutter = 72.0;
const _snapMinutes = 15;

const _weekdays = ['pon', 'wt', 'śr', 'czw', 'pt', 'sob', 'niedz'];
const _weekdaysMini = ['P', 'W', 'Ś', 'C', 'P', 'S', 'N'];
const _months = [
  'Styczeń',
  'Luty',
  'Marzec',
  'Kwiecień',
  'Maj',
  'Czerwiec',
  'Lipiec',
  'Sierpień',
  'Wrzesień',
  'Październik',
  'Listopad',
  'Grudzień',
];
const _monthsShort = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];
const _monthsGenitive = [
  'stycznia',
  'lutego',
  'marca',
  'kwietnia',
  'maja',
  'czerwca',
  'lipca',
  'sierpnia',
  'września',
  'października',
  'listopada',
  'grudnia',
];

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);
DateTime _mondayOf(DateTime d) => _dayOf(d).subtract(Duration(days: d.weekday - 1));
bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute);

/// „18:00–20:00”, a przez północ „22:00–02:00”.
String eventTimeLabel(CalendarEvent e) {
  if (e.allDay) {
    final last = _addDays(e.endsAt, -1);
    return _sameDay(e.startsAt, last)
        ? 'Cały dzień'
        : '${e.startsAt.day} ${_monthsShort[e.startsAt.month - 1]} – ${last.day} ${_monthsShort[last.month - 1]}';
  }
  if (_sameDay(e.startsAt, e.endsAt) || e.endsAt == _addDays(_dayOf(e.startsAt), 1)) {
    return '${_hm(e.startsAt)}–${_hm(e.endsAt)}';
  }
  return '${e.startsAt.day} ${_monthsShort[e.startsAt.month - 1]} ${_hm(e.startsAt)} – '
      '${e.endsAt.day} ${_monthsShort[e.endsAt.month - 1]} ${_hm(e.endsAt)}';
}

enum _View {
  day('Dzień'),
  week('Tydzień'),
  month('Miesiąc');

  const _View(this.label);
  final String label;
}

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  _View _view = _View.week;
  DateTime _anchor = _dayOf(DateTime.now());
  late DateTime _miniMonth = DateTime(_anchor.year, _anchor.month);
  final _hidden = <CalendarKind>{};
  bool _panelOpen = true;

  /// Wydarzenie w panelu po prawej (nowe bez numeru albo zapisane).
  CalendarEvent? _editing;

  /// Przesunięte myszą, zanim baza potwierdzi zapis (bez skoku z powrotem).
  final _moved = <String, CalendarEvent>{};
  final _focus = FocusNode(debugLabel: 'kalendarz');
  final _scroll = ScrollController(initialScrollOffset: 8 * _hourHeight - 12);
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  DateTime get _gridStart => _mondayOf(DateTime(_anchor.year, _anchor.month));

  (DateTime, DateTime) get _range => switch (_view) {
    _View.day => (_anchor, _addDays(_anchor, 1)),
    _View.week => (_mondayOf(_anchor), _addDays(_mondayOf(_anchor), 7)),
    _View.month => (_gridStart, _addDays(_gridStart, 42)),
  };

  void _go(DateTime day) => setState(() {
    _anchor = _dayOf(day);
    _miniMonth = DateTime(_anchor.year, _anchor.month);
  });

  void _shift(int dir) => _go(switch (_view) {
    _View.day => _addDays(_anchor, dir),
    _View.week => _addDays(_anchor, 7 * dir),
    _View.month => DateTime(_anchor.year, _anchor.month + dir),
  });

  void _create(DateTime start, DateTime end) {
    if (!_canEdit) return;
    setState(() => _editing = CalendarEvent(kind: CalendarKind.special, title: '', startsAt: start, endsAt: end));
  }

  bool get _canEdit => ref.read(memberPermissionsProvider).contains('calendar');

  Future<void> _save(String restaurantId, CalendarEvent e) async {
    try {
      await ref
          .read(repositoryProvider)
          .saveCalendarEvent(restaurantId, e, memberId: ref.read(panelMemberProvider)?.dbMemberId);
      ref.invalidate(calendarEventsProvider);
      if (!mounted) return;
      setState(() => _editing = null);
      showMessage(context, e.id == null ? 'Dodano: ${e.title}.' : 'Zapisano: ${e.title}.', tone: ToastTone.success);
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  Future<void> _move(String restaurantId, CalendarEvent e) async {
    setState(() {
      _moved[e.id!] = e;
      if (_editing?.id == e.id) _editing = e;
    });
    try {
      await ref
          .read(repositoryProvider)
          .saveCalendarEvent(restaurantId, e, memberId: ref.read(panelMemberProvider)?.dbMemberId);
      ref.invalidate(calendarEventsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    } catch (err) {
      if (mounted) showError(context, err);
    } finally {
      if (mounted) setState(() => _moved.remove(e.id));
    }
  }

  Future<void> _delete(CalendarEvent e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Usunąć „${e.title}”?'),
        content: Text(
          e.kind == CalendarKind.special
              ? 'Goście przestaną je widzieć na stronie lokalu.'
              : 'Pracownicy przestaną je widzieć w kalendarzu.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Wróć')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repositoryProvider).deleteCalendarEvent(e.id!);
      ref.invalidate(calendarEventsProvider);
      if (mounted) setState(() => _editing = null);
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Pisanie w polach panelu nie zmienia widoku.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) return KeyEventResult.ignored;
    final key = event.logicalKey;
    void run(VoidCallback f) => f();
    if (key == LogicalKeyboardKey.keyT) {
      run(() => _go(DateTime.now()));
    } else if (key == LogicalKeyboardKey.keyD) {
      setState(() => _view = _View.day);
    } else if (key == LogicalKeyboardKey.keyW) {
      setState(() => _view = _View.week);
    } else if (key == LogicalKeyboardKey.keyM) {
      setState(() => _view = _View.month);
    } else if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.arrowRight) {
      _shift(1);
    } else if (key == LogicalKeyboardKey.keyK || key == LogicalKeyboardKey.arrowLeft) {
      _shift(-1);
    } else if (key == LogicalKeyboardKey.escape && _editing != null) {
      setState(() => _editing = null);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String get _title {
    final (from, to) = _range;
    switch (_view) {
      case _View.month:
        return '${_months[_anchor.month - 1]} ${_anchor.year}';
      case _View.day:
        return '${_anchor.day} ${_monthsGenitive[_anchor.month - 1]} ${_anchor.year}';
      case _View.week:
        final last = _addDays(to, -1);
        if (from.month == last.month) return '${_months[from.month - 1]} ${from.year}';
        return '${Fmt.capitalize(_monthsShort[from.month - 1])} – ${Fmt.capitalize(_monthsShort[last.month - 1])} ${last.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final rid = restaurant.id;
    final editable = ref.watch(memberPermissionsProvider).contains('calendar');
    final (from, to) = _range;
    final async = ref.watch(calendarEventsProvider((restaurantId: rid, from: from, to: to)));
    final loaded = async.value ?? const <CalendarEvent>[];
    final events = [
      for (final e in loaded)
        if (!_hidden.contains(e.kind)) _moved[e.id] ?? e,
      // Nowe wydarzenie w panelu widać od razu w siatce.
      if (_editing case final draft? when draft.id == null) draft,
    ];
    final today = _dayOf(_now);
    final text = Theme.of(context).textTheme;

    final panel = SidePanel(
      header: const PanelTitle(icon: AppIcons.calendar, title: 'Kalendarz'),
      actions: [
        if (editable)
          PanelAction(
            label: 'Nowe wydarzenie',
            active: _editing?.id == null && _editing != null,
            onTap: () {
              final start = DateTime(_anchor.year, _anchor.month, _anchor.day, math.max(_now.hour + 1, 9));
              _create(start, start.add(const Duration(hours: 1)));
            },
          ),
      ],
      children: [
        _MiniMonth(
          month: _miniMonth,
          today: today,
          selectedFrom: from,
          selectedTo: _view == _View.month ? from : to,
          onMonth: (dir) => setState(() => _miniMonth = DateTime(_miniMonth.year, _miniMonth.month + dir)),
          onPick: (d) {
            _go(d);
            if (_view == _View.month) setState(() => _view = _View.day);
          },
        ),
        const SizedBox(height: 20),
        Text('Kalendarze', style: text.labelLarge),
        const SizedBox(height: 6),
        for (final kind in CalendarKind.values)
          _KindToggle(
            kind: kind,
            on: !_hidden.contains(kind),
            onChanged: (on) => setState(() => on ? _hidden.remove(kind) : _hidden.add(kind)),
          ),
        const SizedBox(height: 20),
        Text(
          'Skróty: T dziś · D, W, M widok · J i K albo strzałki: poprzedni i następny',
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );

    final grid = switch (_view) {
      _View.month => _MonthGrid(
        start: _gridStart,
        month: _anchor.month,
        today: today,
        events: events,
        selectedId: _editing?.id,
        onEvent: (e) => setState(() => _editing = e),
        onDay: (d) => setState(() {
          _go(d);
          _view = _View.day;
        }),
      ),
      _ => _TimeGrid(
        days: [for (var i = 0; i < (_view == _View.day ? 1 : 7); i++) _addDays(from, i)],
        events: events,
        now: _now,
        selectedId: _editing?.id,
        draft: _editing?.id == null ? _editing : null,
        editable: editable,
        scroll: _scroll,
        onEvent: (e) {
          _focus.requestFocus();
          setState(() => _editing = e);
        },
        onCreate: (start, end) {
          _focus.requestFocus();
          _create(start, end);
        },
        onMove: (e) => _move(rid, e),
      ),
    };

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                Text(_title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 16),
                OutlinedButton(onPressed: () => _go(DateTime.now()), child: const Text('Dziś')),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Poprzedni (K)',
                  onPressed: () => _shift(-1),
                  icon: const Glyph(AppIcons.caretLeft, size: 18),
                ),
                IconButton(
                  tooltip: 'Następny (J)',
                  onPressed: () => _shift(1),
                  icon: const Glyph(AppIcons.caretRight, size: 18),
                ),
                if (async.isLoading && async.hasValue) ...[
                  const SizedBox(width: 8),
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
                const Spacer(),
                SegmentedTabs<_View>(
                  options: [for (final v in _View.values) (v, v.label)],
                  selected: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: async.hasError && !async.hasValue
                        ? ErrorView(error: async.error!, onRetry: () => ref.invalidate(calendarEventsProvider))
                        : grid,
                  ),
                ),
                if (_editing case final e?) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 340,
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: _EventPanel(
                        key: ValueKey(e.id ?? 'nowe'),
                        event: e,
                        editable: editable,
                        restaurantId: rid,
                        onClose: () => setState(() => _editing = null),
                        onSave: (updated) => _save(rid, updated),
                        onDelete: e.id == null ? null : () => _delete(e),
                        onDraft: (updated) {
                          // Nowe wydarzenie: zmiany godzin w panelu przesuwają też szkic w siatce.
                          if (e.id == null) setState(() => _editing = updated);
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: SidePanelLayout(
        open: _panelOpen,
        onToggle: () => setState(() => _panelOpen = !_panelOpen),
        panel: panel,
        content: content,
      ),
    );
  }
}

/// Mini kalendarz miesiąca w panelu: dziś na czerwono, zaznaczony widoczny zakres, strzałki miesięcy.
class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.month,
    required this.today,
    required this.selectedFrom,
    required this.selectedTo,
    required this.onMonth,
    required this.onPick,
  });

  final DateTime month;
  final DateTime today;
  final DateTime selectedFrom;

  /// Koniec zaznaczenia (bez tego dnia). Równy [selectedFrom]: bez zaznaczenia (widok miesiąca).
  final DateTime selectedTo;
  final ValueChanged<int> onMonth;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final start = _mondayOf(month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${_months[month.month - 1]} ${month.year}', style: text.labelLarge),
            ),
            IconButton(
              tooltip: 'Poprzedni miesiąc',
              visualDensity: VisualDensity.compact,
              onPressed: () => onMonth(-1),
              icon: const Glyph(AppIcons.caretLeft, size: 14),
            ),
            IconButton(
              tooltip: 'Następny miesiąc',
              visualDensity: VisualDensity.compact,
              onPressed: () => onMonth(1),
              icon: const Glyph(AppIcons.caretRight, size: 14),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final d in _weekdaysMini)
              Expanded(
                child: Center(
                  child: Text(d, style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        for (var w = 0; w < 6; w++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final day = _addDays(start, w * 7 + i);
                      final inMonth = day.month == month.month;
                      final isToday = _sameDay(day, today);
                      final selected = !day.isBefore(selectedFrom) && day.isBefore(selectedTo);
                      return InkWell(
                        onTap: () => onPick(day),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          height: 30,
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.surfaceRaised : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: isToday ? const BoxDecoration(color: _red, shape: BoxShape.circle) : null,
                            child: Text(
                              '${day.day}',
                              style: text.labelMedium?.copyWith(
                                fontFeatures: _tabular,
                                color: isToday
                                    ? Colors.white
                                    : (inMonth ? AppColors.text : AppColors.textDisabled),
                                fontWeight: isToday ? FontWeight.w600 : null,
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
    );
  }
}

/// Kalendarz do włączania i wyłączania w panelu (jak lista kalendarzy w Notion Calendar).
class _KindToggle extends StatelessWidget {
  const _KindToggle({required this.kind, required this.on, required this.onChanged});

  final CalendarKind kind;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = kind == CalendarKind.special ? CalendarColor.green.color : CalendarColor.blue.color;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onChanged(!on),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: on ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color, width: 1.5),
              ),
              child: on ? const Glyph(AppIcons.check, size: 12, color: Colors.white) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kind.label, style: text.bodyMedium),
                  Text(kind.description, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wydarzenie w siatce dnia: miejsce w kolumnie przy nakładających się wydarzeniach.
typedef PlacedEvent = ({CalendarEvent event, DateTime start, DateTime end, int lane, int lanes});

/// Układ wydarzeń jednego dnia w pasy: nakładające się stoją obok siebie.
List<PlacedEvent> layoutDay(List<CalendarEvent> events, DateTime day) {
  final dayStart = _dayOf(day);
  final dayEnd = _addDays(dayStart, 1);
  final items = [
    for (final e in events)
      if (!e.spansDays && e.overlaps(dayStart, dayEnd))
        (
          event: e,
          start: e.startsAt.isBefore(dayStart) ? dayStart : e.startsAt,
          end: e.endsAt.isAfter(dayEnd) ? dayEnd : e.endsAt,
        ),
  ]..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : b.end.compareTo(a.end);
    });
  final result = <PlacedEvent>[];
  var cluster = <({CalendarEvent event, DateTime start, DateTime end, int lane})>[];
  DateTime? clusterEnd;
  void flush() {
    final lanes = cluster.fold(0, (m, c) => math.max(m, c.lane + 1));
    for (final c in cluster) {
      result.add((event: c.event, start: c.start, end: c.end, lane: c.lane, lanes: lanes));
    }
    cluster = [];
    clusterEnd = null;
  }

  for (final it in items) {
    if (clusterEnd != null && !it.start.isBefore(clusterEnd!)) flush();
    // Pierwszy wolny pas w grupie.
    var lane = 0;
    while (cluster.any((c) => c.lane == lane && c.end.isAfter(it.start))) {
      lane++;
    }
    cluster.add((event: it.event, start: it.start, end: it.end, lane: lane));
    clusterEnd = clusterEnd == null || it.end.isAfter(clusterEnd!) ? it.end : clusterEnd;
  }
  if (cluster.isNotEmpty) flush();
  return result;
}

enum _Drag { move, resize, create }

/// Siatka godzin (dzień albo tydzień): nagłówki dni, pasek „cały dzień”, godziny i wydarzenia.
class _TimeGrid extends StatefulWidget {
  const _TimeGrid({
    required this.days,
    required this.events,
    required this.now,
    required this.selectedId,
    required this.draft,
    required this.editable,
    required this.scroll,
    required this.onEvent,
    required this.onCreate,
    required this.onMove,
  });

  final List<DateTime> days;
  final List<CalendarEvent> events;
  final DateTime now;
  final String? selectedId;
  final CalendarEvent? draft;
  final bool editable;
  final ScrollController scroll;
  final ValueChanged<CalendarEvent> onEvent;
  final void Function(DateTime start, DateTime end) onCreate;
  final ValueChanged<CalendarEvent> onMove;

  @override
  State<_TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<_TimeGrid> {
  _Drag? _mode;
  CalendarEvent? _origin;
  CalendarEvent? _preview;
  Offset _start = Offset.zero;
  int _createDay = 0;
  double _createFrom = 0;
  double _createTo = 0;

  DateTime _timeAt(DateTime day, double y) {
    final minutes = ((y / _hourHeight * 60) / _snapMinutes).round() * _snapMinutes;
    return _dayOf(day).add(Duration(minutes: minutes.clamp(0, 24 * 60)));
  }

  double _yOf(DateTime day, DateTime t) => t.difference(_dayOf(day)).inMinutes / 60 * _hourHeight;

  void _beginEvent(CalendarEvent e, _Drag mode, Offset global) {
    if (!widget.editable || e.id == null) return;
    _mode = mode;
    _origin = e;
    _preview = e;
    _start = global;
  }

  void _updateEvent(Offset global, double colWidth) {
    final o = _origin;
    if (o == null) return;
    final d = global - _start;
    final minutes = ((d.dy / _hourHeight * 60) / _snapMinutes).round() * _snapMinutes;
    final days = widget.days.length == 1 ? 0 : (d.dx / colWidth).round();
    setState(() {
      if (_mode == _Drag.resize) {
        final end = o.endsAt.add(Duration(minutes: minutes));
        final minEnd = o.startsAt.add(const Duration(minutes: _snapMinutes));
        _preview = o.copyWith(endsAt: end.isBefore(minEnd) ? minEnd : end);
      } else {
        final shift = Duration(days: days, minutes: minutes);
        _preview = o.copyWith(startsAt: o.startsAt.add(shift), endsAt: o.endsAt.add(shift));
      }
    });
  }

  void _endEvent() {
    final o = _origin;
    final p = _preview;
    _mode = null;
    _origin = null;
    _preview = null;
    setState(() {});
    if (o != null && p != null && (p.startsAt != o.startsAt || p.endsAt != o.endsAt)) widget.onMove(p);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final days = widget.days;
    final today = _dayOf(widget.now);
    final events = [
      for (final e in widget.events)
        if (_preview != null && e.id != null && e.id == _preview!.id) _preview! else e,
    ];
    final offset = widget.now.timeZoneOffset;
    final tz = 'GMT${offset.isNegative ? '−' : '+'}${offset.inHours.abs()}';

    // Pasek „cały dzień”: całodniowe i wielodniowe w pasach.
    final first = days.first;
    final last = _addDays(days.last, 1);
    final spans = [for (final e in events) if (e.spansDays && e.overlaps(first, last)) e]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final spanLanes = <(CalendarEvent, int, int, int)>[];
    final laneEnds = <int>[];
    for (final e in spans) {
      final from = math.max(0, _dayOf(e.startsAt).difference(first).inDays);
      final to = math.min(days.length - 1, _dayOf(e.endsAt.subtract(const Duration(microseconds: 1))).difference(first).inDays);
      var lane = laneEnds.indexWhere((end) => end < from);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(to);
      } else {
        laneEnds[lane] = to;
      }
      spanLanes.add((e, from, to, lane));
    }
    final allDayHeight = math.max(28.0, laneEnds.length * 24.0 + 6);

    return LayoutBuilder(
      builder: (context, box) {
        final colWidth = (box.maxWidth - _gutter) / days.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Nagłówki dni.
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  SizedBox(
                    width: _gutter,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10, bottom: 4),
                        child: Text(tz, style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
                      ),
                    ),
                  ),
                  for (final d in days)
                    Expanded(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _weekdays[d.weekday - 1],
                              style: text.labelMedium?.copyWith(
                                color: _sameDay(d, today) ? _red : AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: _sameDay(d, today)
                                  ? BoxDecoration(color: _red, borderRadius: BorderRadius.circular(8))
                                  : null,
                              child: Text(
                                '${d.day}',
                                style: text.titleMedium?.copyWith(
                                  fontFeatures: _tabular,
                                  color: _sameDay(d, today) ? Colors.white : AppColors.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Cały dzień.
            Container(
              height: allDayHeight,
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.ring))),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    width: _gutter,
                    top: 6,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                        'cały dzień',
                        textAlign: TextAlign.right,
                        style: text.labelSmall?.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  for (final (e, from, to, lane) in spanLanes)
                    Positioned(
                      left: _gutter + from * colWidth + 2,
                      width: (to - from + 1) * colWidth - 4,
                      top: 3.0 + lane * 24,
                      height: 21,
                      child: _EventChip(
                        event: e,
                        selected: e.id != null && e.id == widget.selectedId || identical(e, widget.draft),
                        onTap: () => widget.onEvent(e),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.ring),
            Expanded(
              child: SingleChildScrollView(
                controller: widget.scroll,
                child: SizedBox(
                  height: 24 * _hourHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _GridPainter(columns: days.length, gutter: _gutter, line: AppColors.ring),
                        ),
                      ),
                      // Godziny po lewej.
                      for (var h = 1; h < 24; h++)
                        Positioned(
                          top: h * _hourHeight - 7,
                          left: 0,
                          width: _gutter - 10,
                          child: Text(
                            '${_two(h)}:00',
                            textAlign: TextAlign.right,
                            style: text.labelSmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                          ),
                        ),
                      for (final (i, d) in days.indexed) ..._column(context, i, d, colWidth, events, today),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _column(BuildContext context, int index, DateTime day, double colWidth, List<CalendarEvent> events,
      DateTime today) {
    final left = _gutter + index * colWidth;
    final text = Theme.of(context).textTheme;
    final widgets = <Widget>[
      // Wolne miejsce: kliknięcie tworzy godzinne wydarzenie, przeciągnięcie wybiera godziny.
      Positioned(
        left: left,
        top: 0,
        width: colWidth,
        height: 24 * _hourHeight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.editable
              ? (d) {
                  final start = _timeAt(day, d.localPosition.dy - _hourHeight / 4);
                  widget.onCreate(start, start.add(const Duration(hours: 1)));
                }
              : null,
          onVerticalDragStart: widget.editable
              ? (d) => setState(() {
                  _mode = _Drag.create;
                  _createDay = index;
                  _createFrom = d.localPosition.dy;
                  _createTo = d.localPosition.dy;
                })
              : null,
          onVerticalDragUpdate: widget.editable ? (d) => setState(() => _createTo = d.localPosition.dy) : null,
          onVerticalDragEnd: widget.editable
              ? (_) {
                  final start = _timeAt(day, math.min(_createFrom, _createTo));
                  var end = _timeAt(day, math.max(_createFrom, _createTo));
                  if (end.difference(start).inMinutes < 30) end = start.add(const Duration(minutes: 30));
                  setState(() => _mode = null);
                  widget.onCreate(start, end);
                }
              : null,
        ),
      ),
    ];
    if (_mode == _Drag.create && _createDay == index) {
      final top = _yOf(day, _timeAt(day, math.min(_createFrom, _createTo)));
      final bottom = _yOf(day, _timeAt(day, math.max(_createFrom, _createTo)));
      widgets.add(
        Positioned(
          left: left + 2,
          width: colWidth - 4,
          top: top,
          height: math.max(bottom - top, _hourHeight / 2),
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ),
      );
    }
    for (final p in layoutDay(events, day)) {
      final top = _yOf(day, p.start);
      final height = math.max(_yOf(day, p.end) - top, 18.0);
      final width = (colWidth - 6) / p.lanes;
      final e = p.event;
      final selected = (e.id != null && e.id == widget.selectedId) || identical(e, widget.draft);
      widgets.add(
        Positioned(
          left: left + 2 + p.lane * width,
          width: width - 1,
          top: top + 1,
          height: height - 2,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onEvent(e),
            onPanStart: (d) => _beginEvent(e, _Drag.move, d.globalPosition),
            onPanUpdate: (d) => _updateEvent(d.globalPosition, colWidth),
            onPanEnd: (_) => _endEvent(),
            child: MouseRegion(
              cursor: widget.editable && e.id != null ? SystemMouseCursors.move : SystemMouseCursors.click,
              child: Stack(
                children: [
                  Positioned.fill(child: _EventBlock(event: e, selected: selected, height: height)),
                  // Dolna krawędź zmienia długość.
                  if (widget.editable && e.id != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 6,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: (d) => _beginEvent(e, _Drag.resize, d.globalPosition),
                          onVerticalDragUpdate: (d) => _updateEvent(d.globalPosition, colWidth),
                          onVerticalDragEnd: (_) => _endEvent(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_sameDay(day, today)) {
      final y = _yOf(day, widget.now);
      widgets.add(
        Positioned(
          left: left - 4,
          width: colWidth + 4,
          top: y - 4,
          height: 8,
          child: IgnorePointer(
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: _red, shape: BoxShape.circle)),
                Expanded(child: Container(height: 2, color: _red)),
              ],
            ),
          ),
        ),
      );
      widgets.add(
        Positioned(
          top: y - 8,
          left: 0,
          width: _gutter - 10,
          child: IgnorePointer(
            child: Container(
              color: Theme.of(context).cardTheme.color ?? AppColors.surface,
              child: Text(
                _hm(widget.now),
                textAlign: TextAlign.right,
                style: text.labelSmall?.copyWith(color: _red, fontWeight: FontWeight.w600, fontFeatures: _tabular),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.columns, required this.gutter, required this.line});

  final int columns;
  final double gutter;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var h = 1; h < 24; h++) {
      final y = h * _hourHeight + 0.5;
      canvas.drawLine(Offset(gutter - 6, y), Offset(size.width, y), paint);
    }
    final colWidth = (size.width - gutter) / columns;
    for (var i = 0; i <= columns - 1; i++) {
      final x = gutter + i * colWidth + 0.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.columns != columns || old.line != line || old.gutter != gutter;
}

/// Blok wydarzenia w siatce godzin: jasne tło w kolorze wydarzenia i kreska po lewej (jak w Notion Calendar).
class _EventBlock extends StatelessWidget {
  const _EventBlock({required this.event, required this.selected, required this.height});

  final CalendarEvent event;
  final bool selected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = event.color.color;
    final title = event.title.trim().isEmpty ? 'Nowe wydarzenie' : event.title;
    return Container(
      decoration: BoxDecoration(
        color: c.withValues(alpha: selected ? 0.34 : 0.2),
        borderRadius: BorderRadius.circular(6),
        border: selected ? Border.all(color: c, width: 1.2) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 3, color: c),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 3, 4, 2),
              child: height < 34
                  ? Text(
                      '$title  ${_hm(event.startsAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, fontFeatures: _tabular),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: height < 60 ? 1 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          eventTimeLabel(event),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelSmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wydarzenie w pasku „cały dzień” i w siatce miesiąca.
class _EventChip extends StatelessWidget {
  const _EventChip({required this.event, required this.selected, required this.onTap});

  final CalendarEvent event;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = event.color.color;
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: c.withValues(alpha: selected ? 0.4 : 0.22),
            borderRadius: BorderRadius.circular(5),
            border: selected ? Border.all(color: c) : null,
          ),
          child: Text(
            [
              if (!event.spansDays) _hm(event.startsAt),
              event.title.trim().isEmpty ? 'Nowe wydarzenie' : event.title,
            ].join(' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, fontFeatures: _tabular),
          ),
        ),
      ),
    );
  }
}

/// Widok miesiąca: 6 tygodni, w dniu do trzech wydarzeń i „+N”, kliknięcie dnia otwiera widok dnia.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.start,
    required this.month,
    required this.today,
    required this.events,
    required this.selectedId,
    required this.onEvent,
    required this.onDay,
  });

  final DateTime start;
  final int month;
  final DateTime today;
  final List<CalendarEvent> events;
  final String? selectedId;
  final ValueChanged<CalendarEvent> onEvent;
  final ValueChanged<DateTime> onDay;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        SizedBox(
          height: 32,
          child: Row(
            children: [
              for (final d in _weekdays)
                Expanded(
                  child: Center(child: Text(d, style: text.labelMedium?.copyWith(color: AppColors.textMuted))),
                ),
            ],
          ),
        ),
        for (var w = 0; w < 6; w++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final day = _addDays(start, w * 7 + i);
                        // Całodniowe i wielodniowe na górze, potem według godziny (jak w Notion Calendar).
                        final dayEvents = [
                          for (final e in events)
                            if (e.overlaps(day, _addDays(day, 1))) e,
                        ]..sort((a, b) {
                            if (a.spansDays != b.spansDays) return a.spansDays ? -1 : 1;
                            return a.startsAt.compareTo(b.startsAt);
                          });
                        final isToday = _sameDay(day, today);
                        return InkWell(
                          onTap: () => onDay(day),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: AppColors.ring),
                                left: i == 0 ? BorderSide.none : BorderSide(color: AppColors.ring),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final fit = math.max(0, ((box.maxHeight - 26) / 22).floor());
                                final shown = dayEvents.length > fit ? math.max(0, fit - 1) : dayEvents.length;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: isToday
                                            ? BoxDecoration(color: _red, borderRadius: BorderRadius.circular(8))
                                            : null,
                                        child: Text(
                                          day.day == 1 ? '${day.day} ${_monthsShort[day.month - 1]}' : '${day.day}',
                                          style: text.labelMedium?.copyWith(
                                            fontFeatures: _tabular,
                                            fontWeight: isToday ? FontWeight.w600 : null,
                                            color: isToday
                                                ? Colors.white
                                                : (day.month == month ? AppColors.text : AppColors.textDisabled),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    for (final e in dayEvents.take(shown))
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 2),
                                        child: SizedBox(
                                          height: 20,
                                          child: _EventChip(
                                            event: e,
                                            selected: e.id != null && e.id == selectedId,
                                            onTap: () => onEvent(e),
                                          ),
                                        ),
                                      ),
                                    if (dayEvents.length > shown)
                                      Text(
                                        '+${dayEvents.length - shown} więcej',
                                        style: text.labelSmall?.copyWith(color: AppColors.textMuted),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Panel wydarzenia po prawej (jak szczegóły w Notion Calendar): nazwa, rodzaj, czas, kolor, opis i menu na
/// wydarzenie specjalne. Bez uprawnienia „Kalendarz” tylko do odczytu.
class _EventPanel extends ConsumerStatefulWidget {
  const _EventPanel({
    super.key,
    required this.event,
    required this.editable,
    required this.restaurantId,
    required this.onClose,
    required this.onSave,
    required this.onDelete,
    required this.onDraft,
  });

  final CalendarEvent event;
  final bool editable;
  final String restaurantId;
  final VoidCallback onClose;
  final ValueChanged<CalendarEvent> onSave;
  final VoidCallback? onDelete;
  final ValueChanged<CalendarEvent> onDraft;

  @override
  ConsumerState<_EventPanel> createState() => _EventPanelState();
}

class _EventPanelState extends ConsumerState<_EventPanel> {
  late final _title = TextEditingController(text: widget.event.title);
  late final _description = TextEditingController(text: widget.event.description ?? '');
  late CalendarKind _kind = widget.event.kind;
  late bool _allDay = widget.event.allDay;
  late DateTime _start = widget.event.startsAt;
  late DateTime _end = widget.event.endsAt;
  late CalendarColor _color = widget.event.color;
  bool _busy = false;

  @override
  void didUpdateWidget(_EventPanel old) {
    super.didUpdateWidget(old);
    // Przeciągnięcie w siatce zmienia godziny otwartego wydarzenia.
    if (old.event.startsAt != widget.event.startsAt || old.event.endsAt != widget.event.endsAt) {
      _start = widget.event.startsAt;
      _end = widget.event.endsAt;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  CalendarEvent get _current => widget.event.copyWith(
    title: _title.text.trim(),
    kind: _kind,
    description: _description.text.trim().isEmpty ? null : _description.text.trim(),
    startsAt: _start,
    endsAt: _end,
    allDay: _allDay,
    color: _color,
  );

  void _changed() => widget.onDraft(_current);

  void _setAllDay(bool v) {
    setState(() {
      _allDay = v;
      if (v) {
        _start = _dayOf(_start);
        final lastDay = _dayOf(_end.subtract(const Duration(microseconds: 1)));
        _end = _addDays(lastDay.isBefore(_start) ? _start : lastDay, 1);
      } else {
        _start = DateTime(_start.year, _start.month, _start.day, 12);
        _end = _start.add(const Duration(hours: 1));
      }
    });
    _changed();
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _start : (_allDay ? _addDays(_end, -1) : _end);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        final length = _end.difference(_start);
        _start = DateTime(picked.year, picked.month, picked.day, _start.hour, _start.minute);
        _end = _start.add(length);
      } else if (_allDay) {
        final end = _addDays(_dayOf(picked), 1);
        _end = end.isAfter(_start) ? end : _addDays(_start, 1);
      } else {
        final end = DateTime(picked.year, picked.month, picked.day, _end.hour, _end.minute);
        _end = end.isAfter(_start) ? end : _start.add(const Duration(hours: 1));
      }
    });
    _changed();
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await pickTime(
      context,
      initial: TimeOfDay(hour: current.hour, minute: current.minute),
      title: start ? 'Początek' : 'Koniec',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        final length = _end.difference(_start);
        _start = DateTime(_start.year, _start.month, _start.day, picked.hour, picked.minute);
        _end = _start.add(length);
      } else {
        var end = DateTime(_end.year, _end.month, _end.day, picked.hour, picked.minute);
        // Koniec wcześniej niż początek tego samego dnia: następny dzień (np. 20:00–02:00).
        if (!end.isAfter(_start)) end = _addDays(end, 1);
        _end = end;
      }
    });
    _changed();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showMessage(context, 'Wpisz nazwę wydarzenia.', tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    widget.onSave(_current);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final on = widget.editable;
    final e = widget.event;
    final sections = [
      for (final s in ref.watch(menuProvider(widget.restaurantId)).value ?? const <MenuSection>[])
        if (e.id != null && s.eventId == e.id) s,
    ];
    Widget when(String label, {required bool start}) {
      final value = start ? _start : (_allDay ? _addDays(_end, -1) : _end);
      return Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.textMuted))),
          Expanded(
            child: OutlinedButton(
              onPressed: on ? () => _pickDate(start: start) : null,
              child: Text(
                '${value.day} ${_monthsShort[value.month - 1]} ${value.year}',
                style: const TextStyle(fontFeatures: _tabular),
              ),
            ),
          ),
          if (!_allDay) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: OutlinedButton(
                onPressed: on ? () => _pickTime(start: start) : null,
                child: Text(_hm(value), style: const TextStyle(fontFeatures: _tabular)),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  e.id == null ? 'Nowe wydarzenie' : 'Wydarzenie',
                  style: text.labelLarge?.copyWith(color: AppColors.textMuted),
                ),
              ),
              if (on && widget.onDelete != null) DeleteButton(onPressed: widget.onDelete),
              IconButton(tooltip: 'Zamknij (Esc)', onPressed: widget.onClose, icon: const Glyph(AppIcons.close, size: 16)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              TextField(
                controller: _title,
                enabled: on,
                autofocus: e.id == null,
                maxLength: 120,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                decoration: const InputDecoration(hintText: 'Nazwa wydarzenia', counterText: ''),
                onChanged: (_) => _changed(),
                onSubmitted: (_) => on ? _save() : null,
              ),
              const SizedBox(height: 14),
              IgnorePointer(
                ignoring: !on,
                child: SegmentedTabs<CalendarKind>(
                  options: const [(CalendarKind.special, 'Specjalne'), (CalendarKind.staff, 'Dla pracowników')],
                  selected: _kind,
                  expand: true,
                  onChanged: (k) {
                    setState(() {
                      _kind = k;
                      if (e.id == null) _color = k == CalendarKind.special ? CalendarColor.green : CalendarColor.blue;
                    });
                    _changed();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_kind.description, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text('Cały dzień', style: text.bodyMedium)),
                  Switch(value: _allDay, onChanged: on ? _setAllDay : null),
                ],
              ),
              const SizedBox(height: 8),
              when('Początek', start: true),
              const SizedBox(height: 8),
              when('Koniec', start: false),
              const SizedBox(height: 16),
              Text('Kolor', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in CalendarColor.values)
                    InkWell(
                      onTap: on
                          ? () {
                              setState(() => _color = c);
                              _changed();
                            }
                          : null,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: c.color,
                          shape: BoxShape.circle,
                          border: _color == c ? Border.all(color: AppColors.text, width: 2) : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _description,
                enabled: on,
                minLines: 3,
                maxLines: 8,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: 'Opis', counterText: ''),
                onChanged: (_) => _changed(),
              ),
              if (_kind == CalendarKind.special) ...[
                const SizedBox(height: 16),
                Text('Menu na wydarzenie', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 6),
                if (sections.isEmpty)
                  Text(
                    e.id == null
                        ? 'Po zapisaniu przypnij do wydarzenia dział menu: Menu → dział → „Tylko na wydarzenie”. '
                              'Goście zobaczą go tylko w czasie wydarzenia.'
                        : 'Bez osobnego menu. Dział tylko na to wydarzenie przypniesz w Menu → dział → „Tylko na '
                              'wydarzenie”.',
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  )
                else
                  for (final s in sections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Glyph(AppIcons.bookOpen, size: 16, color: AppColors.textMuted),
                          const SizedBox(width: 8),
                          Expanded(child: Text('${s.name} · ${s.items.length} dań', style: text.bodyMedium)),
                        ],
                      ),
                    ),
              ],
              if (e.createdByName != null) ...[
                const SizedBox(height: 16),
                Text('Dodał(a): ${e.createdByName}', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ],
          ),
        ),
        if (on)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                TextButton(onPressed: widget.onClose, child: const Text('Anuluj')),
                const Spacer(),
                FilledButton(onPressed: _busy ? null : _save, child: Text(e.id == null ? 'Dodaj' : 'Zapisz')),
              ],
            ),
          ),
      ],
    );
  }
}
