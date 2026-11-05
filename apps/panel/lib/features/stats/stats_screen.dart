import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../../shared/side_panel.dart';
import 'sales_view.dart';

enum _Metric {
  covers('Goście'),
  reservations('Rezerwacje'),
  views('Wyświetlenia profilu'),
  calls('Kliknięcia „Zadzwoń”'),
  likes('Polubienia');

  const _Metric(this.label);
  final String label;

  int valueOf(DayStat s) => switch (this) {
    covers => s.covers,
    reservations => s.reservations,
    views => s.views,
    calls => s.callClicks,
    likes => s.likes,
  };

  /// Kolor slupkow, ten sam co na kaflu z ta liczba.
  Color get color => switch (this) {
    covers => TileColors.green,
    reservations => TileColors.blue,
    views => TileColors.violet,
    calls => TileColors.amber,
    likes => TileColors.rose,
  };
}

/// Rodzaje zamówień w filtrach Sprzedaży (`orders.kind`).
const _kinds = [('dine_in', 'Na miejscu'), ('delivery', 'Dostawa'), ('pickup', 'Odbiór osobisty')];

/// Statystyki (Management) w układzie jak Pracownicy (4.11.2026, prośba użytkownika; kafle zostały): po lewej
/// zwijany panel z zakładkami Sprzedaż / Rezerwacje i goście i w Sprzedaży filtrami z liczbą rachunków w okresie
/// (rodzaj zamówienia, kto otworzył rachunek; puste grupy nie filtrują), po prawej okres 7D / 30D / 90D w górnym
/// rogu, kafle i wykresy. Filtry liczy baza (`panel_sales_stats` z `p_kinds` i `p_members`).
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  int _days = 30;
  _Metric? _metric;

  /// 0: sprzedaż, 1: rezerwacje i goście.
  int _tab = 0;

  // Panel po lewej: zaznaczone filtry Sprzedaży (puste: wszystko), zwinięte grupy i zwinięcie panelu.
  final _kindFilter = <String>{};
  final _memberFilter = <String>{};
  final _closed = <String>{};
  bool _panelOpen = true;

  void _toggle(Set<String> set, String value) =>
      setState(() => set.contains(value) ? set.remove(value) : set.add(value));

  /// Zaznaczone filtry jako klucz zapytania: posortowane, po przecinku.
  static String _key(Set<String> set) => (set.toList()..sort()).join(',');

  /// Filtry Sprzedaży z liczbą rachunków w okresie (bez filtrów).
  List<Widget> _salesFilters(SalesStats? all) {
    final kinds = {for (final (kind, n) in all?.kindCounts ?? const <(String, int)>[]) kind: n};
    final members = [...?all?.memberCounts]
      // Bez przypisania na końcu, reszta po imieniu (tak przychodzi z bazy).
      ..sort((a, b) => (a.$1.isEmpty ? 1 : 0).compareTo(b.$1.isEmpty ? 1 : 0));
    return [
      FilterSection(
        title: 'Rodzaj zamówienia',
        first: true,
        open: !_closed.contains('kind'),
        onToggle: () => _toggle(_closed, 'kind'),
        options: [
          for (final (kind, label) in _kinds)
            (
              label: label,
              count: kinds[kind] ?? 0,
              checked: _kindFilter.contains(kind),
              onChanged: (_) => _toggle(_kindFilter, kind),
              dot: null,
            ),
        ],
      ),
      if (members.isNotEmpty)
        FilterSection(
          title: 'Obsługa (kto otworzył rachunek)',
          open: !_closed.contains('member'),
          onToggle: () => _toggle(_closed, 'member'),
          options: [
            for (final (id, name, n) in members)
              (
                label: name,
                count: n,
                checked: _memberFilter.contains(id),
                onChanged: (_) => _toggle(_memberFilter, id),
                dot: null,
              ),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    // Pobieramy dwa okresy: biezacy na wykres i poprzedni do porownania.
    final query = (restaurantId: restaurant.id, days: _days * 2);
    final async = ref.watch(statsProvider(query));
    final metrics = restaurant.isPro ? _Metric.values : const [_Metric.views, _Metric.calls, _Metric.likes];
    final metric = metrics.contains(_metric) ? _metric! : metrics.first;
    final sales = restaurant.isPro && _tab == 0;
    // Liczby przy filtrach: cały okres bez filtrów (to samo zapytanie co bez zaznaczonych filtrów).
    final unfiltered = sales
        ? ref.watch(salesStatsProvider((restaurantId: restaurant.id, days: _days, kinds: '', members: ''))).value
        : null;

    final panel = SidePanel(
      header: SegmentedTabs<int>(
        options: const [(0, 'Sprzedaż'), (1, 'Rezerwacje i goście')],
        selected: _tab,
        expand: true,
        onChanged: (t) => setState(() => _tab = t),
      ),
      children: sales ? _salesFilters(unfiltered) : const [],
    );

    return SidePanelLayout(
      open: _panelOpen,
      onToggle: () => setState(() => _panelOpen = !_panelOpen),
      panel: panel,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Okres w prawym górnym rogu (5.11.2026, prośba użytkownika), wspólny dla obu zakładek.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 32, 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: SegmentedTabs<int>(
                options: const [(7, '7D'), (30, '30D'), (90, '90D')],
                selected: _days,
                onChanged: (d) => setState(() => _days = d),
              ),
            ),
          ),
          Expanded(
            child: TabContent(
              tab: _tab,
              child: _tab == 0
                  ? (restaurant.isPro
                        ? SalesView(
                            query: (
                              restaurantId: restaurant.id,
                              days: _days,
                              kinds: _key(_kindFilter),
                              members: _key(_memberFilter),
                            ),
                          )
                        : const ProGate(feature: 'Sprzedaż i zamówienia'))
                  : async.when(
                      skipLoadingOnReload: true,
                      loading: () => const LoadingView(),
                      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(statsProvider(query))),
                      data: (all) {
                        final split = all.length > _days ? all.length - _days : 0;
                        final stats = all.sublist(split);
                        final earlier = all.sublist(0, split);
                        int sum(int Function(DayStat) f) => stats.fold(0, (a, s) => a + f(s));

                        // Zmiana wzgledem poprzedniego okresu tej samej dlugosci.
                        double? change(int Function(DayStat) f) {
                          if (earlier.isEmpty) return null;
                          final before = earlier.fold(0, (a, s) => a + f(s));
                          final now = sum(f);
                          if (before == 0) return now == 0 ? 0 : 100;
                          return (now - before) / before * 100;
                        }

                        final reservations = sum((s) => s.reservations);
                        // Polubienia w aplikacji Table: wszystkie na dziś i nowe w okresie.
                        final likesTotal = stats.isEmpty ? 0 : stats.last.likesTotal;
                        final likesNew = sum((s) => s.likes);
                        final noShows = sum((s) => s.noShows);
                        final noShowRate = reservations == 0 ? 0.0 : noShows / reservations * 100;

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(24, 0, 32, 32),
                          children: [
                            // Kafle równej wysokości, także gdy dłuższa nazwa zawija się do drugiej linii.
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: StatTile(
                                      label: 'Wyświetlenia profilu',
                                      value: '${sum((s) => s.views)}',
                                      icon: AppIcons.eye,
                                      color: TileColors.violet,
                                      change: change((s) => s.views),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: StatTile(
                                      label: 'Kliknięcia „Zadzwoń”',
                                      value: '${sum((s) => s.callClicks)}',
                                      icon: AppIcons.phone,
                                      color: TileColors.amber,
                                      change: change((s) => s.callClicks),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: StatTile(
                                      label: 'Polubienia',
                                      value: '$likesTotal',
                                      icon: AppIcons.heart,
                                      color: TileColors.rose,
                                      hint: '+$likesNew w tym okresie',
                                      change: change((s) => s.likes),
                                    ),
                                  ),
                                  if (restaurant.isPro) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: StatTile(
                                        label: 'Rezerwacje',
                                        value: '$reservations',
                                        icon: AppIcons.calendarCheck,
                                        color: TileColors.blue,
                                        hint: '${sum((s) => s.cancellations)} odwołanych',
                                        change: change((s) => s.reservations),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: StatTile(
                                        label: 'Goście',
                                        value: '${sum((s) => s.covers)}',
                                        icon: AppIcons.users,
                                        color: TileColors.green,
                                        accent: true,
                                        change: change((s) => s.covers),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: StatTile(
                                        label: 'Niestawiennictwa',
                                        value: '$noShows',
                                        icon: AppIcons.userMinus,
                                        color: TileColors.rose,
                                        hint: '${Fmt.rating(noShowRate)}% rezerwacji',
                                        change: change((s) => s.noShows),
                                        moreIsBetter: false,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            PanelCard(
                              title: metric.label,
                              icon: AppIcons.chartBar,
                              iconColor: metric.color,
                              trailing: SegmentedTabs<_Metric>(
                                options: [for (final m in metrics) (m, m.label)],
                                selected: metric,
                                onChanged: (m) => setState(() => _metric = m),
                              ),
                              child: SizedBox(
                                height: 320,
                                child: _BarChart(days: stats, valueOf: metric.valueOf, color: metric.color),
                              ),
                            ),
                            if (restaurant.isPro) ...[const SizedBox(height: 16), _OccasionsCard(query: query)],
                            if (!restaurant.isPro) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Statystyki rezerwacji i gości są dostępne w planie Pro.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Słupki dzienne z podpisami osi. Wartość słupka pokazuje dymek po najechaniu.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.days, required this.valueOf, required this.color});

  final List<DayStat> days;
  final int Function(DayStat) valueOf;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final values = [for (final d in days) valueOf(d)];
    final now = DateTime.now();
    bool isToday(DateTime d) => d.year == now.year && d.month == now.month && d.day == now.day;
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
                Text(
                  '$v',
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
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
                                    color: values[i] == 0
                                        ? AppColors.ring
                                        : (isToday(days[i].day) ? AppColors.accentFill : color),
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
                        child: i % labelEvery == 0 || i == days.length - 1 || isToday(days[i].day)
                            ? Text(
                                '${days[i].day.day}.${days[i].day.month.toString().padLeft(2, '0')}',
                                maxLines: 1,
                                overflow: TextOverflow.visible,
                                softWrap: false,
                                style: text.bodySmall?.copyWith(
                                  color: isToday(days[i].day) ? AppColors.accent : AppColors.textMuted,
                                  fontWeight: isToday(days[i].day) ? FontWeight.w600 : null,
                                ),
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

/// Okazje rezerwacji w wybranym okresie: urodziny, rocznice, randki...
class _OccasionsCard extends ConsumerWidget {
  const _OccasionsCard({required this.query});

  final StatsQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final stats = ref.watch(occasionStatsProvider(query)).value ?? const <OccasionStat>[];
    final top = stats.fold(0, (m, s) => math.max(m, s.reservations));

    return PanelCard(
      title: 'Okazje',
      icon: AppIcons.calendarDots,
      iconColor: TileColors.violet,
      child: stats.isEmpty
          ? Text(
              'W tym okresie żadna rezerwacja nie miała okazji.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            )
          : Column(
              children: [
                for (final s in stats)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 180, child: Text(s.occasion.label, style: text.bodyMedium)),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, c) => Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                height: 10,
                                width: math.max(6, c.maxWidth * s.reservations / top),
                                decoration: BoxDecoration(
                                  color: AppColors.accentFill,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 150,
                          child: Text(
                            '${s.reservations} rez. · ${Fmt.people(s.covers)}',
                            textAlign: TextAlign.right,
                            style: text.bodyMedium?.copyWith(
                              color: AppColors.textMuted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
