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

/// Kolor zgłoszenia, które czeka na decyzję przełożonego.
const _pending = Color(0xFFE08A1E);

String _two(int n) => n.toString().padLeft(2, '0');
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Grafik jako zwykły kalendarz miesięczny. Kolor dnia mówi, co z moimi godzinami:
/// zielony przyjęte, pomarańczowy czeka na przełożonego, czerwony odrzucone.
/// Stuknięcie dnia pokazuje szczegóły i pozwala zgłosić godziny.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = _day(DateTime.now());

  void _shift(int months) => setState(() {
    _month = DateTime(_month.year, _month.month + months);
    _selected = _month.year == DateTime.now().year && _month.month == DateTime.now().month
        ? _day(DateTime.now())
        : _month;
  });

  Future<void> _hours(List<Job> jobs, DateTime day, [PlannedShift? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => HoursSheet(jobs: jobs, day: day, existing: existing),
    );
    if (saved == true) {
      ref.invalidate(scheduleMonthProvider);
      if (mounted) showMessage(context, 'Zgłoszone. Przełożony przyjmie godziny, zmieni je albo odrzuci.');
    }
  }

  Future<void> _delete(PlannedShift shift) async {
    try {
      await ref.read(staffRepositoryProvider).deleteHours(shift.id);
      ref.invalidate(scheduleMonthProvider);
      if (mounted) showMessage(context, 'Zgłoszenie wycofane.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final jobs = ref.watch(jobsProvider).value ?? const <Job>[];
    final async = ref.watch(scheduleMonthProvider(_month));
    final entries = async.value ?? const <PlannedShift>[];
    final byDay = <DateTime, List<PlannedShift>>{};
    for (final e in entries) {
      byDay.putIfAbsent(_day(e.day), () => []).add(e);
    }
    final today = _day(DateTime.now());

    // Siatka od poniedziałku tygodnia, w którym zaczyna się miesiąc.
    final first = DateTime(_month.year, _month.month);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final rows = ((first.weekday - 1 + daysInMonth) / 7).ceil();
    final selectedEntries = byDay[_selected] ?? const <PlannedShift>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Grafik')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(scheduleMonthProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Poprzedni miesiąc',
                  onPressed: () => _shift(-1),
                  icon: const Glyph(AppIcons.caretLeft, size: 20),
                ),
                Expanded(
                  child: Text(
                    '${_months[_month.month - 1]} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: text.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Następny miesiąc',
                  onPressed: () => _shift(1),
                  icon: const Glyph(AppIcons.caretRight, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final d in _weekdays)
                  Expanded(
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: text.labelMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (var r = 0; r < rows; r++)
              Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(
                      child: _DayCell(
                        day: start.add(Duration(days: r * 7 + c)),
                        inMonth: start.add(Duration(days: r * 7 + c)).month == _month.month,
                        today: today,
                        selected: _selected,
                        entry: byDay[_day(start.add(Duration(days: r * 7 + c)))]?.first,
                        onTap: (d) => setState(() => _selected = d),
                      ),
                    ),
                ],
              ),
            if (async.isLoading && !async.hasValue)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            const SizedBox(height: 10),
            const _Legend(),
            const SizedBox(height: 20),
            Text(Fmt.capitalize(Fmt.dayLong(_selected)), style: text.titleMedium),
            const SizedBox(height: 8),
            if (selectedEntries.isEmpty) ...[
              Text(
                _selected.isBefore(today) ? 'Brak godzin w tym dniu.' : 'Nie zgłosiłeś godzin na ten dzień.',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
              if (!_selected.isBefore(today) && jobs.isNotEmpty) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _hours(jobs, _selected),
                  icon: const Glyph(AppIcons.calendarPlus, size: 20),
                  label: const Text('Zgłoś godziny'),
                ),
              ],
            ] else
              for (final e in selectedEntries)
                _EntryCard(
                  entry: e,
                  onEdit: e.pending && !_selected.isBefore(today) ? () => _hours(jobs, _selected, e) : null,
                  onDelete: e.pending && !_selected.isBefore(today) ? () => _delete(e) : null,
                ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.selected,
    required this.entry,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final DateTime today;
  final DateTime selected;
  final PlannedShift? entry;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = entry;
    final isSelected = day == selected;
    final isToday = day == today;
    final (Color? fill, Color? border, Color label) = switch (e) {
      null => (null, null, AppColors.text),
      final e when e.accepted => (AppColors.accentFill, null, AppColors.onAccent),
      final e when e.rejected => (null, AppColors.error, AppColors.error),
      _ => (_pending.withValues(alpha: 0.18), _pending, AppColors.text),
    };
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onTap(day),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: AppColors.text, width: 2)
                  : border != null
                  ? Border.all(color: border)
                  : isToday
                  ? Border.all(color: AppColors.accent)
                  : null,
            ),
            child: Opacity(
              opacity: inMonth ? 1 : 0.35,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: text.titleSmall?.copyWith(
                      color: label,
                      fontWeight: isToday ? FontWeight.w600 : null,
                      fontFeatures: _tabular,
                    ),
                  ),
                  if (e != null)
                    Text(
                      e.starts,
                      style: text.labelSmall?.copyWith(
                        color: label,
                        fontFeatures: _tabular,
                        decoration: e.rejected ? TextDecoration.lineThrough : null,
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

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    Widget item(Color color, String label, {bool outline = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: outline ? null : color,
            borderRadius: BorderRadius.circular(4),
            border: outline ? Border.all(color: color, width: 1.5) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: style),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        item(AppColors.accentFill, 'Przyjęte'),
        item(_pending, 'Czeka na decyzję', outline: true),
        item(AppColors.error, 'Odrzucone', outline: true),
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
              '${e.starts}–${e.ends}',
              style: text.headlineSmall?.copyWith(
                fontFeatures: _tabular,
                decoration: e.rejected ? TextDecoration.lineThrough : null,
              ),
            ),
            Text(e.restaurantName, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
            if (e.changed)
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
