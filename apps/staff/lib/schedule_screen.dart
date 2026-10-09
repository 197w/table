import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'ui.dart';

const _tabular = [FontFeature.tabularFigures()];
const _weekdays = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];
const _months = [
  'Styczeń', 'Luty', 'Marzec', 'Kwiecień', 'Maj', 'Czerwiec',
  'Lipiec', 'Sierpień', 'Wrzesień', 'Październik', 'Listopad', 'Grudzień',
];
const _monthsShort = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];

/// Kolor zgłoszenia, które czeka na decyzję przełożonego (czytelny w obu motywach).
Color get _pending => StaffColors.pending;

/// Kolor wolnego dnia (daje go przełożony w panelu).
Color get _off => StaffColors.info;

/// Kolor propozycji przełożonego, na którą czeka moja odpowiedź.
Color get _proposed => StaffColors.proposal;

/// Stan dnia w grafiku: słowo, ikona i kolor (nie sam kolor).
({String label, AppIconData icon, Color color}) _dayStatus(PlannedShift? e, {required bool past, required bool closed}) =>
    switch (e) {
      null when past => (label: 'Brak godzin', icon: AppIcons.minus, color: AppColors.textMuted),
      null when closed => (label: 'Niedostępny', icon: AppIcons.lock, color: AppColors.textMuted),
      null => (label: 'Nie zgłoszono', icon: AppIcons.calendarPlus, color: AppColors.textMuted),
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

/// Czas trwania jako „7:45”.
String _hoursText(Duration d) => '${d.inMinutes ~/ 60}:${_two(d.inMinutes % 60)}';

/// Okres grafiku lokalu (tydzień, 2 tygodnie, miesiąc), przesunięty o [offset] okresów od dziś.
({DateTime from, DateTime to}) periodFor(String kind, int offset) {
  final today = _day(DateTime.now());
  final monday = today.subtract(Duration(days: today.weekday - 1));
  switch (kind) {
    case 'month':
      final from = DateTime(today.year, today.month + offset);
      return (from: from, to: DateTime(from.year, from.month + 1, 0));
    case 'two_weeks':
      // Pary tygodni liczone od stałego poniedziałku, żeby okres był ten sam dla całego lokalu.
      // Dni liczone w UTC, bo przejście na czas letni skraca lokalną różnicę o godzinę.
      final anchor = DateTime(2026, 1, 5);
      final days = DateTime.utc(monday.year, monday.month, monday.day).difference(DateTime.utc(2026, 1, 5)).inDays;
      final index = (days / 14).floor() + offset;
      final from = DateTime(anchor.year, anchor.month, anchor.day + index * 14);
      return (from: from, to: DateTime(from.year, from.month, from.day + 13));
    default:
      final from = DateTime(monday.year, monday.month, monday.day + offset * 7);
      return (from: from, to: DateTime(from.year, from.month, from.day + 6));
  }
}

String _periodLabel(String kind, ({DateTime from, DateTime to}) p) {
  if (kind == 'month') return '${_months[p.from.month - 1]} ${p.from.year}';
  final sameMonth = p.from.month == p.to.month;
  return sameMonth
      ? '${p.from.day}–${p.to.day} ${_monthsShort[p.to.month - 1]}'
      : '${p.from.day} ${_monthsShort[p.from.month - 1]} – ${p.to.day} ${_monthsShort[p.to.month - 1]}';
}

/// Grafik jako czytelna lista dni z okresu, który ustawił lokal (tydzień, 2 tygodnie albo miesiąc).
/// Przy każdym dniu widać, czy godziny są przyjęte, czekają na decyzję albo zostały odrzucone.
/// Godziny można zgłosić na cały okres naraz. Na dole moje przepracowane godziny.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    // Okres grafiku (tydzień, 2 tygodnie, miesiąc) mógł się zmienić w panelu: pobieramy go od nowa.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(jobsProvider);
    });
  }

  Future<void> _hours(List<Job> jobs, DateTime day, [PlannedShift? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
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
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
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
          accept ? 'Przyjęte: ${entry.starts}–${entry.ends}. Dzień jest w Twoim grafiku.' : 'Przełożony zobaczy, że nie możesz.',
          tone: accept ? ToastTone.success : ToastTone.info,
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Uwaga na tydzień dla przełożonego (np. „w środę egzamin”).
  Future<void> _weekNote(List<Job> jobs, DateTime week, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Uwaga na tydzień ${week.day}.${_two(week.month)}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Na przykład: w środę mam egzamin'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || jobs.isEmpty) return;
    try {
      await ref.read(staffRepositoryProvider).setWeekNote(jobs.first.memberId, week, note);
      ref.invalidate(weekNotesProvider);
      if (mounted) showMessage(context, note.isEmpty ? 'Uwaga usunięta.' : 'Uwaga zapisana. Przełożony zobaczy ją w grafiku.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _open(List<Job> jobs, DateTime day, PlannedShift? entry, {required bool closed}) async {
    final today = _day(DateTime.now());
    if (entry == null) {
      if (day.isBefore(today) || jobs.isEmpty) return;
      if (closed) {
        showMessage(context, 'Termin zgłaszania na ten okres minął. Jesteś niedostępny. Zapytaj przełożonego.');
        return;
      }
      await _hours(jobs, day);
      return;
    }
    final editable = (entry.pending || entry.unavailable) && !day.isBefore(today) && !closed;
    final answerable = entry.proposed && !day.isBefore(today);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
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
                onDelete: editable
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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final jobs = ref.watch(jobsProvider).value ?? const <Job>[];
    final kind = jobs.isEmpty ? 'week' : jobs.first.schedulePeriod;
    final period = periodFor(kind, _offset);
    final async = ref.watch(schedulePeriodProvider(period));
    final byDay = {for (final e in async.value ?? const <PlannedShift>[]) _day(e.day): e};
    final days = [
      for (var d = period.from; !d.isAfter(period.to); d = DateTime(d.year, d.month, d.day + 1)) d,
    ];
    final today = _day(DateTime.now());
    // Termin zgłaszania dyspozycyjności na ten okres: po nim wpisywanie się wyłącza.
    final deadline = jobs.isEmpty
        ? null
        : ref.watch(scheduleDeadlineProvider((memberId: jobs.first.memberId, day: period.from))).value;
    final closed = deadline != null && DateTime.now().isAfter(deadline);
    // Uwagi na tygodnie okresu (poniedziałki).
    final firstMonday = period.from.subtract(Duration(days: period.from.weekday - 1));
    final notes = ref.watch(weekNotesProvider((from: firstMonday, to: period.to))).value ?? const <DateTime, String>{};
    final open = closed
        ? const <DateTime>[]
        : days.where((d) => !d.isBefore(today) && (byDay[d] == null || byDay[d]!.pending || byDay[d]!.unavailable)).toList();
    final proposals = byDay.values.where((e) => e.proposed).length;
    final accepted = byDay.values.where((e) => e.accepted).length;
    final waiting = byDay.values.where((e) => e.pending).length;
    final rejected = byDay.values.where((e) => e.rejected).length;
    final free = byDay.values.where((e) => e.off).length;
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final (unit, submitLabel) = switch (kind) {
      'month' => ('miesiąc', 'Zgłoś godziny na ten miesiąc'),
      'two_weeks' => ('2 tygodnie', 'Zgłoś godziny na te 2 tygodnie'),
      _ => ('tydzień', 'Zgłoś godziny na ten tydzień'),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Grafik')),
      body: RefreshIndicator(
        onRefresh: () async => ref
          ..invalidate(jobsProvider)
          ..invalidate(schedulePeriodProvider)
          ..invalidate(shiftsProvider),
        child: ContentWidth(
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            // Okres w pigułce ze strzałkami. Stuknięcie w napis wraca do bieżącego okresu.
            _PeriodSwitcher(
              label: _periodLabel(kind, period),
              caption: _offset == 0 ? 'Grafik na $unit · teraz' : 'Grafik na $unit',
              onPrevious: () => setState(() => _offset--),
              onNext: () => setState(() => _offset++),
              onToday: _offset == 0 ? null : () => setState(() => _offset = 0),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusChip(label: 'Przyjęte: $accepted', icon: AppIcons.checkCircle, color: AppColors.accent),
                StatusChip(label: 'Czeka: $waiting', icon: AppIcons.hourglass, color: _pending),
                if (rejected > 0)
                  StatusChip(label: 'Odrzucone: $rejected', icon: AppIcons.prohibit, color: AppColors.error),
                if (free > 0) StatusChip(label: 'Wolne: $free', icon: AppIcons.sun, color: _off),
                if (proposals > 0)
                  StatusChip(label: 'Propozycje: $proposals', icon: AppIcons.send, color: _proposed),
              ],
            ),
            if (deadline != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Glyph(
                      closed ? AppIcons.lock : AppIcons.alarm,
                      size: 16,
                      color: closed ? AppColors.textMuted : _pending,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      closed
                          ? 'Termin zgłaszania minął (${_deadlineText(deadline)}). Dni bez zgłoszenia: niedostępny.'
                          : 'Zgłoś dyspozycyjność do ${_deadlineText(deadline)}.',
                      style: text.bodyMedium?.copyWith(color: closed ? AppColors.textMuted : _pending),
                    ),
                  ),
                ],
              ),
            ],
            if (open.isNotEmpty && jobs.isNotEmpty) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => _whole(jobs, open, byDay),
                icon: const Glyph(AppIcons.calendarPlus, size: 20),
                label: Text(submitLabel),
              ),
            ],
            const SizedBox(height: 8),
            if (async.isLoading && !async.hasValue)
              const _DaysSkeleton()
            else
              for (final d in days) ...[
                // Na początku tygodnia: moja uwaga na ten tydzień dla przełożonego.
                if (d == period.from || d.weekday == DateTime.monday)
                  _WeekNoteRow(
                    week: d.subtract(Duration(days: d.weekday - 1)),
                    note: notes[d.subtract(Duration(days: d.weekday - 1))],
                    onTap: jobs.isEmpty
                        ? null
                        : () => _weekNote(jobs, d.subtract(Duration(days: d.weekday - 1)), notes[d.subtract(Duration(days: d.weekday - 1))]),
                  ),
                _DayRow(
                  day: d,
                  today: today,
                  entry: byDay[d],
                  closed: closed,
                  onTap: () => _open(jobs, d, byDay[d], closed: closed),
                ),
              ],
            const SizedBox(height: 12),
            HoursHistory(shifts: shifts),
          ],
          ),
        ),
      ),
    );
  }
}

/// Okres grafiku w pigułce: strzałki po bokach (48 dp), napis w środku wraca do bieżącego okresu.
class _PeriodSwitcher extends StatelessWidget {
  const _PeriodSwitcher({
    required this.label,
    required this.caption,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final String label;
  final String caption;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Null: już bieżący okres.
  final VoidCallback? onToday;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ring),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Poprzedni okres',
            onPressed: onPrevious,
            icon: const Glyph(AppIcons.caretLeft, size: 20),
          ),
          Expanded(
            child: Semantics(
              button: onToday != null,
              hint: onToday == null ? null : 'Wróć do bieżącego okresu',
              child: InkWell(
                onTap: onToday,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: text.titleLarge?.copyWith(fontFeatures: _tabular),
                      ),
                      Text(
                        onToday == null ? caption : '$caption · wróć do teraz',
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(color: onToday == null ? AppColors.textMuted : AppColors.accent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Następny okres',
            onPressed: onNext,
            icon: const Glyph(AppIcons.caretRight, size: 20),
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

/// Jeden dzień okresu: kafelek z dniem, godziny i stan zgłoszenia słowem z ikoną.
/// Minione dni są przygaszone kolorem tekstu, nie przezroczystością (kontrast zostaje czytelny).
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.today,
    required this.entry,
    required this.onTap,
    this.closed = false,
  });

  final DateTime day;
  final DateTime today;
  final PlannedShift? entry;
  final VoidCallback onTap;

  /// Termin zgłaszania minął: dzień bez zgłoszenia to „Niedostępny”.
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = entry;
    final past = day.isBefore(today);
    final isToday = day == today;
    final status = _dayStatus(e, past: past, closed: closed);
    final hours = e != null && !e.off && !e.unavailable
        ? '${e.starts}–${e.ends}${e.positionName == null ? '' : ' · ${e.positionName}'}'
        : null;
    final tappable = !past || e != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: tappable,
        label: [
          Fmt.capitalize(Fmt.dayLong(day)),
          if (isToday) 'dziś',
          ?hours,
          status.label,
          if (e?.answer != null) 'przełożony: ${e!.answer}',
        ].join(', '),
        excludeSemantics: true,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isToday ? AppColors.accent : AppColors.ring, width: isToday ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  // Kafelek dnia: dzień tygodnia i numer, dziś w kolorze akcentu.
                  Container(
                    width: 48,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isToday ? AppColors.accentTint : AppColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _weekdays[day.weekday - 1],
                          style: text.labelMedium?.copyWith(color: isToday ? AppColors.accent : AppColors.textMuted),
                        ),
                        Text(
                          '${day.day}',
                          style: text.titleLarge?.copyWith(
                            fontFeatures: _tabular,
                            fontWeight: FontWeight.w600,
                            color: past ? AppColors.textMuted : AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hours != null) ...[
                          Text(
                            hours,
                            style: text.titleMedium?.copyWith(
                              fontFeatures: _tabular,
                              color: past || e!.rejected ? AppColors.textMuted : AppColors.text,
                              decoration: e!.rejected ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        StatusChip(label: status.label, icon: status.icon, color: status.color),
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
                  if (tappable) Glyph(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Szkielet listy dni, zanim grafik dojdzie.
class _DaysSkeleton extends StatelessWidget {
  const _DaysSkeleton();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              height: 64,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.ring),
              ),
              child: const Row(
                children: [
                  SkeletonBox(width: 48, height: 44, radius: 12),
                  SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [SkeletonBox(width: 110, height: 14), SizedBox(height: 8), SkeletonBox(width: 80, height: 12)],
                  ),
                ],
              ),
            ),
        ],
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
  late final Map<DateTime, bool> _on = {for (final d in widget.days) d: widget.existing[d] != null};
  late final Map<DateTime, TimeOfDay> _starts = {
    for (final d in widget.days) d: _parse(widget.existing[d]?.starts ?? '10:00'),
  };
  late final Map<DateTime, TimeOfDay> _ends = {
    for (final d in widget.days) d: _parse(widget.existing[d]?.ends ?? '18:00'),
  };
  late String _memberId = widget.jobs.first.memberId;
  bool _busy = false;

  static TimeOfDay _parse(String hm) {
    final p = hm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static String _fmt(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

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
      if (e.hour * 60 + e.minute <= s.hour * 60 + s.minute) {
        showMessage(context, '${Fmt.capitalize(Fmt.dayShort(d))}: koniec musi być później niż początek.');
        return;
      }
    }
    // Wyłączony dzień ze zgłoszeniem wycofuje je. Niezmienionych dni nie wysyłamy drugi raz.
    final withdrawn = [
      for (final d in widget.days)
        if (!(_on[d] ?? false) && widget.existing[d] != null) widget.existing[d]!,
    ];
    final changed = [
      for (final d in chosen)
        if (widget.existing[d] == null ||
            widget.existing[d]!.starts != _fmt(_starts[d]!) ||
            widget.existing[d]!.ends != _fmt(_ends[d]!))
          d,
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
                          child: Text(_fmt(_ends[d]!), style: const TextStyle(fontFeatures: _tabular, fontSize: 16)),
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

/// Moje przepracowane zmiany w miesiącu kalendarzowym (od 1. do ostatniego dnia), dzień po dniu, z sumą.
/// Strzałki przełączają miesiące, najdalej trzy wstecz.
class HoursHistory extends StatefulWidget {
  const HoursHistory({super.key, required this.shifts});

  final List<Shift> shifts;

  @override
  State<HoursHistory> createState() => _HoursHistoryState();
}

class _HoursHistoryState extends State<HoursHistory> {
  /// Ile miesięcy wstecz od bieżącego (0: ten miesiąc).
  int _back = 0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final month = DateTime(now.year, now.month - _back);
    final next = DateTime(month.year, month.month + 1);
    final shifts = [
      for (final s in widget.shifts)
        if (!s.startedAt.toLocal().isBefore(month) && s.startedAt.toLocal().isBefore(next)) s,
    ];
    final total = shifts.fold(Duration.zero, (sum, s) => sum + s.duration);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Moje godziny',
          trailing: Semantics(
            label: 'Razem ${hoursSpoken(total)}',
            excludeSemantics: true,
            child: Text('${_hoursText(total)} h', style: text.titleLarge?.copyWith(fontFeatures: _tabular)),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Poprzedni miesiąc',
              onPressed: _back < 3 ? () => setState(() => _back++) : null,
              icon: const Glyph(AppIcons.caretLeft, size: 18),
            ),
            Expanded(
              child: Text(
                '${_months[month.month - 1]} ${month.year}',
                textAlign: TextAlign.center,
                style: text.titleSmall,
              ),
            ),
            IconButton(
              tooltip: 'Następny miesiąc',
              onPressed: _back > 0 ? () => setState(() => _back--) : null,
              icon: const Glyph(AppIcons.caretRight, size: 18),
            ),
          ],
        ),
        if (shifts.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Text('Brak zmian w tym miesiącu.', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
          )
        else
          for (final s in shifts)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.ring))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(Fmt.capitalize(Fmt.dayShort(s.startedAt)), style: text.bodyLarge),
                        Text(
                          '${s.restaurantName} · ${_hm(s.startedAt)}–${s.endedAt == null ? 'trwa' : _hm(s.endedAt!)}',
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                      ],
                    ),
                  ),
                  Text('${_hoursText(s.duration)} h', style: text.titleSmall?.copyWith(fontFeatures: _tabular)),
                ],
              ),
            ),
              ],
            ),
          ),
        ),
      ],
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
              Text('Ten dzień już minął.', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
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
    if (_ends.hour * 60 + _ends.minute <= _starts.hour * 60 + _starts.minute) {
      showMessage(context, 'Koniec musi być później niż początek.');
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
