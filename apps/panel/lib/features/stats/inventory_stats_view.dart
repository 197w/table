import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Średnia z rozsądną dokładnością: „12,5 kg”, „2,25 kg”, „0,29 l”, a bardzo małe do trzech miejsc („0,004 kg”).
String _avg(double v) =>
    inventoryNumber(v >= 10 ? (v * 10).round() / 10 : (v >= 0.1 ? (v * 100).round() / 100 : v));

/// Stany w filtrach panelu Statystyk → Inwentaryzacja (klucz, nazwa).
const inventoryStatStates = [
  ('order', 'Do zamówienia'),
  ('week', 'Wystarczy na mniej niż tydzień'),
  ('idle', 'Bez zużycia w okresie'),
];

/// Czy składnik pasuje do stanu z filtrów.
bool inventoryStatMatches(InventoryUsage u, String state) => switch (state) {
  'order' => u.needsOrder,
  'week' => u.daysLeft != null && u.daysLeft! < 7,
  'idle' => u.used <= 0,
  _ => false,
};

/// Klucz lokalizacji w filtrach: pusty napis to „Bez lokalizacji”.
String inventoryStatLocation(InventoryUsage u) => u.location ?? '';

/// Statystyki → Inwentaryzacja (11.11.2026, prośba użytkownika: „średnie zużycie dziennie i prognoza »wystarczy na
/// ok. X dni«”): kafle, tabela składników od tego, który skończy się najszybciej (stan teraz, zużycie w okresie,
/// średnio dziennie, na ile dni wystarczy, kiedy zamówić według progu z Inwentaryzacji) i wykres zużycia dzień po
/// dniu wybranego składnika. Zużycie to sprzedaż z receptur oraz straty i posiłki pracownicze (`panel_inventory_usage`,
/// 0086); średnia z okresu 7D / 30D / 90D albo od dodania składnika. Filtry (stan, lokalizacja) są w panelu po lewej.
class InventoryStatsView extends ConsumerStatefulWidget {
  const InventoryStatsView({super.key, required this.query, required this.states, required this.locations});

  final InventoryUsageQuery query;

  /// Zaznaczone stany i lokalizacje (puste: wszystko).
  final Set<String> states;
  final Set<String> locations;

  @override
  ConsumerState<InventoryStatsView> createState() => _InventoryStatsViewState();
}

class _InventoryStatsViewState extends ConsumerState<InventoryStatsView> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inventoryUsageProvider(widget.query));
    final text = Theme.of(context).textTheme;
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(inventoryUsageProvider(widget.query))),
      data: (report) {
        if (report.items.isEmpty) {
          return const MessageView(
            icon: AppIcons.package,
            title: 'Brak składników',
            message: 'Składniki dodaje się w Management → Inwentaryzacja, a ich zużycie w recepturach dań w Menu.',
          );
        }
        final items = [
          for (final u in report.items)
            if ((widget.states.isEmpty || widget.states.any((s) => inventoryStatMatches(u, s))) &&
                (widget.locations.isEmpty || widget.locations.contains(inventoryStatLocation(u))))
              u,
        ]..sort(_byUrgency);
        if (items.isEmpty) {
          return const MessageView(
            icon: AppIcons.funnel,
            title: 'Nic nie znaleziono',
            message: 'Żaden składnik nie pasuje do zaznaczonych filtrów.',
          );
        }
        final selected =
            items.where((u) => u.itemId == _selected).firstOrNull ??
            items.where((u) => u.used > 0).firstOrNull ??
            items.first;
        final toOrder = items.where((u) => u.needsOrder).length;
        final week = items.where((u) => u.daysLeft != null && u.daysLeft! < 7).length;
        final used = items.where((u) => u.used > 0).length;
        final soonest = items.where((u) => u.daysLeft != null).firstOrNull;

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 32, 32),
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Do zamówienia',
                      value: '$toOrder',
                      icon: AppIcons.package,
                      color: TileColors.amber,
                      hint: 'stan doszedł do progu z Inwentaryzacji',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'Wystarczy na mniej niż tydzień',
                      value: '$week',
                      icon: AppIcons.hourglass,
                      color: TileColors.rose,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'Najszybciej się skończy',
                      value: soonest == null
                          ? '—'
                          : (soonest.daysLeft == 0 ? 'Brak' : inventoryDaysText(soonest.daysLeft!)),
                      icon: AppIcons.clock,
                      color: TileColors.violet,
                      hint: soonest?.name,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'Składniki ze zużyciem',
                      value: '$used z ${items.length}',
                      icon: AppIcons.chartBar,
                      color: TileColors.blue,
                      hint: 'w ostatnich ${widget.query.days} dniach',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _UsageTable(items: items, selected: selected.itemId, onSelect: (id) => setState(() => _selected = id)),
            const SizedBox(height: 16),
            PanelCard(
              title: 'Zużycie dzień po dniu: ${selected.name}',
              icon: AppIcons.chartBar,
              iconColor: TileColors.green,
              trailing: Text(
                selected.perDay > 0
                    ? 'średnio ${_avg(selected.perDay)} ${selected.unit.label} dziennie'
                    : 'bez zużycia w okresie',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
              ),
              child: SizedBox(
                height: 260,
                child: _UsageChart(days: report.days, today: report.today, usage: selected),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Najpierw te, które skończą się najszybciej, potem bez prognozy (nie liczone albo bez zużycia), w nich
  /// najpierw zużywane.
  static int _byUrgency(InventoryUsage a, InventoryUsage b) {
    final da = a.daysLeft ?? double.infinity;
    final db = b.daysLeft ?? double.infinity;
    if (da != db) return da.compareTo(db);
    if (a.perDay != b.perDay) return b.perDay.compareTo(a.perDay);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

/// Tabela składników: stan teraz, zużycie, średnio dziennie, na ile wystarczy i kiedy zamówić. Kliknięty wiersz
/// pokazuje swój wykres pod tabelą.
class _UsageTable extends StatelessWidget {
  const _UsageTable({required this.items, required this.selected, required this.onSelect});

  final List<InventoryUsage> items;
  final String selected;
  final ValueChanged<String> onSelect;

  static const _flex = [4, 2, 2, 2, 2, 2];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final head = text.labelMedium?.copyWith(color: AppColors.textMuted);
    final cell = text.bodyMedium?.copyWith(fontFeatures: _tabular);
    final muted = cell?.copyWith(color: AppColors.textMuted);

    Widget value(int i, String v, TextStyle? style) => Expanded(
      flex: _flex[i],
      child: Text(v, textAlign: TextAlign.right, style: style),
    );

    return PanelCard(
      title: 'Zużycie i prognoza',
      icon: AppIcons.package,
      iconColor: TileColors.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Expanded(flex: _flex[0], child: Text('Składnik', style: head)),
                for (final (i, label) in const [
                  (1, 'Stan teraz'),
                  (2, 'Zużycie w okresie'),
                  (3, 'Średnio dziennie'),
                  (4, 'Wystarczy na'),
                  (5, 'Zamówić'),
                ])
                  value(i, label, head),
              ],
            ),
          ),
          for (final u in items)
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => onSelect(u.itemId),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: u.itemId == selected ? AppColors.surfaceRaised : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: _flex[0],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                            if (u.location != null)
                              Text(u.location!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      value(
                        1,
                        u.stock == null ? 'nie liczono' : '${inventoryNumber(u.stock!)} ${u.unit.label}',
                        u.stock == null
                            ? muted
                            : cell?.copyWith(
                                color: u.stock! <= 0.0005
                                    ? AppColors.error
                                    : (u.needsOrder ? AppColors.warning : null),
                              ),
                      ),
                      value(2, u.used > 0 ? '${inventoryNumber(u.used)} ${u.unit.label}' : '—', u.used > 0 ? cell : muted),
                      value(
                        3,
                        u.perDay > 0 ? '${_avg(u.perDay)} ${u.unit.label}' : '—',
                        u.perDay > 0 ? cell : muted,
                      ),
                      value(4, _left(u), _leftStyle(u, cell, muted)),
                      value(5, _order(u), u.needsOrder ? text.titleSmall?.copyWith(color: AppColors.warning) : muted),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'Zużycie to sprzedaż z receptur dań w Menu oraz straty i posiłki pracownicze (bez przekazań do innego '
            'lokalu i zwrotów). Średnio dziennie liczy się z wybranego okresu albo od dodania składnika, a „Wystarczy '
            'na” to stan teraz podzielony przez średnie zużycie. „Zamówić” według progu „Powiadom o zamówieniu przy” '
            'ze składnika w Inwentaryzacji.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  static String _left(InventoryUsage u) {
    final d = u.daysLeft;
    if (d == null) return u.stock == null ? '—' : 'bez zużycia';
    if (d == 0) return 'Brak';
    return inventoryDaysText(d);
  }

  static TextStyle? _leftStyle(InventoryUsage u, TextStyle? cell, TextStyle? muted) {
    final d = u.daysLeft;
    if (d == null) return muted;
    if (d < 3) return cell?.copyWith(color: AppColors.error);
    if (d < 7) return cell?.copyWith(color: AppColors.warning);
    return cell;
  }

  static String _order(InventoryUsage u) {
    if (u.reorderAt == null) return '—';
    if (u.needsOrder) return 'Teraz';
    final d = u.daysToOrder;
    if (d == null) return 'przy ${inventoryNumber(u.reorderAt!)} ${u.unit.label}';
    if (d < 1) return 'w ciągu doby';
    return 'za ${inventoryDaysText(d)}';
  }
}

/// Słupki zużycia składnika dzień po dniu (sprzedaż i straty razem, w dymku osobno).
class _UsageChart extends StatelessWidget {
  const _UsageChart({required this.days, required this.today, required this.usage});

  final List<DateTime> days;

  /// Dzisiejszy dzień lokalu (z zamknięciem dnia).
  final DateTime today;
  final InventoryUsage usage;

  /// Okrągła góra osi: 1, 2, 2,5 albo 5 razy potęga dziesięciu.
  static double _niceCeil(double v) {
    if (v <= 0) return 1;
    final power = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
      if (v <= m * power + 1e-9) return m * power;
    }
    return 10 * power;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final values = [for (final d in days) usage.usedOn(d)];
    bool isToday(DateTime d) => d == today;
    final top = _niceCeil(values.fold(0.0, math.max));
    final labelEvery = days.length <= 7 ? 1 : (days.length <= 30 ? 5 : 15);
    final unit = usage.unit.label;

    String tip(DateTime day) {
      final d = usage.days[day];
      final when = Fmt.capitalize(Fmt.dayShort(DateTime(day.year, day.month, day.day)));
      if (d == null) return '$when: 0 $unit';
      return [
        '$when: ${inventoryNumber(d.sold + d.lost)} $unit',
        if (d.lost > 0) 'sprzedaż ${inventoryNumber(d.sold)} $unit, straty ${inventoryNumber(d.lost)} $unit',
      ].join('\n');
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, v) in [top, top * 3 / 4, top / 2, top / 4, 0.0].indexed) ...[
                Text(
                  '${inventoryNumber(v)} $unit',
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
                if (i < 4) const Spacer(),
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
                                message: tip(days[i]),
                                child: Container(
                                  width: barWidth,
                                  height: math.max(2, c.maxHeight * values[i] / top),
                                  decoration: BoxDecoration(
                                    color: values[i] <= 0
                                        ? AppColors.ring
                                        : (isToday(days[i]) ? AppColors.accentFill : TileColors.green),
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(math.min(4, barWidth / 2))),
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
                        child: i % labelEvery == 0 || i == days.length - 1 || isToday(days[i])
                            ? Text(
                                '${days[i].day}.${days[i].month.toString().padLeft(2, '0')}',
                                maxLines: 1,
                                overflow: TextOverflow.visible,
                                softWrap: false,
                                style: text.bodySmall?.copyWith(
                                  color: isToday(days[i]) ? AppColors.accent : AppColors.textMuted,
                                  fontWeight: isToday(days[i]) ? FontWeight.w600 : null,
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
}
