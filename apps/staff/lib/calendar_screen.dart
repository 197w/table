import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'ui.dart';

// Wydarzenia z Kalendarza lokalu w Table for employees (0080): wydarzenia specjalne lokalu i te dla pracowników
// (spotkania, szkolenia) ze wszystkich lokali pracownika. Zakładka „Kalendarz” (dawniej Grafik, [ScheduleScreen])
// pokazuje je pod siatką miesiąca razem z grafikiem; osoba z uprawnieniem „Kalendarz” dodaje nowe przyciskiem „+”.

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
const _colors = {
  'green': Color(0xFF2FB673),
  'blue': Color(0xFF3B82F6),
  'violet': Color(0xFF7C5CFF),
  'amber': Color(0xFFD99A15),
  'rose': Color(0xFFE5484D),
  'teal': Color(0xFF14A3A8),
  'gray': Color(0xFF8A8F98),
};

/// Kolor wydarzenia z panelu (green, blue, violet, amber, rose, teal, gray).
Color eventColor(StaffEvent e) => _colors[e.color] ?? AppColors.accent;

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Wydarzenie z Kalendarza lokalu.
class StaffEvent {
  const StaffEvent({
    required this.id,
    required this.restaurantId,
    required this.special,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.description,
    this.allDay = false,
    this.color = 'green',
  });

  final String id;
  final String restaurantId;

  /// Wydarzenie specjalne (widzą goście); inaczej tylko dla pracowników.
  final bool special;
  final String title;
  final String? description;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final String color;

  bool overlaps(DateTime from, DateTime to) => startsAt.isBefore(to) && endsAt.isAfter(from);

  factory StaffEvent.fromJson(Map<String, dynamic> j) => StaffEvent(
    id: j['id'] as String,
    restaurantId: j['restaurant_id'] as String,
    special: j['kind'] != 'staff',
    title: j['title'] as String? ?? '',
    description: (j['description'] as String?)?.trim().isEmpty ?? true ? null : (j['description'] as String).trim(),
    startsAt: DateTime.parse(j['starts_at'] as String).toLocal(),
    endsAt: DateTime.parse(j['ends_at'] as String).toLocal(),
    allDay: j['all_day'] == true,
    color: j['color'] as String? ?? 'green',
  );
}

/// Wydarzenia lokali pracownika w zakresie dat (lokale po przecinku, żeby klucz rodziny był porównywalny).
typedef StaffCalendarQuery = ({String restaurants, DateTime from, DateTime to});

final staffCalendarProvider = FutureProvider.autoDispose.family<List<StaffEvent>, StaffCalendarQuery>((ref, q) async {
  if (q.restaurants.isEmpty) return const [];
  final rows = await Supabase.instance.client
      .from('calendar_events')
      .select('id, restaurant_id, kind, title, description, starts_at, ends_at, all_day, color')
      .inFilter('restaurant_id', q.restaurants.split(','))
      .lt('starts_at', q.to.toUtc().toIso8601String())
      .gt('ends_at', q.from.toUtc().toIso8601String())
      .order('starts_at');
  return [for (final r in rows) StaffEvent.fromJson(r)];
});

/// Wydarzenie dnia jak na liście w Apple Calendar: godziny po lewej, kolorowa kreska, nazwa i opis.
class CalendarEventTile extends StatelessWidget {
  const CalendarEventTile({super.key, required this.event, required this.day, required this.restaurant});

  final StaffEvent event;
  final DateTime day;
  final String? restaurant;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = event;
    final dayEnd = day.add(const Duration(days: 1));
    final wholeDay = e.allDay || (!e.startsAt.isAfter(day) && !e.endsAt.isBefore(dayEnd));
    final color = eventColor(e);
    final kind = e.special ? 'Wydarzenie specjalne' : 'Dla pracowników';
    return Semantics(
      label:
          '${e.title}, ${wholeDay ? 'cały dzień' : '${hm(e.startsAt)} do ${hm(e.endsAt)}'}, $kind'
          '${restaurant == null ? '' : ', $restaurant'}${e.description == null ? '' : '. ${e.description}'}',
      excludeSemantics: true,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 52,
                  child: wholeDay
                      ? Text('cały\ndzień', style: text.labelMedium?.copyWith(color: AppColors.textMuted))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(hm(e.startsAt), style: text.labelLarge),
                            Text(hm(e.endsAt), style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
                          ],
                        ),
                ),
                Container(
                  width: 4,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title, style: text.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        [kind, ?restaurant].join(' · '),
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                      if (e.description != null) ...[
                        const SizedBox(height: 6),
                        Text(e.description!, style: text.bodyMedium),
                      ],
                    ],
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

/// Nowe wydarzenie z telefonu (uprawnienie „Kalendarz”): nazwa, rodzaj, dzień, godziny albo cały dzień, opis.
class AddEventSheet extends ConsumerStatefulWidget {
  const AddEventSheet({super.key, required this.jobs, required this.day});

  final List<Job> jobs;
  final DateTime day;

  @override
  ConsumerState<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends ConsumerState<AddEventSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  late Job _job = widget.jobs.first;
  bool _special = false;
  bool _allDay = false;
  late DateTime _date = widget.day;
  TimeOfDay _from = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 11, minute: 0);
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = _day(picked));
  }

  Future<void> _pickTime({required bool from}) async {
    final picked = await showTimeWheel(context, initial: from ? _from : _to, minuteStep: 15, title: from ? 'Od' : 'Do');
    if (picked == null) return;
    setState(() => from ? _from = picked : _to = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showMessage(context, 'Wpisz nazwę wydarzenia.', tone: ToastTone.warning);
      return;
    }
    final start = _allDay ? _date : DateTime(_date.year, _date.month, _date.day, _from.hour, _from.minute);
    var end = _allDay
        ? _date.add(const Duration(days: 1))
        : DateTime(_date.year, _date.month, _date.day, _to.hour, _to.minute);
    // Koniec wcześniej niż początek: następny dzień (np. 20:00–02:00).
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'panel_save_calendar_event',
        params: {
          'p_restaurant_id': _job.restaurantId,
          'p_id': null,
          'p_kind': _special ? 'special' : 'staff',
          'p_title': title,
          'p_description': _description.text.trim(),
          'p_starts_at': start.toUtc().toIso8601String(),
          'p_ends_at': end.toUtc().toIso8601String(),
          'p_all_day': _allDay,
          'p_color': _special ? 'green' : 'blue',
          'p_member_id': _job.memberId,
        },
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      showMessage(context, 'Dodano: $title.', tone: ToastTone.success);
    } on PostgrestException catch (e) {
      if (mounted) showMessage(context, e.message, tone: ToastTone.error);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Klawiatura albo przyciski systemu Androida: okno kończy się nad tym, co jest wyżej (jak „Zgłoś godziny”).
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final system = MediaQuery.viewPaddingOf(context).bottom;
    Widget picker(String label, String value, VoidCallback onTap) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 6),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: onTap,
            child: Text(value, style: const TextStyle(fontSize: 17, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + (keyboard > system ? keyboard : system)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nowe wydarzenie', style: text.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nazwa', counterText: ''),
            ),
            const SizedBox(height: 12),
            if (widget.jobs.length > 1) ...[
              DropdownButtonFormField<Job>(
                initialValue: _job,
                decoration: const InputDecoration(labelText: 'Lokal'),
                items: [for (final j in widget.jobs) DropdownMenuItem(value: j, child: Text(j.restaurantName))],
                onChanged: (j) => setState(() => _job = j ?? _job),
              ),
              const SizedBox(height: 12),
            ],
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Dla pracowników')),
                ButtonSegment(value: true, label: Text('Specjalne')),
              ],
              selected: {_special},
              onSelectionChanged: (v) => setState(() => _special = v.first),
            ),
            const SizedBox(height: 6),
            Text(
              _special
                  ? 'Goście zobaczą je w aplikacji Table nad godzinami otwarcia.'
                  : 'Widzą je tylko pracownicy, np. spotkanie albo szkolenie.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cały dzień'),
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
            ),
            const SizedBox(height: 4),
            Row(
              children: [picker('Dzień', '${_date.day} ${_monthsGenitive[_date.month - 1]} ${_date.year}', _pickDate)],
            ),
            if (!_allDay) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  picker('Od', _from.format24(), () => _pickTime(from: true)),
                  const SizedBox(width: 12),
                  picker('Do', _to.format24(), () => _pickTime(from: false)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Opis (opcjonalnie)', counterText: ''),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : _save,
              child: const Text('Dodaj wydarzenie'),
            ),
          ],
        ),
      ),
    );
  }
}

extension on TimeOfDay {
  String format24() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
