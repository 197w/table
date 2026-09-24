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
    final positions = ref.watch(positionsProvider(restaurant.id)).value ?? const <StaffPosition>[];
    final positionNames = {for (final p in positions) p.id: p.name};
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
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _PositionsDialog(restaurantId: restaurant.id),
                ),
                icon: const Glyph(AppIcons.identification, size: 18),
                label: const Text('Stanowiska'),
              ),
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
                        positionNames: positionNames,
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
    required this.positionNames,
    required this.onEditMember,
    required this.onAdd,
    required this.onEdit,
  });

  final DateTime week;
  final List<StaffMember> members;
  final List<Availability> availability;
  final bool canEdit;

  /// Aktualne nazwy stanowisk po identyfikatorze. Po zmianie nazwy stanowiska
  /// lista pokazuje nową, a nie tę zapisaną przy pracowniku.
  final Map<String, String> positionNames;
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
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        m.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.labelLarge?.copyWith(
                                          color: m.active ? AppColors.text : AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                    if (m.userId != null) ...[
                                      const SizedBox(width: 6),
                                      Tooltip(
                                        message: 'Loguje się do panelu',
                                        child: Glyph(AppIcons.link, size: 12, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ],
                                ),
                                if (positionNames[m.positionId] != null || m.position != null || !m.active)
                                  Text(
                                    [
                                      ?(positionNames[m.positionId] ?? m.position),
                                      if (!m.active) 'nieaktywny',
                                    ].join(' · '),
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
  late final _firstName = TextEditingController(text: widget.member?.firstName ?? '');
  late final _lastName = TextEditingController(text: widget.member?.lastName ?? '');
  late final _phone = TextEditingController(text: widget.member?.phone ?? '');
  late String? _positionId = widget.member?.positionId;
  late int _color = widget.member?.color ?? 0;
  late bool _active = widget.member?.active ?? true;
  final _email = TextEditingController();

  /// Stan konta po zmianie w tym oknie. Pracownik przekazany do okna go jeszcze nie zna.
  bool? _linked;
  bool _busy = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  /// Łączy pracownika z kontem albo je odłącza. Konto dostaje uprawnienia stanowiska.
  Future<void> _account({required bool link}) async {
    final member = widget.member!;
    final email = _email.text.trim();
    if (link && !email.contains('@')) {
      showMessage(context, 'Wpisz adres e-mail, którym pracownik loguje się do Table.');
      return;
    }
    if (!link) {
      final ok = await confirm(
        context,
        title: 'Odłączyć konto?',
        message: '${member.name} nie zaloguje się już do panelu tego lokalu. Dane w grafiku zostają.',
        action: 'Odłącz',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      if (link) {
        await repo.linkStaffAccount(member.id, email);
      } else {
        await repo.unlinkStaffAccount(member.id);
      }
      ref
        ..invalidate(staffAccountsProvider(widget.restaurantId))
        ..invalidate(staffProvider(widget.restaurantId));
      _email.clear();
      _linked = link;
      if (mounted) {
        showMessage(
          context,
          link
              ? '${member.name} zaloguje się do panelu jako $email.'
              : 'Konto odłączone.',
        );
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(List<StaffPosition> positions) async {
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    StaffPosition? position;
    for (final p in positions) {
      if (p.id == _positionId) position = p;
    }
    final String? problem;
    if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
      problem = 'Wpisz imię i nazwisko pracownika.';
    } else if (digits.length < 9 || digits.length > 15) {
      problem = 'Wpisz numer telefonu, co najmniej 9 cyfr.';
    } else if (position == null) {
      problem = 'Wybierz stanowisko.';
    } else {
      problem = null;
    }
    if (problem != null) {
      showMessage(context, problem);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveStaffMember(
        restaurantId: widget.restaurantId,
        id: widget.member?.id,
        firstName: _firstName.text,
        lastName: _lastName.text,
        position: position!,
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
    final positions =
        ref.watch(positionsProvider(widget.restaurantId)).value ?? const <StaffPosition>[];
    final selected = positions.any((p) => p.id == _positionId) ? _positionId : null;

    return AlertDialog(
      title: Text(widget.member == null ? 'Nowy pracownik' : 'Pracownik'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _firstName,
                    autofocus: widget.member == null,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Imię', counterText: ''),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lastName,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nazwisko', counterText: ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                LengthLimitingTextInputFormatter(20),
              ],
              style: const TextStyle(fontFeatures: _tabular),
              decoration: const InputDecoration(labelText: 'Numer telefonu'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Stanowisko'),
              items: [
                for (final p in positions)
                  DropdownMenuItem(
                    value: p.id,
                    child: Row(
                      children: [
                        Text(p.name),
                        if (p.isSystem) ...[
                          const SizedBox(width: 8),
                          Glyph(AppIcons.lock, size: 12, color: AppColors.textDisabled),
                        ],
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _positionId = v),
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
              if (ref.watch(currentRestaurantProvider)?.canManage ?? false) ...[
                const SizedBox(height: 10),
                Divider(height: 1, color: AppColors.ring),
                const SizedBox(height: 14),
                _AccountSection(
                  email: ref.watch(staffAccountsProvider(widget.restaurantId)).value?[widget.member!.id],
                  linked: _linked ?? widget.member!.userId != null,
                  controller: _email,
                  busy: _busy,
                  onLink: () => _account(link: true),
                  onUnlink: () => _account(link: false),
                ),
              ],
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
        FilledButton(
          onPressed: _busy ? null : () => _save(positions),
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

/// Konto pracownika w panelu. Pracownik z kontem loguje się własnym e-mailem
/// i widzi to, na co pozwala jego stanowisko, np. Kelner nabija zamówienia.
class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.email,
    required this.linked,
    required this.controller,
    required this.busy,
    required this.onLink,
    required this.onUnlink,
  });

  final String? email;
  final bool linked;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onLink;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Konto w panelu', style: text.titleSmall),
        const SizedBox(height: 4),
        if (linked)
          Row(
            children: [
              Glyph(AppIcons.link, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  email == null ? 'Konto połączone' : 'Loguje się jako $email',
                  style: text.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: busy ? null : onUnlink,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Odłącz'),
              ),
            ],
          )
        else ...[
          Text(
            'Bez konta pracownik nie loguje się do panelu. Wpisz e-mail jego konta Table, '
            'a dostanie uprawnienia swojego stanowiska. Konta zakłada na razie administrator Table.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'E-mail konta', isDense: true),
                  onSubmitted: (_) => onLink(),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: busy ? null : onLink,
                icon: const Glyph(AppIcons.link, size: 16),
                label: const Text('Połącz'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Lista stanowisk: systemowe są zablokowane, własne można dodawać, zmieniać i usuwać.
class _PositionsDialog extends ConsumerWidget {
  const _PositionsDialog({required this.restaurantId});

  final String restaurantId;

  Future<void> _edit(BuildContext context, WidgetRef ref, [StaffPosition? position]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PositionEditor(restaurantId: restaurantId, position: position),
    );
    if (saved == true) {
      ref
        ..invalidate(positionsProvider(restaurantId))
        ..invalidate(staffProvider(restaurantId));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, StaffPosition position) async {
    final ok = await confirm(
      context,
      title: 'Usunąć stanowisko „${position.name}”?',
      message: 'Stanowiska przypisanego do pracowników nie da się usunąć. Najpierw zmień im stanowisko.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deletePosition(position.id);
      ref.invalidate(positionsProvider(restaurantId));
    } catch (e) {
      if (!context.mounted) return;
      final raw = e.toString().toLowerCase();
      showMessage(
        context,
        raw.contains('foreign key') || raw.contains('violates')
            ? 'To stanowisko ma przypisanych pracowników. Najpierw zmień im stanowisko.'
            : errorText(e),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(positionsProvider(restaurantId));

    return AlertDialog(
      title: const Text('Stanowiska'),
      content: SizedBox(
        width: 520,
        child: async.when(
          loading: () => const SizedBox(height: 120, child: LoadingView()),
          error: (e, _) => Text(errorText(e)),
          data: (positions) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Kelner, Kucharz i Dostawca są dodane przez system i nie da się ich usunąć, '
                'bo korzystają z nich pakiety Table. Własne stanowiska dodajesz poniżej. '
                'Uprawnienia zaczną działać, gdy pracownicy dostaną własne konta w panelu.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: positions.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.ring),
                  itemBuilder: (context, i) {
                    final p = positions[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(p.name, style: text.labelLarge),
                                    if (p.isSystem) ...[
                                      const SizedBox(width: 8),
                                      Glyph(AppIcons.lock, size: 12, color: AppColors.textDisabled),
                                      const SizedBox(width: 4),
                                      Text(
                                        'systemowe',
                                        style: text.bodySmall?.copyWith(color: AppColors.textDisabled),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  p.permissions.isEmpty
                                      ? 'Bez uprawnień'
                                      : p.permissions.map((x) => x.label).join(' · '),
                                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          if (!p.isSystem) ...[
                            IconButton(
                              tooltip: 'Zmień',
                              icon: const Glyph(AppIcons.pencil, size: 16),
                              onPressed: () => _edit(context, ref, p),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Usuń',
                              icon: Glyph(AppIcons.trash, size: 16, color: AppColors.error),
                              onPressed: () => _delete(context, ref, p),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Zamknij'),
        ),
        FilledButton.icon(
          onPressed: () => _edit(context, ref),
          icon: const Glyph(AppIcons.plus, size: 18),
          label: const Text('Dodaj stanowisko'),
        ),
      ],
    );
  }
}

/// Nazwa i uprawnienia własnego stanowiska.
class _PositionEditor extends ConsumerStatefulWidget {
  const _PositionEditor({required this.restaurantId, this.position});

  final String restaurantId;
  final StaffPosition? position;

  @override
  ConsumerState<_PositionEditor> createState() => _PositionEditorState();
}

class _PositionEditorState extends ConsumerState<_PositionEditor> {
  late final _name = TextEditingController(text: widget.position?.name ?? '');
  late final Set<StaffPermission> _permissions = {...?widget.position?.permissions};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, 'Wpisz nazwę stanowiska.');
      return;
    }
    const reserved = ['kelner', 'kucharz', 'dostawca'];
    if (reserved.contains(name.toLowerCase())) {
      showMessage(context, 'Stanowisko „$name” jest już dodane przez system.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).savePosition(
        restaurantId: widget.restaurantId,
        id: widget.position?.id,
        name: name,
        permissions: [
          for (final p in StaffPermission.values)
            if (_permissions.contains(p)) p,
        ],
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().toLowerCase();
      showMessage(
        context,
        raw.contains('duplicate') || raw.contains('unique')
            ? 'Stanowisko o tej nazwie już istnieje.'
            : errorText(e),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.position == null ? 'Nowe stanowisko' : 'Stanowisko'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: widget.position == null,
                maxLength: 40,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nazwa',
                  hintText: 'Barman, Kierownik zmiany, Hostessa',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              Text('Uprawnienia', style: text.titleSmall),
              const SizedBox(height: 4),
              for (final p in StaffPermission.values)
                CheckboxListTile(
                  value: _permissions.contains(p),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _permissions.add(p);
                    } else {
                      _permissions.remove(p);
                    }
                  }),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  activeColor: AppColors.accentFill,
                  checkColor: AppColors.onAccent,
                  title: Row(
                    children: [
                      Text(p.label, style: text.bodyMedium),
                      if (p.soon) ...[
                        const SizedBox(width: 8),
                        Tag('WKRÓTCE', color: AppColors.textMuted),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    p.description,
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
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
    final picked = await pickTime(context, initial: start ? _starts : _ends);
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
