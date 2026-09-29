import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
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

  Future<void> _addMember(String restaurantId, {required bool withLogin}) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _MemberDialog(restaurantId: restaurantId),
    );
    if (id == null || !mounted) return;
    ref.invalidate(staffProvider(restaurantId));
    if (!withLogin) return;
    // Nowy pracownik od razu dostaje login i łatwe hasło do głównego stanowiska.
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

  Future<void> _hours(String restaurantId, StaffMember member, DateTime day, PlannedShift? existing) {
    return showDialog<void>(
      context: context,
      builder: (_) => _HoursDialog(
        restaurantId: restaurantId,
        member: member,
        day: day,
        existing: existing,
        week: _week,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    // Uprawnienia pracownika zalogowanego w tej zakładce. Każda część ma własne.
    final permissions = ref.watch(tabPermissionsProvider(PanelRoutes.staff));
    final canStaff = permissions.contains('staff');
    final canLogins = permissions.contains('staff_logins');
    final canPlan = permissions.contains('schedule');
    final canTimesheet = permissions.contains('timesheet');
    final canPositions = permissions.contains('positions');
    final tabs = [
      if (canStaff || canLogins) (0, 'Zespół'),
      if (canPlan) (1, 'Grafik'),
      if (canTimesheet) (2, 'Czas pracy'),
    ];
    if (tabs.isEmpty) {
      return const MessageView(
        icon: AppIcons.lock,
        title: 'Brak dostępu',
        message: 'Twoje stanowisko nie ma uprawnień do żadnej części zakładki „Pracownicy”.',
      );
    }
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
              if (canPositions)
                OutlinedButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => _PositionsDialog(restaurantId: restaurant.id),
                  ),
                  icon: const Glyph(AppIcons.identification, size: 18),
                  label: const Text('Stanowiska'),
                ),
              if (canStaff)
                FilledButton.icon(
                  onPressed: () => _addMember(restaurant.id, withLogin: canLogins),
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
                      ? 'Dodaj pracownika. Dostanie login i łatwe hasło do logowania na głównym stanowisku.'
                      : 'Kierownik jeszcze nie dodał pracowników.',
                  actionLabel: canStaff ? 'Dodaj pracownika' : null,
                  onAction: canStaff ? () => _addMember(restaurant.id, withLogin: canLogins) : null,
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
                  canEdit: canTimesheet,
                );
              }

              if (tab == 0) {
                return _TeamGrid(
                  restaurantId: restaurant.id,
                  members: members,
                  shifts: shifts,
                  working: working,
                  showLogins: canLogins,
                  onOpen: canStaff || canLogins ? (m) => _openMember(restaurant.id, m) : null,
                  onAdd: canStaff ? () => _addMember(restaurant.id, withLogin: canLogins) : null,
                  footer: toggleInactive,
                );
              }

              final query = (restaurantId: restaurant.id, weekStart: _week);
              final planned = ref.watch(plannedShiftsProvider(query)).value ?? const <PlannedShift>[];
              final positions = ref.watch(positionsProvider(restaurant.id)).value ?? const <StaffPosition>[];
              final waiting = planned.where((p) => p.status == PlannedShiftStatus.pending).length;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (waiting > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _Banner(
                          icon: AppIcons.clock,
                          text: waiting == 1
                              ? 'Jedno zgłoszenie czeka na decyzję. Kliknij pomarańczowy wpis, żeby je przyjąć, zmienić albo odrzucić.'
                              : 'Zgłoszenia czekające na decyzję: $waiting. Kliknij pomarańczowe wpisy, żeby je przyjąć, zmienić albo odrzucić.',
                        ),
                      ),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: _WeekGrid(
                        week: _week,
                        members: members,
                        planned: planned,
                        positionNames: {for (final p in positions) p.id: p.name},
                        onOpenMember: canStaff ? (m) => _openMember(restaurant.id, m) : null,
                        onHours: (m, day, existing) => _hours(restaurant.id, m, day, existing),
                      ),
                    ),
                    ?toggleInactive,
                    const SizedBox(height: 8),
                    const _Legend(),
                    const SizedBox(height: 8),
                    Text(
                      'Pracownicy zgłaszają w aplikacji Table for employees, od której do której mogą pracować. '
                      'Kliknij zgłoszenie, żeby je przyjąć (także ze zmienionymi godzinami) albo odrzucić. '
                      'Po decyzji pracownik nie może już zmienić tego dnia. Kliknij pusty dzień, żeby wpisać godziny samemu.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
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
        color: _pending.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _pending.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Glyph(icon, size: 18, color: _pending),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Kolor zgłoszenia, które czeka na decyzję przełożonego.
const _pending = Color(0xFFE08A1E);

Color _statusColor(PlannedShiftStatus s) => switch (s) {
  PlannedShiftStatus.accepted => AppColors.accent,
  PlannedShiftStatus.pending => _pending,
  PlannedShiftStatus.rejected => AppColors.error,
};

AppIconData _statusIcon(PlannedShiftStatus s) => switch (s) {
  PlannedShiftStatus.accepted => AppIcons.checkCircle,
  PlannedShiftStatus.pending => AppIcons.clock,
  PlannedShiftStatus.rejected => AppIcons.prohibit,
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
    required this.showLogins,
    required this.onOpen,
    required this.onAdd,
    this.footer,
  });

  final String restaurantId;
  final List<StaffMember> members;

  /// Loginy i hasła widać tylko z uprawnieniem „Loginy i hasła”.
  final bool showLogins;

  /// Zmiany z bieżącego tygodnia, do godzin na kafelkach.
  final List<StaffShift> shifts;

  /// Kto jest teraz w pracy i od kiedy.
  final Map<String, DateTime> working;
  final ValueChanged<StaffMember>? onOpen;
  final VoidCallback? onAdd;
  final Widget? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logins = showLogins
        ? ref.watch(staffLoginsProvider(restaurantId)).value ?? const <String, StaffLogin>{}
        : const <String, StaffLogin>{};
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
                  if (onAdd case final add?) SizedBox(width: width, height: 168, child: _AddTile(onTap: add)),
                  for (final m in members)
                    SizedBox(
                      width: width,
                      height: 168,
                      child: _MemberTile(
                        member: m,
                        position: positionNames[m.positionId] ?? m.position,
                        login: logins[m.id],
                        showLogin: showLogins,
                        workingSince: working[m.id],
                        week: shifts
                            .where((s) => s.memberId == m.id)
                            .fold(Duration.zero, (sum, s) => sum + s.duration),
                        onTap: onOpen == null ? null : () => onOpen!(m),
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
                'Dostanie login i łatwe hasło',
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
    required this.showLogin,
    required this.workingSince,
    required this.week,
    required this.onTap,
  });

  final StaffMember member;
  final String? position;
  final StaffLogin? login;
  final bool showLogin;
  final DateTime? workingSince;
  final Duration week;
  final VoidCallback? onTap;

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
              if (showLogin) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Glyph(
                      login == null ? AppIcons.warning : AppIcons.password,
                      size: 14,
                      color: login == null ? _pending : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        login == null
                            ? 'Bez loginu do stanowiska'
                            : '${login!.login} · hasło: ${login!.password ?? 'nadaj nowe'}'
                                  '${login!.locked ? ' · zablokowany' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: login == null ? _pending : AppColors.textMuted,
                          fontFeatures: _tabular,
                        ),
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

  Future<void> _password(StaffMember member, StaffLogin? login) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PasswordDialog(member: member, login: login),
    );
    if (saved == true) ref.invalidate(staffLoginsProvider(widget.restaurantId));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final members = ref.watch(staffProvider(widget.restaurantId)).value;
    final member = members?.where((m) => m.id == widget.member.id).firstOrNull ?? widget.member;
    final permissions = ref.watch(tabPermissionsProvider(PanelRoutes.staff));
    final canLogins = permissions.contains('staff_logins');
    final canStats = permissions.contains('staff');
    final logins = canLogins ? ref.watch(staffLoginsProvider(widget.restaurantId)).value : null;
    final login = logins?[member.id];
    final positions = ref.watch(positionsProvider(widget.restaurantId)).value ?? const <StaffPosition>[];
    final position = positions.where((p) => p.id == member.positionId).firstOrNull;
    final statsAsync = canStats
        ? ref.watch(memberStatsProvider((memberId: member.id, days: _days)))
        : const AsyncValue<MemberStats>.loading();
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
                  if (canStats)
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
              // Login i hasło do głównego stanowiska: widać je stale (uprawnienie „Loginy i hasła”).
              if (canLogins)
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
                          if (login == null)
                            Text('Brak loginu do stanowiska', style: text.titleMedium)
                          else
                            SelectableText.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: 'Login: ', style: TextStyle(color: AppColors.textMuted)),
                                  TextSpan(text: login.login),
                                  TextSpan(text: '   Hasło: ', style: TextStyle(color: AppColors.textMuted)),
                                  TextSpan(text: login.password ?? '(nieznane)'),
                                ],
                              ),
                              style: text.titleMedium?.copyWith(fontFeatures: _tabular),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            login == null
                                ? 'Utwórz login i hasło, żeby pracownik mógł się logować na głównym stanowisku.'
                                : login.locked
                                ? 'Zablokowany po kilku błędnych hasłach. Zmiana hasła zdejmuje blokadę.'
                                : login.password == null
                                ? 'Hasło założone przed zmianą nie jest znane. Zmień je, żeby było widać.'
                                : 'Tym loginem i hasłem pracownik loguje się na głównym stanowisku.',
                            style: text.bodySmall?.copyWith(
                              color: login?.locked ?? false ? AppColors.error : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: () => _password(member, login),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                      child: Text(login == null ? 'Utwórz login' : 'Zmień hasło'),
                    ),
                  ],
                ),
              ),
              if (canStats) ...[
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
                                ? 'Brak przyjętych godzin od dziś.'
                                : 'Przyjęte dni od dziś: ${stats.planned}.',
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

/// Login i hasło nowego pracownika, do przekazania mu od razu.
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
              'i w zakładkach). Login i hasło widać też w szczegółach pracownika i w jego aplikacji.',
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
    required this.planned,
    required this.positionNames,
    required this.onOpenMember,
    required this.onHours,
  });

  final DateTime week;
  final List<StaffMember> members;
  final List<PlannedShift> planned;

  /// Aktualne nazwy stanowisk po identyfikatorze. Po zmianie nazwy stanowiska
  /// lista pokazuje nową, a nie tę zapisaną przy pracowniku.
  final Map<String, String> positionNames;
  final ValueChanged<StaffMember>? onOpenMember;
  final void Function(StaffMember member, DateTime day, PlannedShift? existing) onHours;

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
                      entry: planned.where((p) => p.memberId == m.id && dateOnly(p.day) == day).firstOrNull,
                      isToday: day == today,
                      onTap: (existing) => onHours(m, day, existing),
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
                child: Text('Przyjętych osób', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
              ),
            ),
            for (final day in days)
              Expanded(
                child: Text(
                  '${planned.where((p) => dateOnly(p.day) == day && p.status == PlannedShiftStatus.accepted && members.any((m) => m.id == p.memberId)).length}',
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

/// Dzień pracownika w grafiku: zgłoszenie (pomarańczowe), przyjęte (w kolorze pracownika)
/// albo odrzucone (przekreślone).
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.member,
    required this.entry,
    required this.isToday,
    required this.onTap,
  });

  final StaffMember member;
  final PlannedShift? entry;
  final bool isToday;
  final ValueChanged<PlannedShift?> onTap;

  @override
  Widget build(BuildContext context) {
    final color = staffColors[member.color % staffColors.length];
    final text = Theme.of(context).textTheme;
    final e = entry;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.ring)),
        color: isToday ? AppColors.accentTint.withValues(alpha: 0.18) : null,
      ),
      child: InkWell(
        onTap: () => onTap(e),
        hoverColor: AppColors.ring,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: e == null
              ? Center(child: Glyph(AppIcons.plus, size: 14, color: AppColors.textDisabled))
              : Tooltip(
                  message: [
                    e.status.label,
                    if (e.changed) 'Zgłoszone: ${e.requestedStarts}–${e.requestedEnds}',
                    if (e.note != null) 'Pracownik: ${e.note}',
                    if (e.answer != null) 'Odpowiedź: ${e.answer}',
                  ].join('\n'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: switch (e.status) {
                        PlannedShiftStatus.accepted => color.withValues(alpha: 0.9),
                        PlannedShiftStatus.pending => _pending.withValues(alpha: 0.16),
                        PlannedShiftStatus.rejected => Colors.transparent,
                      },
                      borderRadius: BorderRadius.circular(8),
                      border: switch (e.status) {
                        PlannedShiftStatus.accepted => null,
                        PlannedShiftStatus.pending => Border.all(color: _pending),
                        PlannedShiftStatus.rejected => Border.all(color: AppColors.ring),
                      },
                    ),
                    child: Row(
                      children: [
                        Glyph(
                          _statusIcon(e.status),
                          size: 13,
                          color: e.status == PlannedShiftStatus.accepted ? Colors.white : _statusColor(e.status),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '${e.starts}–${e.ends}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelMedium?.copyWith(
                              fontFeatures: _tabular,
                              fontWeight: FontWeight.w600,
                              color: switch (e.status) {
                                PlannedShiftStatus.accepted => Colors.white,
                                PlannedShiftStatus.pending => AppColors.text,
                                PlannedShiftStatus.rejected => AppColors.textMuted,
                              },
                              decoration: e.status == PlannedShiftStatus.rejected ? TextDecoration.lineThrough : null,
                            ),
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

/// Decyzja o zgłoszeniu pracownika (przyjmij, przyjmij ze zmienionymi godzinami, odrzuć)
/// albo godziny wpisane przez przełożonego na pusty dzień.
class _HoursDialog extends ConsumerStatefulWidget {
  const _HoursDialog({
    required this.restaurantId,
    required this.member,
    required this.day,
    required this.existing,
    required this.week,
  });

  final String restaurantId;
  final StaffMember member;
  final DateTime day;
  final PlannedShift? existing;
  final DateTime week;

  @override
  ConsumerState<_HoursDialog> createState() => _HoursDialogState();
}

class _HoursDialogState extends ConsumerState<_HoursDialog> {
  late TimeOfDay _starts = _parse(widget.existing?.starts ?? '10:00');
  late TimeOfDay _ends = _parse(widget.existing?.ends ?? '18:00');
  late final _answer = TextEditingController(text: widget.existing?.answer ?? '');
  bool _busy = false;

  static TimeOfDay _parse(String hm) {
    final p = hm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static String _fmt(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  bool get _validTimes => _ends.hour * 60 + _ends.minute > _starts.hour * 60 + _starts.minute;

  @override
  void dispose() {
    _answer.dispose();
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

  void _accept() {
    if (!_validTimes) {
      showMessage(context, 'Koniec musi być później niż początek.');
      return;
    }
    final repo = ref.read(repositoryProvider);
    final existing = widget.existing;
    final first = widget.member.name.split(' ').first;
    if (existing == null) {
      _run(
        () => repo.addHours(
          memberId: widget.member.id,
          day: widget.day,
          starts: _fmt(_starts),
          ends: _fmt(_ends),
          answer: _answer.text,
        ),
        'Godziny dodane do grafiku. $first zobaczy je w aplikacji.',
      );
    } else {
      _run(
        () => repo.decideHours(existing.id, accept: true, starts: _fmt(_starts), ends: _fmt(_ends), answer: _answer.text),
        'Przyjęto ${_fmt(_starts)}–${_fmt(_ends)}. $first zobaczy to w aplikacji.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final existing = widget.existing;
    final repo = ref.read(repositoryProvider);
    final changedHours = existing?.requestedStarts != null &&
        (existing!.requestedStarts != _fmt(_starts) || existing.requestedEnds != _fmt(_ends));
    Widget timeButton(TimeOfDay t, bool start) => OutlinedButton(
      onPressed: () => _pick(start),
      style: OutlinedButton.styleFrom(minimumSize: const Size(96, 44)),
      child: Text(_fmt(t), style: const TextStyle(fontFeatures: _tabular, fontSize: 16)),
    );

    return AlertDialog(
      title: Text(widget.member.name),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              Fmt.capitalize(Fmt.dayLong(widget.day)),
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (existing != null)
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
                            existing.requestedStarts == null
                                ? '${existing.status.label}: ${existing.starts}–${existing.ends} (wpisane przez przełożonego)'
                                : 'Pracownik zgłosił ${existing.requestedStarts}–${existing.requestedEnds}',
                            style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                          ),
                          if (existing.requestedStarts != null)
                            Text(
                              existing.status == PlannedShiftStatus.accepted
                                  ? 'Przyjęte: ${existing.starts}–${existing.ends}'
                                  : existing.status.label,
                              style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                            ),
                          if (existing.note != null)
                            Text('„${existing.note}”', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                'Pracownik nie zgłosił godzin na ten dzień. Możesz wpisać je sam, będą od razu przyjęte.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            const SizedBox(height: 16),
            Text(existing == null ? 'Godziny' : 'Godziny do przyjęcia (możesz je zmienić)', style: text.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                timeButton(_starts, true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('–', style: text.titleMedium),
                ),
                timeButton(_ends, false),
                if (changedHours) ...[
                  const SizedBox(width: 12),
                  const Flexible(child: Tag('ZMIENIONE', color: _pending)),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _answer,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Wiadomość dla pracownika (opcjonalnie)',
                hintText: 'Na przykład: potrzebuję Cię od 12',
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (existing != null) ...[
          TextButton(
            onPressed: _busy ? null : () => _run(() => repo.deleteHours(existing.id), 'Usunięto z grafiku.'),
            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
            child: const Text('Usuń'),
          ),
          if (existing.status != PlannedShiftStatus.rejected)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => repo.decideHours(existing.id, accept: false, answer: _answer.text),
                      'Godziny odrzucone.',
                    ),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Odrzuć'),
            ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _busy ? null : _accept,
          child: Text(existing == null ? 'Dodaj' : (changedHours ? 'Przyjmij zmienione' : 'Przyjmij')),
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
                'Po zapisaniu pracownik dostanie login i łatwe hasło do głównego stanowiska.',
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
                'Pracownik zaloguje się tylko do zakładek, do których ma uprawnienia, i zobaczy tylko dozwolone przyciski.',
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
              Text(
                'Pracownik widzi i otwiera tylko te zakładki i przyciski, do których ma uprawnienia.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              for (final p in StaffPermission.values) ...[
                if (p == StaffPermission.values.first || p.group != StaffPermission.values[p.index - 1].group)
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 2),
                    child: Text(
                      p.group.toUpperCase(),
                      style: text.labelSmall?.copyWith(
                        color: AppColors.textDisabled,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
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

/// Login i hasło pracownika: własne hasło albo wylosowane łatwe („kawa47”).
class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog({required this.member, required this.login});

  final StaffMember member;
  final StaffLogin? login;

  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save({required bool random}) async {
    final typed = _password.text.trim().toLowerCase();
    if (!random && !RegExp(r'^[a-z0-9]{4,20}$').hasMatch(typed)) {
      setState(() => _problem = 'Od 4 do 20 znaków: litery bez polskich znaków i cyfry.');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      final password = random ? null : typed;
      final String shown;
      if (widget.login == null) {
        final created = await repo.createStaffLogin(widget.member.id, password: password);
        shown = '${created.login}, hasło ${created.password}';
      } else {
        shown = 'nowe hasło ${await repo.setStaffPassword(widget.member.id, password: password)}';
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      showMessage(context, '${widget.member.name}: $shown.');
    } catch (e) {
      if (mounted) setState(() => _problem = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final login = widget.login;
    return AlertDialog(
      title: Text(login == null ? 'Login dla: ${widget.member.name}' : 'Hasło: ${widget.member.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              login == null
                  ? 'Login powstanie z imienia i nazwiska. Hasło wpisz sam albo wylosuj łatwe, np. „kawa47”.'
                  : 'Login: ${login.login}. Wpisz nowe hasło albo wylosuj łatwe, np. „kawa47”. Stare przestanie działać.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 20,
              decoration: InputDecoration(
                labelText: 'Hasło',
                hintText: 'np. anna2024',
                counterText: '',
                errorText: _problem,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _save(random: false),
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
        OutlinedButton(
          onPressed: _busy ? null : () => _save(random: true),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Wylosuj łatwe'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _save(random: false),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Zapisz hasło'),
        ),
      ],
    );
  }
}
