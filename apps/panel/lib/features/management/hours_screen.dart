import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../../shared/side_panel.dart';
import '../staff/timesheet.dart';

DateTime _weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// Management → Godziny pracy w układzie jak Pracownicy (24.11.2026, prośba użytkownika): po lewej panel z tytułem
/// i przełącznikiem Miesiąc / Tydzień, wyszukiwaniem, wyborem okresu, „Dopisz zmianę” i filtrami (pracownik,
/// poprawione, trwające), po prawej tabela godzin. Zmiany poprawia się co do minuty; poprawione są żółte, z godzinami
/// sprzed poprawki i różnicą. Uprawnienie „Czas pracy”.
class HoursScreen extends ConsumerStatefulWidget {
  const HoursScreen({super.key});

  @override
  ConsumerState<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends ConsumerState<HoursScreen> {
  bool _monthView = true;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _week = _weekStart(DateTime.now());
  final _search = TextEditingController();
  final _people = <String>{};
  final _only = <String>{};
  final _closed = <String>{};
  bool _panelOpen = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle<T>(Set<T> set, T value) => setState(() => set.contains(value) ? set.remove(value) : set.add(value));

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final canEdit = ref.watch(memberPermissionsProvider).contains('timesheet');
    final staffAsync = ref.watch(staffProvider(restaurant.id));
    final all = staffAsync.value ?? const <StaffMember>[];
    final thisWeek = _weekStart(DateTime.now());
    final thisMonth = DateTime(DateTime.now().year, DateTime.now().month);
    final weekEnd = DateTime(_week.year, _week.month, _week.day + 6);

    // Zmiany okresu: potrzebne do liczb w filtrach i do „Poprawione” oraz „Trwają teraz”.
    final from = _monthView ? _month : _week;
    final to = _monthView ? DateTime(_month.year, _month.month + 1) : _week.add(const Duration(days: 7));
    final shifts = ref.watch(shiftsProvider((restaurantId: restaurant.id, from: from, to: to))).value ?? const <StaffShift>[];
    final inPeriod = [
      for (final s in shifts)
        if (s.isOpen || (!s.startedAt.isBefore(from) && s.startedAt.isBefore(to))) s,
    ];
    int count(String memberId) => inPeriod.where((s) => s.memberId == memberId).length;
    final editedIds = {for (final s in inPeriod) if (s.isEdited) s.memberId};
    final openIds = {for (final s in inPeriod) if (s.isOpen) s.memberId};

    final query = _search.text.trim().toLowerCase();
    final members = [
      for (final m in all)
        if ((query.isEmpty || m.name.toLowerCase().contains(query)) &&
            (_people.isEmpty || _people.contains(m.id)) &&
            (!_only.contains('edited') || editedIds.contains(m.id)) &&
            (!_only.contains('open') || openIds.contains(m.id)))
          m,
    ];

    final panel = SidePanel(
      header: SegmentedTabs<bool>(
        options: const [(true, 'Miesiąc'), (false, 'Tydzień')],
        icons: const [AppIcons.calendar, AppIcons.calendarDots],
        selected: _monthView,
        expand: true,
        onChanged: (v) => setState(() => _monthView = v),
      ),
      search: _search,
      searchHint: 'Szukaj pracownika',
      onSearch: () => setState(() {}),
      actions: [
        if (_monthView)
          StepSwitcher(
            label: Fmt.monthYear(_month),
            expand: true,
            previousTooltip: 'Poprzedni miesiąc',
            nextTooltip: 'Następny miesiąc',
            onPrevious: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
            onNext: _month == thisMonth ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            resetTooltip: 'Wróć do tego miesiąca',
            onReset: _month == thisMonth ? null : () => setState(() => _month = thisMonth),
          )
        else
          StepSwitcher(
            label: weekLabel(_week, weekEnd),
            expand: true,
            previousTooltip: 'Poprzedni tydzień',
            nextTooltip: 'Następny tydzień',
            onPrevious: () => setState(() => _week = DateTime(_week.year, _week.month, _week.day - 7)),
            onNext: _week == thisWeek
                ? null
                : () => setState(() => _week = DateTime(_week.year, _week.month, _week.day + 7)),
            resetTooltip: 'Wróć do tego tygodnia',
            onReset: _week == thisWeek ? null : () => setState(() => _week = thisWeek),
          ),
        if (canEdit && all.isNotEmpty)
          PanelAction(label: 'Dopisz zmianę', onTap: () => openShiftDialog(context, all)),
      ],
      children: [
        if (all.isNotEmpty) ...[
          FilterSection(
            title: 'Pracownik',
            first: true,
            open: !_closed.contains('people'),
            onToggle: () => _toggle(_closed, 'people'),
            options: [
              for (final m in all)
                (
                  label: m.name,
                  count: count(m.id),
                  checked: _people.contains(m.id),
                  onChanged: (_) => _toggle(_people, m.id),
                  dot: m.active ? null : AppColors.textDisabled,
                ),
            ],
          ),
          FilterSection(
            title: 'Zmiany',
            open: !_closed.contains('shifts'),
            onToggle: () => _toggle(_closed, 'shifts'),
            options: [
              (
                label: 'Poprawione',
                count: inPeriod.where((s) => s.isEdited).length,
                checked: _only.contains('edited'),
                onChanged: (_) => _toggle(_only, 'edited'),
                dot: editedColor,
              ),
              (
                label: 'Trwają teraz',
                count: inPeriod.where((s) => s.isOpen).length,
                checked: _only.contains('open'),
                onChanged: (_) => _toggle(_only, 'open'),
                dot: const Color(0xFF2FB673),
              ),
            ],
          ),
        ],
      ],
    );

    final content = staffAsync.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(staffProvider(restaurant.id))),
      data: (_) => all.isEmpty
          ? const MessageView(
              icon: AppIcons.users,
              title: 'Brak pracowników',
              message: 'Pracowników dodaje się w zakładce „Pracownicy”.',
            )
          : TabContent(
              tab: _monthView,
              child: _monthView
                  ? MonthHours(restaurantId: restaurant.id, month: _month, members: members, canEdit: canEdit)
                  : Timesheet(restaurantId: restaurant.id, week: _week, members: members, canEdit: canEdit),
            ),
    );

    return SidePanelLayout(
      open: _panelOpen,
      onToggle: () => setState(() => _panelOpen = !_panelOpen),
      panel: panel,
      content: content,
    );
  }
}
