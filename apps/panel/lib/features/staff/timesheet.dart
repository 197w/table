import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];
const _weekdayShort = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';

/// Czas trwania jako „7:45”.
String hoursText(Duration d) {
  final minutes = d.inMinutes;
  return '${minutes ~/ 60}:${_two(minutes % 60)}';
}

/// Czas pracy w tygodniu: kto jest teraz w pracy, godziny każdego dnia i lista zmian.
/// Zmiany zaczynają się skanem kodu QR w aplikacji Table for workers, kierownik może je poprawić.
class Timesheet extends ConsumerWidget {
  const Timesheet({
    super.key,
    required this.restaurantId,
    required this.week,
    required this.members,
    required this.canEdit,
  });

  final String restaurantId;
  final DateTime week;
  final List<StaffMember> members;
  final bool canEdit;

  Future<void> _edit(BuildContext context, WidgetRef ref, [StaffShift? shift]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ShiftDialog(members: members, week: week, shift: shift),
    );
    if (saved == true && context.mounted) showMessage(context, 'Zmiana zapisana.');
  }

  Future<void> _end(BuildContext context, WidgetRef ref, StaffMember member) async {
    final ok = await confirm(
      context,
      title: 'Zakończyć zmianę?',
      message: '${member.name} kończy pracę teraz.',
      action: 'Zakończ zmianę',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).endShift(member.id);
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, StaffShift shift, String name) async {
    final ok = await confirm(
      context,
      title: 'Usunąć zmianę?',
      message: '$name, ${Fmt.dayShort(shift.startedAt)} ${_hm(shift.startedAt)}. Godziny znikną z podsumowania.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteShift(shift.id);
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final to = week.add(const Duration(days: 7));
    final async = ref.watch(shiftsProvider((restaurantId: restaurantId, from: week, to: to)));
    final byId = {for (final m in members) m.id: m};

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(shiftsProvider((restaurantId: restaurantId, from: week, to: to))),
      ),
      data: (all) {
        final shifts = all.where((s) => s.startedAt.isBefore(to) && !s.startedAt.isBefore(week) || s.isOpen).toList();
        final open = all.where((s) => s.isOpen).toList();

        // Godziny pracownika w danym dniu tygodnia (zmiana liczy się do dnia, w którym się zaczęła).
        Duration hours(String memberId, int day) {
          final start = DateTime(week.year, week.month, week.day + day);
          final end = DateTime(week.year, week.month, week.day + day + 1);
          return shifts
              .where((s) => s.memberId == memberId && !s.startedAt.isBefore(start) && s.startedAt.isBefore(end))
              .fold(Duration.zero, (sum, s) => sum + s.duration);
        }

        final rows = [
          for (final m in members)
            if (m.active || shifts.any((s) => s.memberId == m.id)) m,
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelCard(
                title: open.isEmpty ? 'Nikt nie jest teraz w pracy' : 'Teraz w pracy',
                icon: AppIcons.timer,
                iconColor: TileColors.green,
                trailing: canEdit
                    ? OutlinedButton.icon(
                        onPressed: () => _edit(context, ref),
                        icon: const Glyph(AppIcons.plus, size: 16),
                        label: const Text('Dopisz zmianę'),
                      )
                    : null,
                child: open.isEmpty
                    ? Text(
                        'Pracownik zaczyna zmianę, skanując kod z panelu (tryb obsługi) w aplikacji Table for workers.',
                        style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                      )
                    : Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final s in open)
                            if (byId[s.memberId] case final m?)
                              Container(
                                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceRaised,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.ringStrong),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF2FB673),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(m.name, style: text.labelLarge),
                                    const SizedBox(width: 8),
                                    Text(
                                      'od ${_hm(s.startedAt)} · ${hoursText(s.duration)} h',
                                      style: text.bodyMedium?.copyWith(
                                        color: AppColors.textMuted,
                                        fontFeatures: _tabular,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton(
                                      onPressed: () => _end(context, ref, m),
                                      child: const Text('Zakończ'),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Nagłówek tabeli: dni tygodnia i suma.
                    Container(
                      color: AppColors.surfaceRaised,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(width: 220, child: Text('Pracownik', style: text.labelLarge)),
                          for (var d = 0; d < 7; d++)
                            Expanded(
                              child: Text(
                                '${_weekdayShort[d]} ${DateTime(week.year, week.month, week.day + d).day}',
                                textAlign: TextAlign.center,
                                style: text.labelLarge?.copyWith(color: AppColors.textMuted),
                              ),
                            ),
                          SizedBox(
                            width: 90,
                            child: Text('Razem', textAlign: TextAlign.right, style: text.labelLarge),
                          ),
                        ],
                      ),
                    ),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Brak pracowników.', style: text.bodyMedium),
                      ),
                    for (final m in rows)
                      Container(
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.ring))),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 220,
                              child: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelLarge),
                            ),
                            for (var d = 0; d < 7; d++)
                              Expanded(
                                child: Text(
                                  hours(m.id, d) == Duration.zero ? '–' : hoursText(hours(m.id, d)),
                                  textAlign: TextAlign.center,
                                  style: text.bodyMedium?.copyWith(
                                    fontFeatures: _tabular,
                                    color: hours(m.id, d) == Duration.zero ? AppColors.textDisabled : null,
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: 90,
                              child: Text(
                                hoursText(List.generate(7, (d) => hours(m.id, d)).fold(Duration.zero, (a, b) => a + b)),
                                textAlign: TextAlign.right,
                                style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                title: 'Zmiany w tym tygodniu',
                icon: AppIcons.list,
                iconColor: TileColors.blue,
                child: shifts.isEmpty
                    ? Text(
                        'W tym tygodniu nikt jeszcze nie zaczął zmiany.',
                        style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                      )
                    : Column(
                        children: [
                          for (final s in shifts.reversed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 220,
                                    child: Text(byId[s.memberId]?.name ?? 'Były pracownik', style: text.labelLarge),
                                  ),
                                  SizedBox(
                                    width: 150,
                                    child: Text(Fmt.capitalize(Fmt.dayShort(s.startedAt)), style: text.bodyMedium),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${_hm(s.startedAt)} – ${s.endedAt == null ? 'trwa' : _hm(s.endedAt!)}'
                                      '  ·  ${hoursText(s.duration)} h'
                                      '${s.source == 'panel' ? '  ·  wpisana ręcznie' : ''}',
                                      style: text.bodyMedium?.copyWith(
                                        color: AppColors.textMuted,
                                        fontFeatures: _tabular,
                                      ),
                                    ),
                                  ),
                                  if (canEdit) ...[
                                    IconButton(
                                      tooltip: 'Popraw',
                                      icon: const Glyph(AppIcons.pencil, size: 16),
                                      onPressed: () => _edit(context, ref, s),
                                    ),
                                    IconButton(
                                      tooltip: 'Usuń',
                                      icon: Glyph(AppIcons.trash, size: 16, color: AppColors.error),
                                      onPressed: () => _delete(context, ref, s, byId[s.memberId]?.name ?? 'Pracownik'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Ręczne dopisanie albo poprawa zmiany, np. gdy pracownik zapomniał zeskanować kod.
class _ShiftDialog extends ConsumerStatefulWidget {
  const _ShiftDialog({required this.members, required this.week, this.shift});

  final List<StaffMember> members;
  final DateTime week;
  final StaffShift? shift;

  @override
  ConsumerState<_ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends ConsumerState<_ShiftDialog> {
  late String? _memberId = widget.shift?.memberId;
  late DateTime _day = dateOnly(widget.shift?.startedAt.toLocal() ?? DateTime.now());
  late TimeOfDay _start = TimeOfDay.fromDateTime(widget.shift?.startedAt.toLocal() ?? DateTime.now());
  late TimeOfDay? _end = widget.shift?.endedAt == null
      ? (widget.shift == null ? TimeOfDay.fromDateTime(DateTime.now()) : null)
      : TimeOfDay.fromDateTime(widget.shift!.endedAt!.toLocal());
  bool _busy = false;

  String _fmt(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  Future<void> _save() async {
    final member = _memberId;
    if (member == null) {
      showMessage(context, 'Wybierz pracownika.');
      return;
    }
    final started = DateTime(_day.year, _day.month, _day.day, _start.hour, _start.minute);
    DateTime? ended;
    final end = _end;
    if (end != null) {
      ended = DateTime(_day.year, _day.month, _day.day, end.hour, end.minute);
      // Zmiana po północy kończy się następnego dnia.
      if (!ended.isAfter(started)) ended = ended.add(const Duration(days: 1));
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveShift(
        id: widget.shift?.id,
        memberId: member,
        startedAt: started,
        endedAt: ended,
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
    return AlertDialog(
      title: Text(widget.shift == null ? 'Dopisz zmianę' : 'Popraw zmianę'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _memberId,
              decoration: const InputDecoration(labelText: 'Pracownik'),
              items: [
                for (final m in widget.members.where((m) => m.active || m.id == _memberId))
                  DropdownMenuItem(value: m.id, child: Text(m.name)),
              ],
              onChanged: widget.shift == null ? (v) => setState(() => _memberId = v) : null,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _day,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _day = dateOnly(picked));
              },
              icon: const Glyph(AppIcons.calendar, size: 16),
              label: Text(Fmt.capitalize(Fmt.dayLong(_day))),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await pickTime(context, initial: _start, minuteStep: 5);
                      if (t != null) setState(() => _start = t);
                    },
                    child: Text('Od ${_fmt(_start)}', style: const TextStyle(fontFeatures: _tabular)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await pickTime(context, initial: _end ?? _start, minuteStep: 5);
                      if (t != null) setState(() => _end = t);
                    },
                    child: Text(
                      _end == null ? 'Trwa' : 'Do ${_fmt(_end!)}',
                      style: const TextStyle(fontFeatures: _tabular),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Zmiana po północy kończy się następnego dnia.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Zapisz')),
      ],
    );
  }
}
