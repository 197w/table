import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';

const _tabular = [FontFeature.tabularFigures()];
const _weekdays = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];
const _months = [
  'Styczeń', 'Luty', 'Marzec', 'Kwiecień', 'Maj', 'Czerwiec',
  'Lipiec', 'Sierpień', 'Wrzesień', 'Październik', 'Listopad', 'Grudzień',
];
const _monthsShort = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];

/// Kolor zgłoszenia, które czeka na decyzję przełożonego.
const _pending = Color(0xFFE08A1E);

/// Kolor wolnego dnia (daje go przełożony w panelu).
const _off = Color(0xFF3B82F6);

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

  Future<void> _hours(List<Job> jobs, DateTime day, [PlannedShift? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => HoursSheet(jobs: jobs, day: day, existing: existing),
    );
    if (saved == true) {
      ref.invalidate(schedulePeriodProvider);
      if (mounted) showMessage(context, 'Zgłoszone. Przełożony przyjmie godziny, zmieni je albo odrzuci.');
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
      if (mounted) showMessage(context, errorText(e));
    }
  }

  Future<void> _open(List<Job> jobs, DateTime day, PlannedShift? entry) async {
    final today = _day(DateTime.now());
    if (entry == null) {
      if (!day.isBefore(today) && jobs.isNotEmpty) await _hours(jobs, day);
      return;
    }
    final editable = entry.pending && !day.isBefore(today);
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
                        _hours(jobs, day, entry);
                      }
                    : null,
                onDelete: editable
                    ? () {
                        Navigator.pop(context);
                        _delete(entry);
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
    final open = days.where((d) => !d.isBefore(today) && (byDay[d]?.pending ?? true)).toList();
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
          ..invalidate(schedulePeriodProvider)
          ..invalidate(shiftsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Poprzedni okres',
                  onPressed: () => setState(() => _offset--),
                  icon: const Glyph(AppIcons.caretLeft, size: 20),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(_periodLabel(kind, period), style: text.titleLarge?.copyWith(fontFeatures: _tabular)),
                      Text(
                        _offset == 0 ? 'Grafik na $unit · teraz' : 'Grafik na $unit',
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Następny okres',
                  onPressed: () => setState(() => _offset++),
                  icon: const Glyph(AppIcons.caretRight, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _Count(color: AppColors.accent, label: 'Przyjęte', count: accepted),
                _Count(color: _pending, label: 'Czeka', count: waiting),
                _Count(color: AppColors.error, label: 'Odrzucone', count: rejected),
                if (free > 0) _Count(color: _off, label: 'Wolne', count: free),
              ],
            ),
            if (open.isNotEmpty && jobs.isNotEmpty) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => _whole(jobs, open, byDay),
                icon: const Glyph(AppIcons.calendarPlus, size: 20),
                label: Text(submitLabel),
              ),
            ],
            const SizedBox(height: 14),
            if (async.isLoading && !async.hasValue)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else
              for (final d in days)
                _DayRow(
                  day: d,
                  today: today,
                  entry: byDay[d],
                  onTap: () => _open(jobs, d, byDay[d]),
                ),
            const SizedBox(height: 28),
            HoursHistory(shifts: shifts),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.color, required this.label, required this.count});

  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color, fontFeatures: _tabular),
      ),
    );
  }
}

/// Jeden dzień okresu: dzień tygodnia i data, godziny i stan zgłoszenia.
class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.today, required this.entry, required this.onTap});

  final DateTime day;
  final DateTime today;
  final PlannedShift? entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = entry;
    final past = day.isBefore(today);
    final isToday = day == today;
    final (Color color, String status) = switch (e) {
      null => (AppColors.textMuted, past ? 'Brak godzin' : 'Nie zgłoszono'),
      final e when e.accepted => (AppColors.accent, e.changed ? 'Przyjęte ze zmianą' : 'Przyjęte'),
      final e when e.rejected => (AppColors.error, 'Odrzucone'),
      final e when e.off => (_off, 'Wolne'),
      _ => (_pending, 'Czeka na decyzję'),
    };
    return Opacity(
      opacity: past ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isToday ? AppColors.accent : AppColors.ring, width: isToday ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Column(
                      children: [
                        Text(
                          _weekdays[day.weekday - 1],
                          style: text.labelMedium?.copyWith(color: isToday ? AppColors.accent : AppColors.textMuted),
                        ),
                        Text(
                          '${day.day}',
                          style: text.titleLarge?.copyWith(fontFeatures: _tabular, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 4,
                    height: 34,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: e == null ? AppColors.ring : color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (e != null && !e.off)
                          Text(
                            '${e.starts}–${e.ends}',
                            style: text.titleMedium?.copyWith(
                              fontFeatures: _tabular,
                              decoration: e.rejected ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        Text(status, style: text.bodySmall?.copyWith(color: color)),
                        if (e?.answer != null)
                          Text(
                            'Przełożony: ${e!.answer}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                      ],
                    ),
                  ),
                  if (!past) Glyph(AppIcons.caretRight, size: 16, color: AppColors.textDisabled),
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
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _starts[day]! : _ends[day]!,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
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
      if (mounted) showMessage(context, done == 0 ? errorText(e) : 'Zapisano $done dni. ${errorText(e)}');
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

/// Moje przepracowane zmiany z ostatniego miesiąca, dzień po dniu, z sumą.
class HoursHistory extends StatelessWidget {
  const HoursHistory({super.key, required this.shifts});

  final List<Shift> shifts;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = shifts.fold(Duration.zero, (sum, s) => sum + s.duration);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Moje godziny', style: text.titleMedium)),
            Text(
              '31 dni: ${_hoursText(total)} h',
              style: text.titleSmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (shifts.isEmpty)
          Text('Tu pojawią się Twoje zmiany.', style: text.bodyMedium?.copyWith(color: AppColors.textMuted))
        else
          for (final s in shifts)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.ring))),
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
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onEdit, required this.onDelete});

  final PlannedShift entry;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

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
        : (_pending, AppIcons.clock, 'Czeka na decyzję przełożonego');
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
              e.off ? 'Masz wolne' : '${e.starts}–${e.ends}',
              style: text.headlineSmall?.copyWith(
                fontFeatures: _tabular,
                decoration: e.rejected ? TextDecoration.lineThrough : null,
              ),
            ),
            Text(e.restaurantName, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
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
            if (onEdit != null || onDelete != null) ...[
              const SizedBox(height: 12),
              // Przyciski w motywie Table zajmują całą szerokość, więc w wierszu dostają Expanded.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: onEdit,
                      child: const Text('Zmień'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: AppColors.error),
                      onPressed: onDelete,
                      child: const Text('Wycofaj'),
                    ),
                  ),
                ],
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
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _starts : _ends,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
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
      if (mounted) showMessage(context, errorText(e));
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
          ],
        ),
      ),
    );
  }
}
