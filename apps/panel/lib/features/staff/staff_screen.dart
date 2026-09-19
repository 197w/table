import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Kolory pracowników w kalendarzu. Czytelne w jasnym i ciemnym motywie.
const staffColors = [
  Color(0xFF16A37F),
  Color(0xFF3B82F6),
  Color(0xFFE08A1E),
  Color(0xFFD9467A),
  Color(0xFF8B5CF6),
  Color(0xFF0EA5B7),
  Color(0xFFB45309),
  Color(0xFF64748B),
];

const _weekdayShort = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];

DateTime _weekStart(DateTime d) {
  final day = dateOnly(d);
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  DateTime _week = _weekStart(DateTime.now());
  bool _showInactive = false;

  Future<void> _editMember(String restaurantId, [StaffMember? member]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MemberDialog(restaurantId: restaurantId, member: member),
    );
    if (saved == true) ref.invalidate(staffProvider(restaurantId));
  }

  Future<void> _editAvailability(
    String restaurantId,
    StaffMember member,
    DateTime day, [
    Availability? existing,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AvailabilityDialog(
        restaurantId: restaurantId,
        member: member,
        day: day,
        existing: existing,
      ),
    );
    if (saved == true) {
      ref.invalidate(availabilityProvider((restaurantId: restaurantId, weekStart: _week)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final canEdit = restaurant.canManage;
    final staffAsync = ref.watch(staffProvider(restaurant.id));
    final query = (restaurantId: restaurant.id, weekStart: _week);
    final availability = ref.watch(availabilityProvider(query)).value ?? const <Availability>[];
    final weekEnd = DateTime(_week.year, _week.month, _week.day + 6);
    final isThisWeek = _week == _weekStart(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Pracownicy',
          subtitle:
              'Dyspozycyjność ${Fmt.dayShort(_week)} – ${Fmt.dayShort(weekEnd)}${isThisWeek ? ' · ten tydzień' : ''}',
          actions: [
            IconButton(
              tooltip: 'Poprzedni tydzień',
              icon: const Glyph(AppIcons.caretLeft, size: 18),
              onPressed: () => setState(() => _week = DateTime(_week.year, _week.month, _week.day - 7)),
            ),
            OutlinedButton(
              onPressed: isThisWeek ? null : () => setState(() => _week = _weekStart(DateTime.now())),
              child: const Text('Ten tydzień'),
            ),
            IconButton(
              tooltip: 'Następny tydzień',
              icon: const Glyph(AppIcons.caretRight, size: 18),
              onPressed: () => setState(() => _week = DateTime(_week.year, _week.month, _week.day + 7)),
            ),
            if (canEdit) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _editMember(restaurant.id),
                icon: const Glyph(AppIcons.plus, size: 18),
                label: const Text('Dodaj pracownika'),
              ),
            ],
          ],
        ),
        if (!canEdit)
          const ReadOnlyBanner(message: 'Grafik układa kierownik albo właściciel lokalu.'),
        Expanded(
          child: staffAsync.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(staffProvider(restaurant.id)),
            ),
            data: (all) {
              final members = all.where((m) => _showInactive || m.active).toList();
              if (all.isEmpty) {
                return MessageView(
                  icon: AppIcons.users,
                  title: 'Brak pracowników',
                  message: canEdit
                      ? 'Dodaj pracowników, a potem wpisz im dyspozycyjność w kalendarzu.'
                      : 'Kierownik jeszcze nie dodał pracowników.',
                  actionLabel: canEdit ? 'Dodaj pracownika' : null,
                  onAction: canEdit ? () => _editMember(restaurant.id) : null,
                );
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: _WeekGrid(
                        week: _week,
                        members: members,
                        availability: availability,
                        canEdit: canEdit,
                        onEditMember: (m) => _editMember(restaurant.id, m),
                        onAdd: (m, day) => _editAvailability(restaurant.id, m, day),
                        onEdit: (m, a) => _editAvailability(restaurant.id, m, a.day, a),
                      ),
                    ),
                    if (all.any((m) => !m.active))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => setState(() => _showInactive = !_showInactive),
                          child: Text(_showInactive ? 'Ukryj nieaktywnych' : 'Pokaż nieaktywnych'),
                        ),
                      ),
                    if (canEdit) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Kliknij pole w kalendarzu, żeby dodać dyspozycyjność. Kliknij godziny, żeby je zmienić albo usunąć. '
                        'Kliknij imię, żeby edytować pracownika.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.week,
    required this.members,
    required this.availability,
    required this.canEdit,
    required this.onEditMember,
    required this.onAdd,
    required this.onEdit,
  });

  final DateTime week;
  final List<StaffMember> members;
  final List<Availability> availability;
  final bool canEdit;
  final ValueChanged<StaffMember> onEditMember;
  final void Function(StaffMember member, DateTime day) onAdd;
  final void Function(StaffMember member, Availability entry) onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final days = [for (var i = 0; i < 7; i++) DateTime(week.year, week.month, week.day + i)];
    final today = dateOnly(DateTime.now());

    Widget headerCell(int i) {
      final isToday = days[i] == today;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.ring)),
            color: isToday ? AppColors.accentTint : null,
          ),
          child: Column(
            children: [
              Text(_weekdayShort[i], style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
              Text(
                '${days[i].day}.${days[i].month.toString().padLeft(2, '0')}',
                style: text.titleSmall?.copyWith(
                  fontFeatures: _tabular,
                  color: isToday ? AppColors.accent : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 220,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Pracownik', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
              ),
            ),
            for (var i = 0; i < 7; i++) headerCell(i),
          ],
        ),
        for (final m in members) ...[
          Divider(height: 1, color: AppColors.ring),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 220,
                  child: InkWell(
                    onTap: canEdit ? () => onEditMember(m) : null,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: staffColors[m.color % staffColors.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  m.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.labelLarge?.copyWith(
                                    color: m.active ? AppColors.text : AppColors.textMuted,
                                  ),
                                ),
                                if (m.position != null || !m.active)
                                  Text(
                                    [if (m.position != null) m.position!, if (!m.active) 'nieaktywny'].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (final day in days)
                  Expanded(
                    child: _DayCell(
                      member: m,
                      day: day,
                      entries: availability
                          .where((a) => a.memberId == m.id && dateOnly(a.day) == day)
                          .toList(),
                      canEdit: canEdit,
                      isToday: day == today,
                      onAdd: () => onAdd(m, day),
                      onEdit: (a) => onEdit(m, a),
                    ),
                  ),
              ],
            ),
          ),
        ],
        Divider(height: 1, color: AppColors.ring),
        Row(
          children: [
            SizedBox(
              width: 220,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text('Dostępnych osób', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
              ),
            ),
            for (final day in days)
              Expanded(
                child: Text(
                  '${members.where((m) => availability.any((a) => a.memberId == m.id && dateOnly(a.day) == day)).length}',
                  textAlign: TextAlign.center,
                  style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.member,
    required this.day,
    required this.entries,
    required this.canEdit,
    required this.isToday,
    required this.onAdd,
    required this.onEdit,
  });

  final StaffMember member;
  final DateTime day;
  final List<Availability> entries;
  final bool canEdit;
  final bool isToday;
  final VoidCallback onAdd;
  final ValueChanged<Availability> onEdit;

  @override
  Widget build(BuildContext context) {
    final color = staffColors[member.color % staffColors.length];
    final text = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.ring)),
        color: isToday ? AppColors.accentTint.withValues(alpha: 0.4) : null,
      ),
      child: InkWell(
        onTap: canEdit ? onAdd : null,
        hoverColor: AppColors.ring,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final a in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Tooltip(
                    message: a.note ?? '',
                    child: Material(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: canEdit ? () => onEdit(a) : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border(left: BorderSide(color: color, width: 3)),
                          ),
                          child: Text(
                            '${a.starts}–${a.ends}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelMedium?.copyWith(fontFeatures: _tabular),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (entries.isEmpty && canEdit)
                Expanded(
                  child: Center(
                    child: Glyph(AppIcons.plus, size: 14, color: AppColors.textDisabled),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberDialog extends ConsumerStatefulWidget {
  const _MemberDialog({required this.restaurantId, this.member});

  final String restaurantId;
  final StaffMember? member;

  @override
  ConsumerState<_MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends ConsumerState<_MemberDialog> {
  late final _name = TextEditingController(text: widget.member?.name ?? '');
  late final _position = TextEditingController(text: widget.member?.position ?? '');
  late final _phone = TextEditingController(text: widget.member?.phone ?? '');
  late int _color = widget.member?.color ?? 0;
  late bool _active = widget.member?.active ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _position.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showMessage(context, 'Wpisz imię pracownika.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveStaffMember(
        restaurantId: widget.restaurantId,
        id: widget.member?.id,
        name: _name.text,
        position: _position.text,
        phone: _phone.text,
        color: _color,
        active: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Usunąć ${widget.member!.name}?',
      message: 'Razem z pracownikiem znikną jego wpisy w kalendarzu. Jeśli tylko odchodzi, możesz go oznaczyć jako nieaktywnego.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteStaffMember(widget.member!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.member == null ? 'Nowy pracownik' : 'Pracownik'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.member == null,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Imię i nazwisko', counterText: ''),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _position,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Stanowisko',
                      hintText: 'Kelner, kucharz, barman',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                    decoration: const InputDecoration(labelText: 'Telefon (opcjonalnie)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Kolor w kalendarzu', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < staffColors.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _color = i),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: staffColors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: i == _color ? AppColors.text : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (widget.member != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Text('Aktywny w grafiku', style: text.bodyMedium)),
                  Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.member != null)
          TextButton(
            onPressed: _busy ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Usuń'),
          ),
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

class _AvailabilityDialog extends ConsumerStatefulWidget {
  const _AvailabilityDialog({
    required this.restaurantId,
    required this.member,
    required this.day,
    this.existing,
  });

  final String restaurantId;
  final StaffMember member;
  final DateTime day;
  final Availability? existing;

  @override
  ConsumerState<_AvailabilityDialog> createState() => _AvailabilityDialogState();
}

class _AvailabilityDialogState extends ConsumerState<_AvailabilityDialog> {
  late TimeOfDay _starts = _parse(widget.existing?.starts ?? '10:00');
  late TimeOfDay _ends = _parse(widget.existing?.ends ?? '18:00');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  bool _busy = false;

  static TimeOfDay _parse(String hm) {
    final p = hm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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

  Future<void> _save() async {
    if (_ends.hour * 60 + _ends.minute <= _starts.hour * 60 + _starts.minute) {
      showMessage(context, 'Koniec musi być później niż początek.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveAvailability(
        restaurantId: widget.restaurantId,
        id: widget.existing?.id,
        memberId: widget.member.id,
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

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).deleteAvailability(widget.existing!.id);
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
    Widget timeButton(TimeOfDay t, bool start) => OutlinedButton(
      onPressed: () => _pick(start),
      style: OutlinedButton.styleFrom(minimumSize: const Size(96, 44)),
      child: Text(_fmt(t), style: const TextStyle(fontFeatures: _tabular, fontSize: 16)),
    );

    return AlertDialog(
      title: Text(widget.member.name),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Dyspozycyjność: ${Fmt.capitalize(Fmt.dayLong(widget.day))}',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                timeButton(_starts, true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('–', style: text.titleMedium),
                ),
                timeButton(_ends, false),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Uwagi (opcjonalnie)', hintText: 'Na przykład: tylko sala'),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: _busy ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Usuń'),
          ),
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
