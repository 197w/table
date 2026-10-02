import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

String _two(int n) => n.toString().padLeft(2, '0');

/// Godziny jako „37:45”.
String _hours(int seconds) => '${seconds ~/ 3600}:${_two(seconds % 3600 ~/ 60)}';

/// Statystyki zespołu (grupa Pracownicy): godziny, zmiany, rachunki, sprzedaż, pozycje i kursy na osobę
/// z ostatnich 7, 30 albo 90 dni. Uprawnienie „Statystyki”.
class TeamStatsScreen extends ConsumerStatefulWidget {
  const TeamStatsScreen({super.key});

  @override
  ConsumerState<TeamStatsScreen> createState() => _TeamStatsScreenState();
}

class _TeamStatsScreenState extends ConsumerState<TeamStatsScreen> {
  var _days = 30;

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final query = (restaurantId: restaurant.id, days: _days);
    final async = ref.watch(teamStatsProvider(query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
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
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(teamStatsProvider(query))),
            data: (all) {
              final people = [for (final s in all) if (s.active || s.hasActivity) s];
              if (people.isEmpty) {
                return const MessageView(
                  icon: AppIcons.chartBarHorizontal,
                  title: 'Brak danych',
                  message: 'Statystyki pojawią się po pierwszych zmianach zespołu.',
                );
              }
              final seconds = people.fold(0, (sum, s) => sum + s.seconds);
              final revenue = people.fold(0, (sum, s) => sum + s.revenueGrosze);
              final closed = people.fold(0, (sum, s) => sum + s.ordersClosed);
              final deliveries = people.fold(0, (sum, s) => sum + s.deliveries);
              final best = people.fold(0, (m, s) => s.revenueGrosze > m ? s.revenueGrosze : m);

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: 'Godziny pracy',
                            value: '${_hours(seconds)} h',
                            icon: AppIcons.clock,
                            color: TileColors.blue,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: StatTile(
                            label: 'Sprzedaż zespołu',
                            value: Fmt.price(revenue),
                            icon: AppIcons.money,
                            color: TileColors.green,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: StatTile(
                            label: 'Zamknięte rachunki',
                            value: '$closed',
                            icon: AppIcons.receipt,
                            color: TileColors.violet,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: StatTile(
                            label: 'Kursy dostaw',
                            value: '$deliveries',
                            icon: AppIcons.moped,
                            color: TileColors.amber,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _HeaderRow(),
                          Divider(height: 1, color: AppColors.ring),
                          for (final (i, s) in people.indexed) ...[
                            if (i > 0) Divider(height: 1, color: AppColors.ring),
                            _MemberRow(stat: s, best: best),
                          ],
                        ],
                      ),
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

const _column = 112.0;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted);
    Widget cell(String label) => SizedBox(width: _column, child: Text(label, textAlign: TextAlign.end, style: style));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Expanded(child: Text('Pracownik', style: style)),
          cell('Godziny'),
          cell('Zmiany'),
          cell('Rachunki'),
          cell('Pozycje'),
          cell('Kursy'),
          SizedBox(width: _column + 60, child: Text('Sprzedaż', textAlign: TextAlign.end, style: style)),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.stat, required this.best});

  final TeamStat stat;

  /// Najwyższa sprzedaż w zespole, do paska porównania.
  final int best;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = stat;
    final value = text.bodyLarge?.copyWith(fontFeatures: _tabular);
    Widget cell(String label, {bool muted = false}) => SizedBox(
      width: _column,
      child: Text(label, textAlign: TextAlign.end, style: value?.copyWith(color: muted ? AppColors.textMuted : null)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                Text(
                  [?s.position, if (!s.active) 'nieaktywny'].join(' · '),
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          cell(s.seconds == 0 ? '—' : '${_hours(s.seconds)} h', muted: s.seconds == 0),
          cell('${s.shifts}', muted: s.shifts == 0),
          cell('${s.ordersClosed}', muted: s.ordersClosed == 0),
          cell('${s.items}', muted: s.items == 0),
          cell('${s.deliveries}', muted: s.deliveries == 0),
          SizedBox(
            width: _column + 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  s.revenueGrosze == 0 ? '—' : Fmt.price(s.revenueGrosze),
                  style: value?.copyWith(color: s.revenueGrosze == 0 ? AppColors.textMuted : null),
                ),
                if (best > 0) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      width: _column,
                      height: 5,
                      child: LinearProgressIndicator(
                        value: s.revenueGrosze / best,
                        backgroundColor: AppColors.surfaceRaised,
                        color: AppColors.accentFill,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
