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

/// Statystyki zespołu (grupa Pracownicy): godziny, zmiany, rachunki, sprzedaż, pozycje, kursy, goście (i pominięcia
/// liczby gości), napiwki gotówką i kartą oraz zarobek na osobę: dziś, 7 i 14 dni albo bieżący miesiąc.
/// Uprawnienie „Statystyki”, zarobki i udział wypłat w obrocie tylko z uprawnieniem „Pracownicy”.
class TeamStatsScreen extends ConsumerStatefulWidget {
  const TeamStatsScreen({super.key});

  @override
  ConsumerState<TeamStatsScreen> createState() => _TeamStatsScreenState();
}

class _TeamStatsScreenState extends ConsumerState<TeamStatsScreen> {
  TeamPeriod _period = TeamPeriod.month;

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final query = (restaurantId: restaurant.id, period: _period);
    final async = ref.watch(teamStatsProvider(query));
    final summary = ref.watch(teamSummaryProvider(query)).value ?? const TeamSummary();
    final canPay = ref.watch(memberPermissionsProvider).contains('staff');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          below: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedTabs<TeamPeriod>(
              options: [for (final p in TeamPeriod.values) (p, p.label)],
              selected: _period,
              onChanged: (p) => setState(() => _period = p),
            ),
          ),
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
              final payroll = people.fold(0, (sum, s) => sum + (s.earningsGrosze ?? 0));
              final payrollNet = people.fold(
                0,
                (sum, s) => sum + (s.earningsGrosze == null ? 0 : Payroll.monthlyNet(s.contract, s.earningsGrosze!)),
              );
              final pay = canPay && people.any((s) => s.rateGrosze != null);
              final best = people.fold(0, (m, s) => s.revenueGrosze > m ? s.revenueGrosze : m);
              // Jaka część obrotu lokalu idzie na wypłaty (brutto) w wybranym okresie.
              final payShare = summary.revenueGrosze > 0 ? payroll / summary.revenueGrosze * 100 : null;

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
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (pay) ...[
                          Expanded(
                            child: StatTile(
                              label: 'Wynagrodzenia brutto',
                              value: Fmt.price(payroll),
                              hint: 'netto ok. ${Fmt.price(payrollNet)}',
                              icon: AppIcons.creditCard,
                              color: TileColors.violet,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: StatTile(
                              label: 'Wypłaty z obrotu',
                              value: payShare == null ? '—' : '${payShare.toStringAsFixed(1).replaceAll('.', ',')}%',
                              hint: 'obrót lokalu ${Fmt.price(summary.revenueGrosze)}',
                              icon: AppIcons.chartPie,
                              color: TileColors.rose,
                            ),
                          ),
                          const SizedBox(width: 14),
                        ],
                        Expanded(
                          child: StatTile(
                            label: 'Napiwki',
                            value: Fmt.price(summary.tipsCashGrosze + summary.tipsCardGrosze),
                            hint: 'gotówka ${Fmt.price(summary.tipsCashGrosze)} · karta ${Fmt.price(summary.tipsCardGrosze)}',
                            icon: AppIcons.handCoins,
                            color: TileColors.green,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: StatTile(
                            label: 'Goście przy stolikach',
                            value: '${summary.guests}',
                            hint: summary.skipped == 0
                                ? 'liczba gości wpisana przy każdym stoliku'
                                : 'bez liczby gości: ${summary.skipped} z ${summary.tables} stolików',
                            icon: AppIcons.users,
                            color: TileColors.blue,
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
                          _HeaderRow(pay: pay),
                          Divider(height: 1, color: AppColors.ring),
                          for (final (i, s) in people.indexed) ...[
                            if (i > 0) Divider(height: 1, color: AppColors.ring),
                            _MemberRow(stat: s, best: best, pay: pay),
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

const _column = 100.0;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.pay});

  final bool pay;

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
          cell('Goście'),
          cell('Napiwki'),
          if (pay) SizedBox(width: _column + 30, child: Text('Zarobek', textAlign: TextAlign.end, style: style)),
          SizedBox(width: _column + 60, child: Text('Sprzedaż', textAlign: TextAlign.end, style: style)),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.stat, required this.best, required this.pay});

  final TeamStat stat;
  final bool pay;

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
          // Goście przy otwartych stolikach i ile razy pominięto ich liczbę.
          SizedBox(
            width: _column,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${s.guests}', style: value?.copyWith(color: s.guests == 0 ? AppColors.textMuted : null)),
                if (s.guestsSkipped > 0)
                  Text(
                    'pominięte: ${s.guestsSkipped}',
                    style: text.bodySmall?.copyWith(color: const Color(0xFFD99A15), fontFeatures: _tabular),
                  ),
              ],
            ),
          ),
          // Napiwki z płatności, które przyjął: gotówką i kartą.
          SizedBox(
            width: _column,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  s.tipsCashGrosze + s.tipsCardGrosze == 0 ? '—' : Fmt.price(s.tipsCashGrosze + s.tipsCardGrosze),
                  style: value?.copyWith(color: s.tipsCashGrosze + s.tipsCardGrosze == 0 ? AppColors.textMuted : null),
                ),
                if (s.tipsCashGrosze + s.tipsCardGrosze > 0)
                  Text(
                    'got. ${Fmt.price(s.tipsCashGrosze)} · karta ${Fmt.price(s.tipsCardGrosze)}',
                    textAlign: TextAlign.end,
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular, fontSize: 11),
                  ),
              ],
            ),
          ),
          // Zarobek ze stawką widoczną od razu (bez najeżdżania).
          if (pay)
            SizedBox(
              width: _column + 30,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    s.earningsGrosze == null ? '—' : Fmt.price(s.earningsGrosze!),
                    style: value?.copyWith(
                      color: s.earningsGrosze == null || s.earningsGrosze == 0 ? AppColors.textMuted : null,
                    ),
                  ),
                  Text(
                    s.rateGrosze == null ? 'bez stawki' : '${Fmt.price(s.rateGrosze!)}/h brutto',
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                  ),
                  if (s.earningsGrosze != null)
                    Text(
                      'netto ${Fmt.price(Payroll.monthlyNet(s.contract, s.earningsGrosze!))}',
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                    ),
                ],
              ),
            ),
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
