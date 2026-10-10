import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];
const _weekdays = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];

/// Zmiana w procentach względem poprzedniego okresu. Null, gdy nie ma z czym porównać.
double? _change(int now, int before) {
  if (before == 0) return now == 0 ? null : 100;
  return (now - before) / before * 100;
}

String _duration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Zaokrąglona kwota bez groszy, np. „1 240 zł”, do osi i podpisów wykresów.
String _money(int grosze) {
  final zl = (grosze / 100).round();
  final digits = zl.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '$buffer zł';
}

/// Sprzedaż z rachunków zamkniętych w panelu: obrót, pory dnia, dania, płatności i obsługa.
class SalesView extends ConsumerWidget {
  const SalesView({super.key, required this.restaurantId, required this.days});

  final String restaurantId;
  final int days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (restaurantId: restaurantId, days: days);
    final async = ref.watch(salesStatsProvider(query));
    final text = Theme.of(context).textTheme;

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(salesStatsProvider(query))),
      data: (s) {
        if (s.orders == 0 && s.prevOrders == 0) {
          return const MessageView(
            icon: AppIcons.receipt,
            title: 'Brak sprzedaży w tym okresie',
            message: 'Statystyki sprzedaży liczą się z rachunków zamkniętych w zakładce „Zamówienia”.',
          );
        }
        final prevAverage = s.prevOrders == 0 ? 0 : s.prevRevenue ~/ s.prevOrders;

        return ListView(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Obrót',
                    value: _money(s.revenue),
                    icon: AppIcons.receipt,
                    color: TileColors.green,
                    accent: true,
                    hint: s.giftCards > 0 ? 'w tym ${_money(s.giftCards)} z kart podarunkowych' : null,
                    change: _change(s.revenue, s.prevRevenue),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    label: 'Rachunki',
                    value: '${s.orders}',
                    icon: AppIcons.checkCircle,
                    color: TileColors.blue,
                    hint: s.cancelled > 0 ? '${s.cancelled} anulowanych' : null,
                    change: _change(s.orders, s.prevOrders),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    label: 'Średni rachunek',
                    value: Fmt.price(s.averageCheck),
                    icon: AppIcons.chartBar,
                    color: TileColors.violet,
                    change: _change(s.averageCheck, prevAverage),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    label: 'Sprzedane pozycje',
                    value: '${s.items}',
                    icon: AppIcons.forkKnife,
                    color: TileColors.amber,
                    hint: s.orders == 0 ? null : '${Fmt.rating(s.items / s.orders)} na rachunek',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    label: 'Czas przy stoliku',
                    value: s.avgTableMinutes == null ? '—' : '${s.avgTableMinutes} min',
                    icon: AppIcons.clock,
                    color: TileColors.blue,
                    hint: s.kitchenSeconds == null ? null : 'kuchnia średnio ${_duration(s.kitchenSeconds!)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PanelCard(
              title: 'Obrót dzień po dniu',
              icon: AppIcons.chartBar,
              iconColor: TileColors.green,
              child: SizedBox(
                height: 260,
                child: _Bars(
                  values: [for (final d in s.daily) d.$2],
                  labels: [for (final d in s.daily) '${d.$1.day}.${d.$1.month.toString().padLeft(2, '0')}'],
                  tooltips: [
                    for (final d in s.daily)
                      '${Fmt.capitalize(Fmt.dayShort(d.$1))}: ${Fmt.price(d.$2)} · ${d.$3} rach.',
                  ],
                  color: TileColors.green,
                  labelEvery: s.daily.length <= 7 ? 1 : (s.daily.length <= 31 ? 5 : 15),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Karty w rzędzie wyrównane do góry. Bez IntrinsicHeight, bo wykresy mierzą się same (LayoutBuilder).
            Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: PanelCard(
                      title: 'Pora dnia (otwarcie rachunku)',
                      icon: AppIcons.clock,
                      iconColor: TileColors.blue,
                      child: SizedBox(
                        height: 200,
                        child: _Bars(
                          values: [for (final h in s.hourly) h.revenue],
                          labels: [for (final h in s.hourly) '${h.key}'],
                          tooltips: [
                            for (final h in s.hourly)
                              '${h.key}:00–${h.key + 1}:00: ${Fmt.price(h.revenue)} · ${h.orders} rach.',
                          ],
                          color: TileColors.blue,
                          labelEvery: 3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: PanelCard(
                      title: 'Dzień tygodnia',
                      icon: AppIcons.calendarDots,
                      iconColor: TileColors.violet,
                      child: SizedBox(
                        height: 200,
                        child: _Bars(
                          values: [for (final w in s.weekdays) w.revenue],
                          labels: [for (final w in s.weekdays) _weekdays[(w.key - 1).clamp(0, 6)]],
                          tooltips: [
                            for (final w in s.weekdays)
                              '${_weekdays[(w.key - 1).clamp(0, 6)]}: ${Fmt.price(w.revenue)} · ${w.orders} rach.',
                          ],
                          color: TileColors.violet,
                          labelEvery: 1,
                        ),
                      ),
                    ),
                  ),
                ],
            ),
            const SizedBox(height: 16),
            _HourlyTable(hours: s.hourly),
            const SizedBox(height: 16),
            // Karty w rzędzie wyrównane do góry. Bez IntrinsicHeight, bo wykresy mierzą się same (LayoutBuilder).
            Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PanelCard(
                      title: 'Najczęściej zamawiane',
                      icon: AppIcons.forkKnife,
                      iconColor: TileColors.amber,
                      child: s.topItems.isEmpty
                          ? _empty(text)
                          : Column(
                              children: [
                                for (final (i, t) in s.topItems.indexed)
                                  _Meter(
                                    label: '${i + 1}. ${t.$1}',
                                    value: t.$2,
                                    max: s.topItems.first.$2,
                                    trailing: '${t.$2} szt. · ${_money(t.$3)}',
                                    color: TileColors.amber,
                                  ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PanelCard(
                          title: 'Płatności',
                          icon: AppIcons.receipt,
                          iconColor: TileColors.green,
                          child: s.payments.isEmpty
                              ? _empty(text)
                              : Column(
                                  children: [
                                    for (final p in s.payments)
                                      _Meter(
                                        label: p.$1?.label ?? 'Inne',
                                        value: p.$2,
                                        max: s.payments.map((x) => x.$2).fold(1, math.max),
                                        trailing:
                                            '${_money(p.$2)} · ${s.revenue == 0 ? 0 : (p.$2 * 100 / s.revenue).round()}%',
                                        color: TileColors.green,
                                      ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 16),
                        PanelCard(
                          title: 'Obsługa (kto otworzył rachunek)',
                          icon: AppIcons.users,
                          iconColor: TileColors.blue,
                          child: s.staff.isEmpty
                              ? _empty(text)
                              : Column(
                                  children: [
                                    for (final w in s.staff)
                                      _Meter(
                                        label: w.$1,
                                        value: w.$2,
                                        max: s.staff.map((x) => x.$2).fold(1, math.max),
                                        trailing: '${_money(w.$2)} · ${w.$3} rach.',
                                        color: TileColors.blue,
                                      ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 16),
                        PanelCard(
                          title: 'VAT w sprzedaży',
                          icon: AppIcons.list,
                          iconColor: TileColors.violet,
                          child: s.vat.isEmpty
                              ? _empty(text)
                              : Column(
                                  children: [
                                    for (final v in s.vat)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(
                                          children: [
                                            SizedBox(width: 80, child: Text('${v.$1}%', style: text.labelLarge)),
                                            Expanded(
                                              child: Text(
                                                'brutto ${Fmt.price(v.$2)}',
                                                style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                                              ),
                                            ),
                                            Text(
                                              'VAT ${Fmt.price((v.$2 * v.$1 / (100 + v.$1)).round())}',
                                              style: text.bodyMedium?.copyWith(
                                                color: AppColors.textMuted,
                                                fontFeatures: _tabular,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
            ),
          ],
        );
      },
    );
  }

  static Widget _empty(TextTheme text) => Text(
    'Brak danych w tym okresie.',
    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
  );
}

/// Poziomy pasek z podpisem i wartością, np. danie i liczba sprzedanych sztuk.
class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.value,
    required this.max,
    required this.trailing,
    required this.color,
  });

  final String label;
  final int value;
  final int max;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 190,
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 10,
                  width: math.max(6, c.maxWidth * value / (max == 0 ? 1 : max)),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: Text(
              trailing,
              textAlign: TextAlign.right,
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
            ),
          ),
        ],
      ),
    );
  }
}

/// Słupki pionowe z podpisami pod spodem i dymkiem po najechaniu.
class _Bars extends StatelessWidget {
  const _Bars({
    required this.values,
    required this.labels,
    required this.tooltips,
    required this.color,
    required this.labelEvery,
  });

  final List<int> values;
  final List<String> labels;
  final List<String> tooltips;
  final Color color;
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final top = math.max(1, values.fold(0, math.max));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 64,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_money(top), style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              const Spacer(),
              Text(_money(top ~/ 2), style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              const Spacer(),
              Text('0', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
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
                    final gap = values.length > 40 ? 2.0 : 4.0;
                    final width = math.max(2.0, (c.maxWidth - gap * (values.length - 1)) / values.length);
                    return Stack(
                      children: [
                        for (var i = 0; i <= 2; i++)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: c.maxHeight * i / 2,
                            child: Container(height: 1, color: AppColors.ring),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < values.length; i++) ...[
                              if (i > 0) SizedBox(width: gap),
                              Tooltip(
                                message: tooltips[i],
                                child: Container(
                                  width: width,
                                  height: math.max(2, c.maxHeight * values[i] / top),
                                  decoration: BoxDecoration(
                                    color: values[i] == 0 ? AppColors.ring : color,
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(math.min(4, width / 2))),
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
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        child: i % labelEvery == 0
                            ? Text(
                                labels[i],
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.visible,
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
}

/// Sprzedaż w godzinach (godzina złożenia zamówienia): ile zamówień, za ile i ile z nich na sali,
/// z dostawą i z odbiorem osobistym. Tylko godziny, w których coś sprzedano, na dole suma.
class _HourlyTable extends StatelessWidget {
  const _HourlyTable({required this.hours});

  final List<SalesPoint> hours;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = hours.where((h) => h.orders > 0).toList();
    final total = (
      orders: rows.fold(0, (s, h) => s + h.orders),
      revenue: rows.fold(0, (s, h) => s + h.revenue),
      dineIn: rows.fold(0, (s, h) => s + h.dineIn),
      delivery: rows.fold(0, (s, h) => s + h.delivery),
      pickup: rows.fold(0, (s, h) => s + h.pickup),
    );
    final head = text.labelMedium?.copyWith(color: AppColors.textMuted);
    final cell = text.bodyMedium?.copyWith(fontFeatures: _tabular);
    final strong = text.titleSmall?.copyWith(fontFeatures: _tabular);
    String two(int n) => n.toString().padLeft(2, '0');

    Widget row(List<String> values, TextStyle? style, {bool header = false, bool shaded = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: shaded ? AppColors.surfaceRaised : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (final (i, v) in values.indexed)
            Expanded(
              flex: i == 0 ? 3 : 2,
              child: Text(v, textAlign: i == 0 ? TextAlign.left : TextAlign.right, style: style),
            ),
        ],
      ),
    );

    return PanelCard(
      title: 'Sprzedaż w godzinach',
      icon: AppIcons.clock,
      iconColor: TileColors.blue,
      child: rows.isEmpty
          ? SalesView._empty(text)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row(['Godzina', 'Zamówienia', 'Kwota', 'Na miejscu', 'Dostawa', 'Odbiór osobisty'], head, header: true),
                for (final h in rows)
                  row([
                    '${two(h.key)}:00–${two((h.key + 1) % 24)}:00',
                    '${h.orders}',
                    Fmt.price(h.revenue),
                    '${h.dineIn}',
                    '${h.delivery}',
                    '${h.pickup}',
                  ], cell),
                const SizedBox(height: 4),
                row([
                  'Razem',
                  '${total.orders}',
                  Fmt.price(total.revenue),
                  '${total.dineIn}',
                  '${total.delivery}',
                  '${total.pickup}',
                ], strong, shaded: true),
              ],
            ),
    );
  }
}
