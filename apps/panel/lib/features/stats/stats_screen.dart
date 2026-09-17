import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

enum _Metric {
  covers('Goście'),
  reservations('Rezerwacje'),
  views('Wyświetlenia profilu'),
  calls('Kliknięcia „Zadzwoń”');

  const _Metric(this.label);
  final String label;

  int valueOf(DayStat s) => switch (this) {
    covers => s.covers,
    reservations => s.reservations,
    views => s.views,
    calls => s.callClicks,
  };
}

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  int _days = 30;
  _Metric? _metric;

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final query = (restaurantId: restaurant.id, days: _days);
    final async = ref.watch(statsProvider(query));
    final metrics = restaurant.isPro
        ? _Metric.values
        : const [_Metric.views, _Metric.calls];
    final metric = metrics.contains(_metric) ? _metric! : metrics.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Statystyki',
          subtitle: 'Dane z aplikacji Table. Dzień liczony według czasu lokalu.',
          actions: [
            SegmentedTabs<int>(
              options: const [(7, '7 dni'), (30, '30 dni'), (90, '90 dni')],
              selected: _days,
              onChanged: (d) => setState(() => _days = d),
            ),
          ],
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(statsProvider(query)),
            ),
            data: (stats) {
              int sum(int Function(DayStat) f) => stats.fold(0, (a, s) => a + f(s));
              final reservations = sum((s) => s.reservations);
              final noShows = sum((s) => s.noShows);
              final noShowRate = reservations == 0 ? 0.0 : noShows / reservations * 100;

              return ListView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Wyświetlenia profilu',
                          value: '${sum((s) => s.views)}',
                          icon: AppIcons.eye,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          label: 'Kliknięcia „Zadzwoń”',
                          value: '${sum((s) => s.callClicks)}',
                          icon: AppIcons.phone,
                        ),
                      ),
                      if (restaurant.isPro) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatTile(
                            label: 'Rezerwacje',
                            value: '$reservations',
                            icon: AppIcons.calendarCheck,
                            hint: '${sum((s) => s.cancellations)} odwołanych',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatTile(
                            label: 'Goście',
                            value: '${sum((s) => s.covers)}',
                            icon: AppIcons.users,
                            accent: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatTile(
                            label: 'Niestawiennictwa',
                            value: '$noShows',
                            icon: AppIcons.userMinus,
                            hint: '${Fmt.rating(noShowRate)}% rezerwacji',
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  PanelCard(
                    title: metric.label,
                    trailing: SegmentedTabs<_Metric>(
                      options: [for (final m in metrics) (m, m.label)],
                      selected: metric,
                      onChanged: (m) => setState(() => _metric = m),
                    ),
                    child: SizedBox(
                      height: 320,
                      child: _BarChart(
                        days: stats,
                        valueOf: metric.valueOf,
                      ),
                    ),
                  ),
                  if (!restaurant.isPro) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Statystyki rezerwacji i gości są dostępne w planie Pro.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Słupki dzienne z podpisami osi. Wartość słupka pokazuje dymek po najechaniu.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.days, required this.valueOf});

  final List<DayStat> days;
  final int Function(DayStat) valueOf;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final values = [for (final d in days) valueOf(d)];
    final maxValue = values.fold(0, math.max);
    final top = maxValue == 0 ? 4 : _niceCeil(maxValue);
    final labelEvery = days.length <= 7 ? 1 : (days.length <= 30 ? 5 : 15);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 36,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final v in [top, top * 3 ~/ 4, top ~/ 2, top ~/ 4, 0]) ...[
                Text('$v', style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: const [FontFeature.tabularFigures()])),
                if (v != 0) const Spacer(),
              ],
              const SizedBox(height: 22),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final gap = days.length > 60 ? 2.0 : 4.0;
                    final barWidth = math.max(2.0, (c.maxWidth - gap * (days.length - 1)) / days.length);
                    return Stack(
                      children: [
                        for (var i = 0; i <= 4; i++)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: c.maxHeight * i / 4,
                            child: Container(height: 1, color: AppColors.ring),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < days.length; i++) ...[
                              if (i > 0) SizedBox(width: gap),
                              Tooltip(
                                message: '${Fmt.capitalize(Fmt.dayShort(days[i].day))}: ${values[i]}',
                                child: Container(
                                  width: barWidth,
                                  height: math.max(2, c.maxHeight * values[i] / top),
                                  decoration: BoxDecoration(
                                    color: values[i] == 0 ? AppColors.ring : AppColors.accentFill,
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(math.min(4, barWidth / 2)),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 16,
                child: Row(
                  children: [
                    for (var i = 0; i < days.length; i++)
                      Expanded(
                        child: i % labelEvery == 0 || i == days.length - 1
                            ? Text(
                                '${days[i].day.day}.${days[i].day.month.toString().padLeft(2, '0')}',
                                maxLines: 1,
                                overflow: TextOverflow.visible,
                                softWrap: false,
                                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static int _niceCeil(int value) {
    for (final step in [4, 8, 20, 40, 80, 100, 200, 400, 800, 1000, 2000, 4000]) {
      if (value <= step) return step;
    }
    return ((value / 4000).ceil()) * 4000;
  }
}
