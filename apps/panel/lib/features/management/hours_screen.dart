import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../staff/timesheet.dart';

DateTime _weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// Management → Godziny pracy: suma godzin każdego pracownika w miesiącu albo tydzień dzień po dniu.
/// Zmiany poprawia się co do minuty; poprawione są żółte, z godzinami sprzed poprawki i różnicą.
/// Uprawnienie „Czas pracy”.
class HoursScreen extends ConsumerStatefulWidget {
  const HoursScreen({super.key});

  @override
  ConsumerState<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends ConsumerState<HoursScreen> {
  bool _monthView = true;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _week = _weekStart(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final canEdit = ref.watch(memberPermissionsProvider).contains('timesheet');
    final staffAsync = ref.watch(staffProvider(restaurant.id));
    final members = staffAsync.value ?? const <StaffMember>[];
    final thisWeek = _weekStart(DateTime.now());
    final weekEnd = DateTime(_week.year, _week.month, _week.day + 6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          below: Row(
            children: [
              SegmentedTabs<bool>(
                options: const [(true, 'Miesiąc'), (false, 'Tydzień')],
                selected: _monthView,
                onChanged: (v) => setState(() => _monthView = v),
              ),
              const Spacer(),
              if (_monthView)
                MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m))
              else
                StepSwitcher(
                  label: weekLabel(_week, weekEnd),
                  labelWidth: 132,
                  previousTooltip: 'Poprzedni tydzień',
                  nextTooltip: 'Następny tydzień',
                  onPrevious: () => setState(() => _week = DateTime(_week.year, _week.month, _week.day - 7)),
                  onNext: _week == thisWeek
                      ? null
                      : () => setState(() => _week = DateTime(_week.year, _week.month, _week.day + 7)),
                  resetTooltip: 'Wróć do tego tygodnia',
                  onReset: _week == thisWeek ? null : () => setState(() => _week = thisWeek),
                ),
            ],
          ),
          actions: [
            if (canEdit && members.isNotEmpty)
              FilledButton.icon(
                onPressed: () => openShiftDialog(context, members),
                icon: const Glyph(AppIcons.plus, size: 18),
                label: const Text('Dopisz zmianę'),
              ),
          ],
        ),
        Expanded(
          child: TabContent(
            tab: _monthView,
            child: staffAsync.when(
              skipLoadingOnReload: true,
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(staffProvider(restaurant.id))),
              data: (all) => all.isEmpty
                  ? const MessageView(
                      icon: AppIcons.users,
                      title: 'Brak pracowników',
                      message: 'Pracowników dodaje się w zakładce „Pracownicy”.',
                    )
                  : _monthView
                  ? MonthHours(restaurantId: restaurant.id, month: _month, members: all, canEdit: canEdit)
                  : Timesheet(restaurantId: restaurant.id, week: _week, members: all, canEdit: canEdit),
            ),
          ),
        ),
      ],
    );
  }
}
