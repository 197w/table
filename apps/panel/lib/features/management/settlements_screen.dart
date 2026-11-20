import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../../shared/side_panel.dart';

const _tabular = [FontFeature.tabularFigures()];
const _paidColor = Color(0xFF2FB673);
const _unpaidColor = Color(0xFFE0A21B);

/// Stałe szerokości wąskich kolumn; zamówienia, adresy, dostawca, auto i płatność dzielą resztę.
const _whenWidth = 96.0;
const _amountWidth = 104.0;

/// Wysokość jednej linii w komórce: zamówienia kursu stoją w kolumnach równo pod sobą.
const _lineHeight = 24.0;

/// Okres rozliczeń.
enum SettlementPeriod {
  today('Dziś'),
  yesterday('Wczoraj'),
  week('7 dni'),
  month('Ten miesiąc'),
  lastMonth('Zeszły miesiąc');

  const SettlementPeriod(this.label);
  final String label;

  /// Dni lokalu od–do włącznie, licząc od [today] (dzień lokalu z godziną zamknięcia dnia).
  (DateTime, DateTime) range(DateTime today) => switch (this) {
    SettlementPeriod.today => (today, today),
    SettlementPeriod.yesterday => (
      DateTime(today.year, today.month, today.day - 1),
      DateTime(today.year, today.month, today.day - 1),
    ),
    SettlementPeriod.week => (DateTime(today.year, today.month, today.day - 6), today),
    SettlementPeriod.month => (DateTime(today.year, today.month), today),
    // Dzień 0 miesiąca to ostatni dzień poprzedniego.
    SettlementPeriod.lastMonth => (DateTime(today.year, today.month - 1), DateTime(today.year, today.month, 0)),
  };
}

/// Kursy po filtrach: dostawcy (klucz '-' to kurs bez dostawcy), opłacenie i wyszukiwanie.
List<CourierRun> filterRuns(
  List<CourierRun> runs, {
  Set<String> couriers = const {},
  Set<bool> paid = const {},
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  bool hit(CourierRun r) =>
      q.isEmpty ||
      (r.courierName?.toLowerCase().contains(q) ?? false) ||
      (r.vehicleLabel?.toLowerCase().contains(q) ?? false) ||
      r.orders.any(
        (o) =>
            '#${o.number}'.contains(q) ||
            '${o.number}' == q ||
            (o.address?.toLowerCase().contains(q) ?? false) ||
            (o.customer?.toLowerCase().contains(q) ?? false),
      );
  return [
    for (final r in runs)
      if ((couriers.isEmpty || couriers.contains(r.courierId ?? '-')) &&
          (paid.isEmpty || paid.contains(r.paid)) &&
          hit(r))
        r,
  ];
}

/// Sumy kursów po filtrach: opłacone z góry i nieopłacone (gotówka albo karta pobrana przez dostawcę).
({int paidGrosze, int paidRuns, int unpaidGrosze, int unpaidRuns, int orders}) settlementTotals(List<CourierRun> runs) {
  var paid = 0, paidRuns = 0, unpaid = 0, unpaidRuns = 0, orders = 0;
  for (final r in runs) {
    orders += r.orders.length;
    if (r.paid) {
      paid += r.totalGrosze;
      paidRuns++;
    } else {
      unpaid += r.totalGrosze;
      unpaidRuns++;
    }
  }
  return (paidGrosze: paid, paidRuns: paidRuns, unpaidGrosze: unpaid, unpaidRuns: unpaidRuns, orders: orders);
}

/// Management → Rozliczenia dostawców (20.11.2026, prośba użytkownika): wszystkie kursy dostawców z numerami
/// zamówień, opłaceniem, adresami, dostawcą i autem, w układzie jak Pracownicy: po lewej panel z wyszukiwaniem
/// i filtrami (dostawcy, opłacone / nieopłacone), po prawej tabela, na dole suma kursów opłaconych. Opłacone to karta
/// online i przyjęte z góry; gotówka i karta przy odbiorze to nieopłacone, bo dostawca pobiera je od gościa.
/// Uprawnienie „Podsumowanie dnia”.
class SettlementsScreen extends ConsumerStatefulWidget {
  const SettlementsScreen({super.key});

  @override
  ConsumerState<SettlementsScreen> createState() => _SettlementsScreenState();
}

class _SettlementsScreenState extends ConsumerState<SettlementsScreen> {
  final _search = TextEditingController();
  final _couriers = <String>{};
  final _paid = <bool>{};
  final _closed = <String>{};
  SettlementPeriod _period = SettlementPeriod.week;
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
    final (from, to) = _period.range(businessToday(ref.watch(dayCloseProvider)));
    final query = (restaurantId: restaurant.id, from: from, to: to);
    final async = ref.watch(courierSettlementsProvider(query));
    final runs = CourierRun.group(async.value ?? const <SettlementOrder>[]);
    final shown = filterRuns(runs, couriers: _couriers, paid: _paid, query: _search.text);
    final totals = settlementTotals(shown);

    // Dostawcy z kursów okresu (kurs bez dostawcy czeka na wolnego), z liczbą kursów.
    final names = <String, String>{};
    final counts = <String, int>{};
    for (final r in runs) {
      final id = r.courierId ?? '-';
      names[id] = r.courierName ?? 'Bez dostawcy';
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final courierIds = names.keys.toList()
      ..sort((a, b) {
        if (a == '-') return 1;
        if (b == '-') return -1;
        return names[a]!.toLowerCase().compareTo(names[b]!.toLowerCase());
      });

    final panel = SidePanel(
      header: const PanelTitle(icon: AppIcons.handCoins, title: 'Rozliczenia dostawców'),
      search: _search,
      searchHint: 'Szukaj kursu',
      onSearch: () => setState(() {}),
      children: [
        FilterSection(
          title: 'Dostawca',
          first: true,
          open: !_closed.contains('courier'),
          onToggle: () => _toggle(_closed, 'courier'),
          options: [
            for (final id in courierIds)
              (
                label: names[id]!,
                count: counts[id]!,
                checked: _couriers.contains(id),
                onChanged: (_) => _toggle(_couriers, id),
                dot: null,
              ),
          ],
        ),
        FilterSection(
          title: 'Opłacenie',
          open: !_closed.contains('paid'),
          onToggle: () => _toggle(_closed, 'paid'),
          options: [
            (
              label: 'Opłacone',
              count: runs.where((r) => r.paid).length,
              checked: _paid.contains(true),
              onChanged: (_) => _toggle(_paid, true),
              dot: _paidColor,
            ),
            (
              label: 'Nieopłacone',
              count: runs.where((r) => !r.paid).length,
              checked: _paid.contains(false),
              onChanged: (_) => _toggle(_paid, false),
              dot: _unpaidColor,
            ),
          ],
        ),
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 32, 0),
          child: Row(
            children: [
              SegmentedTabs<SettlementPeriod>(
                options: [for (final p in SettlementPeriod.values) (p, p.label)],
                selected: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
              const Spacer(),
              Text(
                from == to ? Fmt.dayShort(from) : '${Fmt.dayShort(from)} – ${Fmt.dayShort(to)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 32, 0),
            child: async.when(
              skipLoadingOnReload: true,
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(courierSettlementsProvider(query))),
              data: (_) => _RunsTable(runs: shown, empty: runs.isEmpty),
            ),
          ),
        ),
        _TotalsBar(totals: totals),
      ],
    );

    return SidePanelLayout(
      open: _panelOpen,
      onToggle: () => setState(() => _panelOpen = !_panelOpen),
      panel: panel,
      content: content,
    );
  }
}

/// Kursy jako tabela: kiedy, zamówienia, adresy, dostawca, auto, płatność i kwota.
class _RunsTable extends StatelessWidget {
  const _RunsTable({required this.runs, required this.empty});

  final List<CourierRun> runs;

  /// W okresie nie było żadnego kursu (inaczej filtry nic nie zostawiły).
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                tableHead(context, 'Kiedy', 0, width: _whenWidth),
                tableHead(context, 'Zamówienia', 3),
                tableHead(context, 'Adres', 4),
                tableHead(context, 'Dostawca', 3),
                tableHead(context, 'Auto', 4),
                tableHead(context, 'Płatność', 4),
                tableHead(context, 'Kwota', 0, width: _amountWidth, align: TextAlign.right),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.ring),
        Expanded(
          child: runs.isEmpty
              ? Center(
                  child: Text(
                    empty
                        ? 'W tym okresie nie było kursów dostawców.'
                        : 'Nic nie znaleziono. Zmień wyszukiwanie albo filtry po lewej.',
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                )
              : ListView.separated(
                  itemCount: runs.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.ring),
                  itemBuilder: (_, i) => _RunRow(run: runs[i]),
                ),
        ),
      ],
    );
  }
}

/// Jedna linia komórki: stała wysokość, żeby zamówienia kursu stały równo w kolumnach.
Widget _line(Widget child) => SizedBox(height: _lineHeight, child: Align(alignment: Alignment.centerLeft, child: child));

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run});

  final CourierRun run;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final body = text.bodyMedium?.copyWith(fontFeatures: _tabular);
    final at = run.at.toLocal();

    Widget lines(List<Widget> children, {CrossAxisAlignment align = CrossAxisAlignment.start}) =>
        Column(crossAxisAlignment: align, children: children);
    Text one(String value, {TextStyle? style, TextAlign align = TextAlign.left}) =>
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: align, style: style ?? body);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _whenWidth,
            child: lines([
              _line(one(Fmt.dayShort(at))),
              _line(one(Fmt.time(at), style: muted)),
            ]),
          ),
          Expanded(
            flex: 3,
            child: lines([
              for (final o in run.orders)
                _line(
                  one(
                    [
                      '#${o.number}',
                      ?o.customer,
                    ].join(' · '),
                  ),
                ),
            ]),
          ),
          Expanded(
            flex: 4,
            child: lines([
              for (final o in run.orders) _line(Tooltip(message: o.address ?? '', child: one(o.address ?? '—'))),
            ]),
          ),
          Expanded(
            flex: 3,
            child: lines([
              _line(one(run.courierName ?? 'Bez dostawcy', style: run.courierName == null ? muted : body)),
              if (!run.delivered) _line(one('Jeszcze w drodze', style: muted?.copyWith(color: _unpaidColor))),
            ]),
          ),
          Expanded(
            flex: 4,
            child: lines([_line(one(run.vehicleLabel ?? '—', style: run.vehicleLabel == null ? muted : body))]),
          ),
          Expanded(
            flex: 4,
            child: lines([
              for (final o in run.orders)
                _line(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: o.paid ? _paidColor : _unpaidColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        o.paid ? 'Opłacone' : 'Nieopłacone',
                        style: text.bodyMedium?.copyWith(
                          color: o.paid ? _paidColor : _unpaidColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(child: one(o.paymentShort, style: muted)),
                    ],
                  ),
                ),
            ]),
          ),
          SizedBox(
            width: _amountWidth,
            child: lines(
              [
                for (final o in run.orders)
                  _line(one(Fmt.price(o.totalGrosze), style: run.orders.length > 1 ? muted : body, align: TextAlign.right)),
                if (run.orders.length > 1)
                  _line(
                    one(
                      Fmt.price(run.totalGrosze),
                      style: body?.copyWith(fontWeight: FontWeight.w600),
                      align: TextAlign.right,
                    ),
                  ),
              ],
              align: CrossAxisAlignment.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// Na dole: suma kursów opłaconych (po filtrach) i, mniejszą czcionką, nieopłaconych (do rozliczenia z dostawcami).
class _TotalsBar extends StatelessWidget {
  const _TotalsBar({required this.totals});

  final ({int paidGrosze, int paidRuns, int unpaidGrosze, int unpaidRuns, int orders}) totals;

  String _runs(int n) {
    if (n == 1) return '1 kurs';
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n kursy';
    return '$n kursów';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 32, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.ringStrong)),
      ),
      child: Row(
        children: [
          Text(
            '${_runs(totals.paidRuns + totals.unpaidRuns)} · ${totals.orders} zam.',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Nieopłacone (do rozliczenia z dostawcami): ${Fmt.price(totals.unpaidGrosze)} · ${_runs(totals.unpaidRuns)}',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
              ),
            ],
          ),
          const SizedBox(width: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Suma kursów opłaconych', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
              Text(
                Fmt.price(totals.paidGrosze),
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: _paidColor, fontFeatures: _tabular),
              ),
              Text(_runs(totals.paidRuns), style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
