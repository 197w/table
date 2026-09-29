import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import 'timesheet.dart';

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

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';

String _initials(String name) =>
    name.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();

/// Zakładki: 0 zespół (kafelki pracowników), 1 grafik (dyspozycyjność i propozycje godzin),
/// 2 czas pracy (zmiany ze stanowiska).
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  DateTime _week = _weekStart(DateTime.now());
  bool _showInactive = false;
  int _tab = 0;

  Future<void> _addMember(String restaurantId) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _MemberDialog(restaurantId: restaurantId),
    );
    if (id == null || !mounted) return;
    ref.invalidate(staffProvider(restaurantId));
    // Nowy pracownik od razu dostaje login i krótkie hasło do głównego stanowiska.
    try {
      final created = await ref.read(repositoryProvider).createStaffLogin(id);
      ref.invalidate(staffLoginsProvider(restaurantId));
      final members = await ref.read(staffProvider(restaurantId).future);
      if (!mounted) return;
      final name = members.where((m) => m.id == id).firstOrNull?.name ?? 'Pracownik';
      await showDialog<void>(
        context: context,
        builder: (_) => CredentialsDialog(name: name, login: created.login, password: created.password),
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Pracownik dodany, ale nie udało się utworzyć loginu: ${errorText(e)}');
    }
  }

  Future<void> _openMember(String restaurantId, StaffMember member) {
    return showDialog<void>(
      context: context,
      builder: (_) => _MemberDetailsDialog(restaurantId: restaurantId, member: member),
    );
  }

  Future<void> _plan(String restaurantId, StaffMember member, DateTime day, PlannedShift? existing,
      List<Availability> availability) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PlanDialog(
        restaurantId: restaurantId,
        member: member,
        day: day,
        existing: existing,
        availability: availability,
        week: _week,
      ),
    );
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
    final permissions = ref.watch(effectivePermissionsProvider(restaurant.id)) ?? const <String>{};
    // Zakładka „Zespół” i czas pracy: uprawnienie „Pracownicy”. Grafik: także samo „Grafik”.
    final canStaff = permissions.contains('staff');
    final canPlan = canStaff || permissions.contains('schedule');
    // Uprawnienia stanowisk zmienia tylko właściciel lub kierownik na swoim koncie,
    // nie pracownik zalogowany na stanowisku.
    final canEditPositions = ref.watch(actingMemberProvider) == null && restaurant.canManage;
    final tabs = [if (canStaff) (0, 'Zespół'), (1, 'Grafik'), if (canStaff) (2, 'Czas pracy')];
    final tab = tabs.any((t) => t.$1 == _tab) ? _tab : tabs.first.$1;

    final staffAsync = ref.watch(staffProvider(restaurant.id));
    final all = staffAsync.value ?? const <StaffMember>[];
    final weekEnd = DateTime(_week.year, _week.month, _week.day + 6);
    final isThisWeek = _week == _weekStart(DateTime.now());
    final thisWeek = _weekStart(DateTime.now());
    final shifts = ref.watch(
      shiftsProvider((
        restaurantId: restaurant.id,
        from: thisWeek,
        to: DateTime(thisWeek.year, thisWeek.month, thisWeek.day + 7),
      )),
    ).value ?? const <StaffShift>[];
    final working = {for (final s in shifts) if (s.isOpen) s.memberId: s.startedAt};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Pracownicy',
          subtitle: tab == 0
              ? '${all.where((m) => m.active).length} w zespole · ${working.length} teraz w pracy'
              : '${tab == 1 ? 'Grafik' : 'Czas pracy'} ${Fmt.dayShort(_week)} – ${Fmt.dayShort(weekEnd)}'
                    '${isThisWeek ? ' · ten tydzień' : ''}',
          below: tabs.length < 2
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedTabs<int>(
                    options: tabs,
                    selected: tab,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                ),
          actions: [
            if (tab == 0) ...[
              if (canEditPositions)
                OutlinedButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => _PositionsDialog(restaurantId: restaurant.id),
                  ),
                  icon: const Glyph(AppIcons.identification, size: 18),
                  label: const Text('Stanowiska'),
                ),
              FilledButton.icon(
                onPressed: () => _addMember(restaurant.id),
                icon: const Glyph(AppIcons.plus, size: 18),
                label: const Text('Dodaj pracownika'),
              ),
            ] else ...[
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
            ],
          ],
        ),
        Expanded(
          child: staffAsync.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(staffProvider(restaurant.id)),
            ),
            data: (all) {
              if (all.isEmpty) {
                return MessageView(
                  icon: AppIcons.users,
                  title: 'Brak pracowników',
                  message: canStaff
                      ? 'Dodaj pracownika. Dostanie login i krótkie hasło do logowania na głównym stanowisku.'
                      : 'Kierownik jeszcze nie dodał pracowników.',
                  actionLabel: canStaff ? 'Dodaj pracownika' : null,
                  onAction: canStaff ? () => _addMember(restaurant.id) : null,
                );
              }
              final members = all.where((m) => _showInactive || m.active).toList();
              final toggleInactive = all.any((m) => !m.active)
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => _showInactive = !_showInactive),
                        child: Text(_showInactive ? 'Ukryj nieaktywnych' : 'Pokaż nieaktywnych'),
                      ),
                    )
                  : null;

              if (tab == 2) {
                return Timesheet(
                  restaurantId: restaurant.id,
                  week: _week,
                  members: all,
                  canEdit: canStaff,
                );
              }

              if (tab == 0) {
                return _TeamGrid(
                  restaurantId: restaurant.id,
                  members: members,
                  shifts: shifts,
                  working: working,
                  onOpen: (m) => _openMember(restaurant.id, m),
                  onAdd: () => _addMember(restaurant.id),
                  footer: toggleInactive,
                );
              }

              final query = (restaurantId: restaurant.id, weekStart: _week);
              final availability = ref.watch(availabilityProvider(query)).value ?? const <Availability>[];
              final planned = ref.watch(plannedShiftsProvider(query)).value ?? const <PlannedShift>[];
              final positions = ref.watch(positionsProvider(restaurant.id)).value ?? const <StaffPosition>[];
              final waiting = planned.where((p) => p.status == PlannedShiftStatus.changed).length;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (waiting > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _Banner(
                          icon: AppIcons.chatText,
                          text: waiting == 1
                              ? 'Jeden pracownik proponuje inne godziny. Kliknij pomarańczowy wpis, żeby odpowiedzieć.'
                              : 'Pracownicy proponują inne godziny ($waiting). Kliknij pomarańczowe wpisy, żeby odpowiedzieć.',
                        ),
                      ),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: _WeekGrid(
                        week: _week,
                        members: members,
                        availability: availability,
                        planned: planned,
                        canPlan: canPlan,
                        positionNames: {for (final p in positions) p.id: p.name},
                        onOpenMember: canStaff ? (m) => _openMember(restaurant.id, m) : null,
                        onPlan: (m, day, existing) => _plan(
                          restaurant.id,
                          m,
                          day,
                          existing,
                          availability.where((a) => a.memberId == m.id && dateOnly(a.day) == day).toList(),
                        ),
                        onEditAvailability: canPlan ? (m, a) => _editAvailability(restaurant.id, m, a.day, a) : null,
                      ),
                    ),
                    ?toggleInactive,
                    const SizedBox(height: 8),
                    const _Legend(),
                    if (canPlan) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Kliknij dzień pracownika, żeby zaproponować mu godziny. Pracownik przyjmuje je '
                        'albo proponuje inne w aplikacji Table for employees. Jasne pola to dyspozycyjność.',
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

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final AppIconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _changed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _changed.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Glyph(icon, size: 18, color: _changed),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Kolor propozycji zmienionej przez pracownika: czeka na odpowiedź przełożonego.
const _changed = Color(0xFFE08A1E);

Color _statusColor(PlannedShiftStatus s) => switch (s) {
  PlannedShiftStatus.accepted => AppColors.accent,
  PlannedShiftStatus.proposed => AppColors.textMuted,
  PlannedShiftStatus.changed => _changed,
};

AppIconData _statusIcon(PlannedShiftStatus s) => switch (s) {
  PlannedShiftStatus.accepted => AppIcons.checkCircle,
  PlannedShiftStatus.proposed => AppIcons.clock,
  PlannedShiftStatus.changed => AppIcons.chatText,
};

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    return Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        for (final s in PlannedShiftStatus.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Glyph(_statusIcon(s), size: 14, color: _statusColor(s)),
              const SizedBox(width: 6),
              Text(s.label, style: text),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Zespół: kafelki pracowników
// ---------------------------------------------------------------

class _TeamGrid extends ConsumerWidget {
  const _TeamGrid({
    required this.restaurantId,
    required this.members,
    required this.shifts,
    required this.working,
    required this.onOpen,
    required this.onAdd,
    this.footer,
  });

  final String restaurantId;
  final List<StaffMember> members;

  /// Zmiany z bieżącego tygodnia, do godzin na kafelkach.
  final List<StaffShift> shifts;

  /// Kto jest teraz w pracy i od kiedy.
  final Map<String, DateTime> working;
  final ValueChanged<StaffMember> onOpen;
  final VoidCallback onAdd;
  final Widget? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logins = ref.watch(staffLoginsProvider(restaurantId)).value ?? const <String, StaffLogin>{};
    final positions = ref.watch(positionsProvider(restaurantId)).value ?? const <StaffPosition>[];
    final positionNames = {for (final p in positions) p.id: p.name};
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              const gap = 14.0;
              final columns = (box.maxWidth / 300).floor().clamp(1, 6);
              final width = (box.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(width: width, height: 168, child: _AddTile(onTap: onAdd)),
                  for (final m in members)
                    SizedBox(
                      width: width,
                      height: 168,
                      child: _MemberTile(
                        member: m,
                        position: positionNames[m.positionId] ?? m.position,
                        login: logins[m.id],
                        workingSince: working[m.id],
                        week: shifts
                            .where((s) => s.memberId == m.id)
                            .fold(Duration.zero, (sum, s) => sum + s.duration),
                        onTap: () => onOpen(m),
                      ),
                    ),
                ],
              );
            },
          ),
          if (footer != null) ...[const SizedBox(height: 8), footer!],
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.ringStrong, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accentTint, borderRadius: BorderRadius.circular(22)),
                child: Glyph(AppIcons.plus, size: 22, color: AppColors.accent),
              ),
              const SizedBox(height: 10),
              Text('Dodaj pracownika', style: text.titleSmall),
              const SizedBox(height: 2),
              Text(
                'Dostanie login i krótkie hasło',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.position,
    required this.login,
    required this.workingSince,
    required this.week,
    required this.onTap,
  });

  final StaffMember member;
  final String? position;
  final StaffLogin? login;
  final DateTime? workingSince;
  final Duration week;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = staffColors[member.color % staffColors.length];
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(name: member.name, color: color, size: 44, dimmed: !member.active),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(
                            color: member.active ? AppColors.text : AppColors.textMuted,
                          ),
                        ),
                        Text(
                          [?position, if (!member.active) 'nieaktywny'].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (workingSince != null)
                _Pill(
                  icon: AppIcons.timer,
                  text: 'W pracy od ${_hm(workingSince!)}',
                  color: AppColors.accent,
                )
              else
                _Pill(
                  icon: AppIcons.clock,
                  text: 'W tym tygodniu ${hoursText(week)} h',
                  color: AppColors.textMuted,
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Glyph(
                    login == null ? AppIcons.warning : AppIcons.password,
                    size: 14,
                    color: login == null ? _changed : AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      login == null
                          ? 'Bez loginu do stanowiska'
                          : 'Login: ${login!.login}${login!.locked ? ' (zablokowany)' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: login == null ? _changed : AppColors.textMuted,
                        fontFeatures: _tabular,
                      ),
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

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color});

  final AppIconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontFeatures: _tabular),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.color, this.size = 40, this.dimmed = false});

  final String name;
  final Color color;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = dimmed ? AppColors.textMuted : color;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: c,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Szczegóły pracownika: dane, login do stanowiska i statystyki
// ---------------------------------------------------------------

class _MemberDetailsDialog extends ConsumerStatefulWidget {
  const _MemberDetailsDialog({required this.restaurantId, required this.member});

  final String restaurantId;
  final StaffMember member;

  @override
  ConsumerState<_MemberDetailsDialog> createState() => _MemberDetailsDialogState();
}

class _MemberDetailsDialogState extends ConsumerState<_MemberDetailsDialog> {
  int _days = 30;
  bool _busy = false;

  Future<void> _edit(StaffMember member) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _MemberDialog(restaurantId: widget.restaurantId, member: member),
    );
    if (result == null) return;
    ref.invalidate(staffProvider(widget.restaurantId));
    // Usunięty pracownik: zamykamy też szczegóły.
    if (result == _MemberDialog.deleted && mounted) Navigator.pop(context);
  }

  Future<void> _newPassword(StaffMember member, StaffLogin? login) async {
    if (login != null) {
      final ok = await confirm(
        context,
        title: 'Nadać nowe hasło?',
        message: 'Dotychczasowe hasło ${member.name} przestanie działać.',
        action: 'Nadaj nowe hasło',
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      final String loginText;
      final String password;
      if (login == null) {
        final created = await repo.createStaffLogin(member.id);
        (loginText, password) = (created.login, created.password);
      } else {
        password = await repo.resetStaffPassword(member.id);
        loginText = login.login;
      }
      ref.invalidate(staffLoginsProvider(widget.restaurantId));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => CredentialsDialog(name: member.name, login: loginText, password: password),
      );
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final members = ref.watch(staffProvider(widget.restaurantId)).value;
    final member = members?.where((m) => m.id == widget.member.id).firstOrNull ?? widget.member;
    final login = ref.watch(staffLoginsProvider(widget.restaurantId)).value?[member.id];
    final positions = ref.watch(positionsProvider(widget.restaurantId)).value ?? const <StaffPosition>[];
    final position = positions.where((p) => p.id == member.positionId).firstOrNull;
    final statsAsync = ref.watch(memberStatsProvider((memberId: member.id, days: _days)));
    final stats = statsAsync.value;
    final color = staffColors[member.color % staffColors.length];

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _Avatar(name: member.name, color: color, size: 56, dimmed: !member.active),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(member.name, style: text.headlineSmall),
                        const SizedBox(height: 2),
                        Text(
                          [
                            ?(position?.name ?? member.position),
                            ?member.phone,
                            if (!member.active) 'nieaktywny',
                          ].join(' · '),
                          style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _edit(member),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                    icon: const Glyph(AppIcons.pencil, size: 16),
                    label: const Text('Edytuj'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Zamknij',
                    onPressed: () => Navigator.pop(context),
                    icon: const Glyph(AppIcons.close, size: 18),
                  ),
                ],
              ),
              if (position != null && position.permissions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in position.permissions) Tag(p.label.toUpperCase(), color: AppColors.textMuted),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              // Login do głównego stanowiska. Hasło widać tylko przy tworzeniu albo zmianie.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Glyph(AppIcons.password, size: 22, color: AppColors.accent),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            login == null ? 'Brak loginu do stanowiska' : 'Login: ${login.login}',
                            style: text.titleMedium?.copyWith(fontFeatures: _tabular),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            login == null
                                ? 'Utwórz login i krótkie hasło, żeby pracownik mógł wejść na zmianę na głównym stanowisku.'
                                : login.locked
                                ? 'Zablokowany po kilku błędnych hasłach. Nowe hasło zdejmuje blokadę.'
                                : 'Hasło widać tylko przy nadawaniu. Zapomniane? Nadaj nowe.',
                            style: text.bodySmall?.copyWith(
                              color: login?.locked ?? false ? AppColors.error : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: _busy ? null : () => _newPassword(member, login),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                      child: Text(login == null ? 'Utwórz login' : 'Nadaj nowe hasło'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Text('Statystyki', style: text.titleLarge)),
                  SegmentedTabs<int>(
                    options: const [(7, '7 dni'), (30, '30 dni'), (90, '90 dni')],
                    selected: _days,
                    onChanged: (d) => setState(() => _days = d),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (statsAsync.hasError)
                Text(errorText(statsAsync.error!), style: text.bodyMedium?.copyWith(color: AppColors.error))
              else if (stats == null)
                const SizedBox(height: 160, child: LoadingView())
              else ...[
                LayoutBuilder(
                  builder: (context, box) {
                    const gap = 12.0;
                    final width = (box.maxWidth - gap * 2) / 3;
                    final tiles = [
                      ('Czas pracy', '${hoursText(Duration(seconds: stats.seconds))} h', '${stats.shifts} zmian'),
                      ('W tym tygodniu', '${hoursText(Duration(seconds: stats.weekSeconds))} h',
                          stats.openSince == null ? 'teraz poza pracą' : 'w pracy od ${_hm(stats.openSince!)}'),
                      ('Sprzedaż', Fmt.price(stats.revenueGrosze), '${stats.ordersClosed} zamkniętych rachunków'),
                      ('Średni rachunek', stats.ordersClosed == 0 ? '—' : Fmt.price(stats.averageOrder), 'na zamknięty rachunek'),
                      ('Otwarte stoliki', '${stats.ordersOpened}', 'rachunki otwarte przez pracownika'),
                      ('Nabite pozycje', '${stats.items}', 'dania i napoje'),
                    ];
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final (label, value, hint) in tiles)
                          SizedBox(width: width, child: _StatTile(label: label, value: value, hint: hint)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Najczęściej nabijane', style: text.titleSmall),
                          const SizedBox(height: 6),
                          if (stats.topItems.isEmpty)
                            Text('Brak zamówień w tym okresie.',
                                style: text.bodySmall?.copyWith(color: AppColors.textMuted))
                          else
                            for (final (name, quantity) in stats.topItems)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    Text('$quantity×', style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Grafik', style: text.titleSmall),
                          const SizedBox(height: 6),
                          Text(
                            stats.planned == 0
                                ? 'Brak zaplanowanych zmian.'
                                : 'Zaplanowane zmiany od dziś: ${stats.planned}.',
                            style: text.bodyMedium,
                          ),
                          if (stats.lastShift != null)
                            Text(
                              'Ostatnia zmiana: ${Fmt.dayShort(stats.lastShift!)}, ${_hm(stats.lastShift!)}',
                              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.hint});

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ring),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(value, style: text.headlineSmall?.copyWith(fontFeatures: _tabular)),
          const SizedBox(height: 2),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Login i hasło pokazane raz: przy dodaniu pracownika albo nadaniu nowego hasła.
class CredentialsDialog extends StatelessWidget {
  const CredentialsDialog({super.key, required this.name, required this.login, required this.password});

  final String name;
  final String login;
  final String password;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: text.headlineSmall?.copyWith(fontFeatures: _tabular, letterSpacing: 1),
            ),
          ),
          IconButton(
            tooltip: 'Kopiuj',
            icon: const Glyph(AppIcons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              showMessage(context, 'Skopiowano.');
            },
          ),
        ],
      ),
    );

    return AlertDialog(
      title: Text('Login dla: $name'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [row('Login', login), row('Hasło', password)]),
            ),
            const SizedBox(height: 14),
            Text(
              'Przekaż je pracownikowi. Loguje się nimi na głównym stanowisku („Wejdź na zmianę” '
              'i przy zamówieniach). Hasło widać tylko teraz. Gdy zginie, nadaj nowe w szczegółach pracownika.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Gotowe')),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Grafik: dyspozycyjność i propozycje godzin
// ---------------------------------------------------------------

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.week,
    required this.members,
    required this.availability,
    required this.planned,
    required this.canPlan,
    required this.positionNames,
    required this.onOpenMember,
    required this.onPlan,
    required this.onEditAvailability,
  });

  final DateTime week;
  final List<StaffMember> members;
  final List<Availability> availability;
  final List<PlannedShift> planned;
  final bool canPlan;

  /// Aktualne nazwy stanowisk po identyfikatorze. Po zmianie nazwy stanowiska
  /// lista pokazuje nową, a nie tę zapisaną przy pracowniku.
  final Map<String, String> positionNames;
  final ValueChanged<StaffMember>? onOpenMember;
  final void Function(StaffMember member, DateTime day, PlannedShift? existing) onPlan;
  final void Function(StaffMember member, Availability entry)? onEditAvailability;

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
                    onTap: onOpenMember == null ? null : () => onOpenMember!(m),
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
                      entries: availability
                          .where((a) => a.memberId == m.id && dateOnly(a.day) == day)
                          .toList(),
                      planned: planned.where((p) => p.memberId == m.id && dateOnly(p.day) == day).firstOrNull,
                      canPlan: canPlan,
                      isToday: day == today,
                      onPlan: (existing) => onPlan(m, day, existing),
                      onEditAvailability: onEditAvailability == null ? null : (a) => onEditAvailability!(m, a),
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
                child: Text('W grafiku / dostępnych', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
              ),
            ),
            for (final day in days)
              Expanded(
                child: Text(
                  '${planned.where((p) => dateOnly(p.day) == day && members.any((m) => m.id == p.memberId)).length}'
                  ' / '
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

/// Dzień pracownika w grafiku: jasne pola to dyspozycyjność, pełne to godziny w grafiku.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.member,
    required this.entries,
    required this.planned,
    required this.canPlan,
    required this.isToday,
    required this.onPlan,
    required this.onEditAvailability,
  });

  final StaffMember member;
  final List<Availability> entries;
  final PlannedShift? planned;
  final bool canPlan;
  final bool isToday;
  final ValueChanged<PlannedShift?> onPlan;
  final ValueChanged<Availability>? onEditAvailability;

  @override
  Widget build(BuildContext context) {
    final color = staffColors[member.color % staffColors.length];
    final text = Theme.of(context).textTheme;
    final shift = planned;
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.ring)),
        color: isToday ? AppColors.accentTint.withValues(alpha: 0.18) : null,
      ),
      child: InkWell(
        onTap: canPlan ? () => onPlan(shift) : null,
        hoverColor: AppColors.ring,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (shift != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Tooltip(
                    message: [
                      shift.status.label,
                      if (shift.status == PlannedShiftStatus.changed)
                        'Proponuje ${shift.changeStarts}–${shift.changeEnds}',
                      ?shift.reply,
                    ].join('\n'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: shift.status == PlannedShiftStatus.changed
                            ? _changed.withValues(alpha: 0.18)
                            : color.withValues(alpha: shift.status == PlannedShiftStatus.accepted ? 0.9 : 0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: shift.status == PlannedShiftStatus.changed ? Border.all(color: _changed) : null,
                      ),
                      child: Row(
                        children: [
                          Glyph(
                            _statusIcon(shift.status),
                            size: 13,
                            color: shift.status == PlannedShiftStatus.accepted ? Colors.white : _statusColor(shift.status),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '${shift.starts}–${shift.ends}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelMedium?.copyWith(
                                fontFeatures: _tabular,
                                fontWeight: FontWeight.w600,
                                color: shift.status == PlannedShiftStatus.accepted ? Colors.white : AppColors.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              for (final a in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Tooltip(
                    message: ['Dyspozycyjność', ?a.note].join(': '),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: onEditAvailability == null ? null : () => onEditAvailability!(a),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: color.withValues(alpha: 0.45), style: BorderStyle.solid),
                          ),
                          child: Text(
                            '${a.starts}–${a.ends}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelSmall?.copyWith(fontFeatures: _tabular, color: AppColors.textMuted),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (shift == null && entries.isEmpty && canPlan)
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

/// Propozycja godzin dla pracownika w danym dniu. Gdy pracownik zaproponował inne,
/// przełożony je przyjmuje albo proponuje jeszcze raz.
class _PlanDialog extends ConsumerStatefulWidget {
  const _PlanDialog({
    required this.restaurantId,
    required this.member,
    required this.day,
    required this.existing,
    required this.availability,
    required this.week,
  });

  final String restaurantId;
  final StaffMember member;
  final DateTime day;
  final PlannedShift? existing;
  final List<Availability> availability;
  final DateTime week;

  @override
  ConsumerState<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends ConsumerState<_PlanDialog> {
  late TimeOfDay _starts = _parse(
    widget.existing?.starts ?? (widget.availability.isEmpty ? '10:00' : widget.availability.first.starts),
  );
  late TimeOfDay _ends = _parse(
    widget.existing?.ends ?? (widget.availability.isEmpty ? '18:00' : widget.availability.first.ends),
  );
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
    final picked = await pickTime(context, initial: start ? _starts : _ends);
    if (picked != null) setState(() => start ? _starts = picked : _ends = picked);
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(plannedShiftsProvider((restaurantId: widget.restaurantId, weekStart: widget.week)));
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose() {
    if (_ends.hour * 60 + _ends.minute <= _starts.hour * 60 + _starts.minute) {
      showMessage(context, 'Koniec musi być później niż początek.');
      return Future.value();
    }
    return _run(
      () => ref.read(repositoryProvider).planShift(
        memberId: widget.member.id,
        day: widget.day,
        starts: _fmt(_starts),
        ends: _fmt(_ends),
        note: _note.text,
      ),
      'Propozycja wysłana. ${widget.member.name.split(' ').first} zobaczy ją w aplikacji.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final existing = widget.existing;
    final repo = ref.read(repositoryProvider);
    Widget timeButton(TimeOfDay t, bool start) => OutlinedButton(
      onPressed: () => _pick(start),
      style: OutlinedButton.styleFrom(minimumSize: const Size(96, 44)),
      child: Text(_fmt(t), style: const TextStyle(fontFeatures: _tabular, fontSize: 16)),
    );

    return AlertDialog(
      title: Text(widget.member.name),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              Fmt.capitalize(Fmt.dayLong(widget.day)),
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            Text(
              widget.availability.isEmpty
                  ? 'Brak dyspozycyjności w tym dniu.'
                  : 'Dyspozycyjność: ${widget.availability.map((a) => '${a.starts}–${a.ends}').join(', ')}',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
            ),
            if (existing != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusColor(existing.status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Glyph(_statusIcon(existing.status), size: 18, color: _statusColor(existing.status)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${existing.status == PlannedShiftStatus.accepted ? 'W grafiku' : 'Twoja propozycja'}: '
                            '${existing.starts}–${existing.ends}',
                            style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                          ),
                          Text(
                            existing.status == PlannedShiftStatus.changed
                                ? 'Pracownik proponuje ${existing.changeStarts}–${existing.changeEnds}'
                                : existing.status.label,
                            style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                          ),
                          if (existing.reply != null)
                            Text('„${existing.reply}”', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (existing.status == PlannedShiftStatus.changed) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => repo.acceptShiftChange(existing.id), 'Przyjęto godziny pracownika.'),
                  icon: const Glyph(AppIcons.check, size: 18),
                  label: Text('Przyjmij ${existing.changeStarts}–${existing.changeEnds}'),
                ),
              ],
            ],
            const SizedBox(height: 16),
            Text(existing == null ? 'Zaproponuj godziny' : 'Zaproponuj inne godziny', style: text.titleSmall),
            const SizedBox(height: 8),
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
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Uwagi (opcjonalnie)', hintText: 'Na przykład: bar, zamknięcie'),
            ),
          ],
        ),
      ),
      actions: [
        if (existing != null)
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() => repo.deletePlannedShift(existing.id), 'Usunięto z grafiku.'),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Usuń z grafiku'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _busy ? null : _propose,
          child: Text(existing == null ? 'Zaproponuj' : 'Wyślij propozycję'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Dane pracownika
// ---------------------------------------------------------------

/// Dodanie albo edycja pracownika. Zwraca numer pracownika po zapisie
/// albo [deleted] po usunięciu.
class _MemberDialog extends ConsumerStatefulWidget {
  const _MemberDialog({required this.restaurantId, this.member});

  static const deleted = 'usunięty';

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
  bool _busy = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
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
      final id = await ref.read(repositoryProvider).saveStaffMember(
        restaurantId: widget.restaurantId,
        id: widget.member?.id,
        firstName: _firstName.text,
        lastName: _lastName.text,
        position: position!,
        phone: _phone.text,
        color: _color,
        active: _active,
      );
      if (mounted) Navigator.pop(context, id);
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
      message: 'Razem z pracownikiem znikną jego login, grafik i wpisy w kalendarzu. '
          'Jeśli tylko odchodzi, możesz go oznaczyć jako nieaktywnego.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteStaffMember(widget.member!.id);
      if (mounted) Navigator.pop(context, _MemberDialog.deleted);
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
              decoration: const InputDecoration(
                labelText: 'Numer telefonu',
                helperText: 'Tym numerem pracownik loguje się w aplikacji Table for employees.',
              ),
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
            Text('Kolor w grafiku', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
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
                  Expanded(child: Text('Aktywny (może się logować)', style: text.bodyMedium)),
                  Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
                ],
              ),
            ] else ...[
              const SizedBox(height: 14),
              Text(
                'Po zapisaniu pracownik dostanie login i krótkie hasło do głównego stanowiska.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
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
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _save(positions),
          child: Text(widget.member == null ? 'Dodaj' : 'Zapisz'),
        ),
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
                'Pracownik zalogowany na głównym stanowisku widzi tylko zakładki ze swoimi uprawnieniami.',
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
