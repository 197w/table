import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];
const _weekdayShort = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];

/// Kolor poprawionych zmian: żółty, jak zakreślacz.
const editedColor = Color(0xFFE0A21B);

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';

/// Czas trwania jako „7:45”.
String hoursText(Duration d) {
  final minutes = d.inMinutes;
  return '${minutes ~/ 60}:${_two(minutes % 60)}';
}

/// Różnica czasu ze znakiem, np. „+0:15” albo „−1:05”.
String diffText(Duration d) => '${d.isNegative ? '−' : '+'}${hoursText(d.abs())}';

/// Dopisanie albo poprawa zmiany. Zwraca true po zapisie.
Future<void> openShiftDialog(BuildContext context, List<StaffMember> members, {StaffShift? shift}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => ShiftDialog(members: members, shift: shift),
  );
  if (saved == true && context.mounted) showMessage(context, 'Zmiana zapisana.');
}

Future<void> _deleteShift(BuildContext context, WidgetRef ref, StaffShift shift, String name) async {
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
    if (context.mounted) showError(context, e);
  }
}

/// Kto jest teraz w pracy: zielona kropka, od kiedy i „Zakończ”.
class WorkingNow extends ConsumerWidget {
  const WorkingNow({super.key, required this.open, required this.members});

  final List<StaffShift> open;
  final List<StaffMember> members;

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
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final byId = {for (final m in members) m.id: m};
    return PanelCard(
      title: open.isEmpty ? 'Nikt nie jest teraz w pracy' : 'Teraz w pracy',
      icon: AppIcons.timer,
      iconColor: TileColors.green,
      child: open.isEmpty
          ? Text(
              'Zmianę zaczyna się w „Wejdź na zmianę”: kodem QR z aplikacji Table for employees albo kodem pracownika.',
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
                            decoration: const BoxDecoration(color: Color(0xFF2FB673), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Text(m.name, style: text.labelLarge),
                          const SizedBox(width: 8),
                          Text(
                            'od ${_hm(s.startedAt)} · ${hoursText(s.duration)} h',
                            style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                          ),
                          const SizedBox(width: 4),
                          TextButton(onPressed: () => _end(context, ref, m), child: const Text('Zakończ')),
                        ],
                      ),
                    ),
              ],
            ),
    );
  }
}

/// Jedna zmiana na liście: dzień, godziny, czas. Poprawiona jest żółta, z godzinami sprzed poprawki i różnicą.
class ShiftTile extends ConsumerWidget {
  const ShiftTile({super.key, required this.shift, required this.members, required this.canEdit, this.showName = true});

  final StaffShift shift;
  final List<StaffMember> members;
  final bool canEdit;
  final bool showName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final s = shift;
    final name = members.where((m) => m.id == s.memberId).firstOrNull?.name ?? 'Były pracownik';
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final diff = s.editDifference;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: s.isEdited ? editedColor.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: s.isEdited ? editedColor.withValues(alpha: 0.45) : Colors.transparent),
      ),
      child: Row(
        children: [
          if (showName)
            SizedBox(width: 200, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelLarge)),
          SizedBox(width: 130, child: Text(Fmt.capitalize(Fmt.dayShort(s.startedAt)), style: text.bodyMedium)),
          SizedBox(
            width: 130,
            child: Text(
              '${_hm(s.startedAt)} – ${s.endedAt == null ? 'trwa' : _hm(s.endedAt!)}',
              style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
            ),
          ),
          SizedBox(width: 70, child: Text('${hoursText(s.duration)} h', style: muted)),
          Expanded(
            child: s.isEdited
                ? Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'było ${_hm(s.originalStartedAt!)} – '
                              '${s.originalEndedAt == null ? 'trwa' : _hm(s.originalEndedAt!)}',
                        ),
                        if (diff != null && diff != Duration.zero)
                          TextSpan(
                            text: '  ${diffText(diff)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                    style: text.bodyMedium?.copyWith(color: editedColor, fontFeatures: _tabular),
                  )
                : Text(s.source == 'panel' ? 'wpisana ręcznie' : '', style: muted),
          ),
          if (canEdit) ...[
            IconButton(
              tooltip: 'Popraw',
              icon: const Glyph(AppIcons.pencil, size: 16),
              onPressed: () => openShiftDialog(context, members, shift: s),
            ),
            IconButton(
              tooltip: 'Usuń',
              icon: Glyph(AppIcons.trash, size: 16, color: AppColors.error),
              onPressed: () => _deleteShift(context, ref, s, name),
            ),
          ],
        ],
      ),
    );
  }
}

/// Czas pracy w tygodniu: kto jest teraz w pracy, godziny każdego dnia i lista zmian.
/// Dzień z poprawioną zmianą jest żółty.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final to = week.add(const Duration(days: 7));
    final query = (restaurantId: restaurantId, from: week, to: to);
    final async = ref.watch(shiftsProvider(query));

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(shiftsProvider(query))),
      data: (all) {
        final shifts = all.where((s) => s.startedAt.isBefore(to) && !s.startedAt.isBefore(week) || s.isOpen).toList();
        final open = all.where((s) => s.isOpen).toList();

        // Zmiany pracownika w danym dniu tygodnia (zmiana liczy się do dnia, w którym się zaczęła).
        List<StaffShift> dayShifts(String memberId, int day) {
          final start = DateTime(week.year, week.month, week.day + day);
          final end = DateTime(week.year, week.month, week.day + day + 1);
          return [
            for (final s in shifts)
              if (s.memberId == memberId && !s.startedAt.isBefore(start) && s.startedAt.isBefore(end)) s,
          ];
        }

        Duration sum(Iterable<StaffShift> list) => list.fold(Duration.zero, (a, s) => a + s.duration);

        final rows = [
          for (final m in members)
            if (m.active || shifts.any((s) => s.memberId == m.id)) m,
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorkingNow(open: open, members: members),
              const SizedBox(height: 16),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
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
                          SizedBox(width: 90, child: Text('Razem', textAlign: TextAlign.right, style: text.labelLarge)),
                        ],
                      ),
                    ),
                    if (rows.isEmpty)
                      Padding(padding: const EdgeInsets.all(24), child: Text('Brak pracowników.', style: text.bodyMedium)),
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
                                child: Builder(
                                  builder: (context) {
                                    final list = dayShifts(m.id, d);
                                    final hours = sum(list);
                                    final edited = list.any((s) => s.isEdited);
                                    return Text(
                                      hours == Duration.zero ? '–' : hoursText(hours),
                                      textAlign: TextAlign.center,
                                      style: text.bodyMedium?.copyWith(
                                        fontFeatures: _tabular,
                                        fontWeight: edited ? FontWeight.w600 : null,
                                        color: edited
                                            ? editedColor
                                            : hours == Duration.zero
                                            ? AppColors.textDisabled
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            SizedBox(
                              width: 90,
                              child: Text(
                                hoursText(sum(shifts.where((s) => s.memberId == m.id && !s.startedAt.isBefore(week)))),
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
                          for (final s in shifts.reversed) ShiftTile(shift: s, members: members, canEdit: canEdit),
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

/// Godziny w miesiącu: każdy pracownik z sumą godzin. Stuknięcie w osobę rozwija jej zmiany do poprawy.
class MonthHours extends ConsumerStatefulWidget {
  const MonthHours({
    super.key,
    required this.restaurantId,
    required this.month,
    required this.members,
    required this.canEdit,
  });

  final String restaurantId;

  /// Pierwszy dzień miesiąca.
  final DateTime month;
  final List<StaffMember> members;
  final bool canEdit;

  @override
  ConsumerState<MonthHours> createState() => _MonthHoursState();
}

class _MonthHoursState extends ConsumerState<MonthHours> {
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final from = DateTime(widget.month.year, widget.month.month);
    final to = DateTime(widget.month.year, widget.month.month + 1);
    final query = (restaurantId: widget.restaurantId, from: from, to: to);
    final async = ref.watch(shiftsProvider(query));

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(shiftsProvider(query))),
      data: (all) {
        final open = all.where((s) => s.isOpen).toList();
        final shifts = [for (final s in all) if (!s.startedAt.isBefore(from) && s.startedAt.isBefore(to)) s];
        Duration sum(Iterable<StaffShift> list) => list.fold(Duration.zero, (a, s) => a + s.duration);
        final rows = [
          for (final m in widget.members)
            if (m.active || shifts.any((s) => s.memberId == m.id)) m,
        ]..sort((a, b) => sum(shifts.where((s) => s.memberId == b.id)).compareTo(sum(shifts.where((s) => s.memberId == a.id))));
        final header = text.labelLarge?.copyWith(color: AppColors.textMuted);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (open.isNotEmpty) ...[
                WorkingNow(open: open, members: widget.members),
                const SizedBox(height: 16),
              ],
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: AppColors.surfaceRaised,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(child: Text('Pracownik', style: text.labelLarge)),
                          SizedBox(width: 90, child: Text('Zmiany', textAlign: TextAlign.right, style: header)),
                          SizedBox(width: 120, child: Text('Poprawione', textAlign: TextAlign.right, style: header)),
                          SizedBox(width: 110, child: Text('Godziny', textAlign: TextAlign.right, style: text.labelLarge)),
                          const SizedBox(width: 40),
                        ],
                      ),
                    ),
                    if (rows.isEmpty)
                      Padding(padding: const EdgeInsets.all(24), child: Text('Brak pracowników.', style: text.bodyMedium)),
                    for (final m in rows) ...[
                      Builder(
                        builder: (context) {
                          final mine = [for (final s in shifts) if (s.memberId == m.id) s];
                          final edited = mine.where((s) => s.isEdited).length;
                          final diff = mine.fold(Duration.zero, (a, s) => a + (s.editDifference ?? Duration.zero));
                          final open = _expanded.contains(m.id);
                          return InkWell(
                            onTap: mine.isEmpty
                                ? null
                                : () => setState(() => open ? _expanded.remove(m.id) : _expanded.add(m.id)),
                            child: Container(
                              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.ring))),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelLarge),
                                  ),
                                  SizedBox(
                                    width: 90,
                                    child: Text(
                                      '${mine.length}',
                                      textAlign: TextAlign.right,
                                      style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      edited == 0 ? '–' : '$edited · ${diffText(diff)}',
                                      textAlign: TextAlign.right,
                                      style: text.bodyMedium?.copyWith(
                                        fontFeatures: _tabular,
                                        color: edited == 0 ? AppColors.textDisabled : editedColor,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      '${hoursText(sum(mine))} h',
                                      textAlign: TextAlign.right,
                                      style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 40,
                                    child: mine.isEmpty
                                        ? null
                                        : AnimatedRotation(
                                            turns: open ? 0.5 : 0,
                                            duration: const Duration(milliseconds: 180),
                                            child: Glyph(AppIcons.caretDown, size: 16, color: AppColors.textMuted),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      if (_expanded.contains(m.id))
                        Container(
                          color: AppColors.surfaceRaised.withValues(alpha: 0.5),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                          child: Column(
                            children: [
                              for (final s in shifts.reversed)
                                if (s.memberId == m.id)
                                  ShiftTile(shift: s, members: widget.members, canEdit: widget.canEdit, showName: false),
                            ],
                          ),
                        ),
                    ],
                    Container(
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.ringStrong))),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(child: Text('Razem', style: text.titleSmall)),
                          SizedBox(
                            width: 90,
                            child: Text('${shifts.length}', textAlign: TextAlign.right, style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
                          ),
                          const SizedBox(width: 120),
                          SizedBox(
                            width: 110,
                            child: Text(
                              '${hoursText(sum(shifts))} h',
                              textAlign: TextAlign.right,
                              style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                            ),
                          ),
                          const SizedBox(width: 40),
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

/// Ręczne dopisanie albo poprawa zmiany co do minuty, np. gdy pracownik zapomniał zeskanować kod.
/// Poprawka zapamiętuje godziny sprzed niej (żółte na liście, z różnicą).
class ShiftDialog extends ConsumerStatefulWidget {
  const ShiftDialog({super.key, required this.members, this.shift});

  final List<StaffMember> members;
  final StaffShift? shift;

  @override
  ConsumerState<ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends ConsumerState<ShiftDialog> {
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
        editorId: ref.read(panelMemberProvider)?.dbMemberId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = widget.shift;
    return AlertDialog(
      title: Text(s == null ? 'Dopisz zmianę' : 'Popraw zmianę'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _memberId,
              decoration: const InputDecoration(labelText: 'Pracownik'),
              icon: const Glyph(AppIcons.caretDown, size: 16),
              items: [
                for (final m in widget.members.where((m) => m.active || m.id == _memberId))
                  DropdownMenuItem(value: m.id, child: Text(m.name)),
              ],
              onChanged: s == null ? (v) => setState(() => _memberId = v) : null,
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
                      final t = await pickTime(context, initial: _start, minuteStep: 1, title: 'Początek zmiany');
                      if (t != null) setState(() => _start = t);
                    },
                    child: Text('Od ${_fmt(_start)}', style: const TextStyle(fontFeatures: _tabular)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await pickTime(
                        context,
                        initial: _end ?? _start,
                        minuteStep: 1,
                        allowEndOfDay: true,
                        title: 'Koniec zmiany',
                      );
                      if (t != null) setState(() => _end = t);
                    },
                    child: Text(_end == null ? 'Trwa' : 'Do ${_fmt(_end!)}', style: const TextStyle(fontFeatures: _tabular)),
                  ),
                ),
              ],
            ),
            if (s != null && s.isEdited) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: editedColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Przed poprawką: ${_hm(s.originalStartedAt!)} – '
                  '${s.originalEndedAt == null ? 'trwała' : _hm(s.originalEndedAt!)}',
                  style: text.bodyMedium?.copyWith(color: editedColor, fontFeatures: _tabular),
                ),
              ),
            ],
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
