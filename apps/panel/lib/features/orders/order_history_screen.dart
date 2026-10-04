import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

enum _Filter {
  all('Wszystkie'),
  paid('Opłacone'),
  cancelled('Anulowane');

  const _Filter(this.label);
  final String label;

  bool matches(PanelOrder o) => switch (this) {
    all => true,
    paid => o.isPaid,
    cancelled => o.isCancelled,
  };
}

/// Historia zamówień: zamknięte rachunki z wybranego dnia. Podsumowanie obrotu widzi tylko osoba
/// z uprawnieniem „Przychody” (kierownik, właściciel); kelner widzi same rachunki.
class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key, this.embedded = false});

  /// Wewnątrz zakładki „Statystyki”: bez własnego nagłówka strony.
  final bool embedded;

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  DateTime _day = dateOnly(DateTime.now());
  _Filter _filter = _Filter.all;
  String? _selectedId;

  void _shift(int days) => setState(() {
    _day = DateTime(_day.year, _day.month, _day.day + days);
    _selectedId = null;
  });

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _day = dateOnly(picked);
        _selectedId = null;
      });
    }
  }

  /// Dzień historii w pigułce ze strzałkami; stuknięcie w datę wraca do dziś.
  Widget _daySwitcher(DateTime today) => StepSwitcher(
    label: '${Fmt.capitalize(Fmt.dayShort(_day))}${_day == today ? ' · dziś' : ''}',
    labelWidth: 150,
    previousTooltip: 'Poprzedni dzień',
    nextTooltip: 'Następny dzień',
    onPrevious: () => _shift(-1),
    onNext: _day == today ? null : () => _shift(1),
    resetTooltip: 'Wróć do dziś',
    onReset: _day == today ? null : () => _shift(today.difference(_day).inDays),
    extras: [(AppIcons.calendar, 'Wybierz dzień', _pickDay)],
  );

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();

    if (!restaurant.isPro) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: ProGate(feature: 'Historia zamówień')),
        ],
      );
    }
    final today = dateOnly(DateTime.now());
    final canRevenue = ref.watch(memberPermissionsProvider).contains('revenue');
    final query = (restaurantId: restaurant.id, day: _day);
    final async = ref.watch(orderHistoryProvider(query));
    final tables = ref.watch(tablesProvider(restaurant.id)).value ?? const <DiningTable>[];
    final labels = {for (final t in tables) ?t.id: '${t.isSeat ? 'Miejsce' : 'Stolik'} ${t.label}'};
    String labelOf(PanelOrder o) => o.takeawayLabel ?? labels[o.tableId] ?? 'Bez stolika';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
            child: Row(
              children: [
                SegmentedTabs<_Filter>(
                  options: [for (final f in _Filter.values) (f, f.label)],
                  selected: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
                const Spacer(),
                _daySwitcher(today),
              ],
            ),
          )
        else
        PageHeader(
          actions: [
            _daySwitcher(today),
          ],
          below: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedTabs<_Filter>(
              options: [for (final f in _Filter.values) (f, f.label)],
              selected: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
            child: async.when(
              skipLoadingOnReload: true,
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(orderHistoryProvider(query)),
              ),
              data: (orders) {
                final visible = orders.where(_filter.matches).toList();
                PanelOrder? selected;
                for (final o in orders) {
                  if (o.id == _selectedId) selected = o;
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (canRevenue) ...[
                      _Summary(orders: orders),
                      const SizedBox(height: 16),
                    ],
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Card(
                              child: visible.isEmpty
                                  ? MessageView(
                                      icon: AppIcons.receipt,
                                      title: orders.isEmpty ? 'Brak zamkniętych rachunków' : 'Nic w tym filtrze',
                                      message: orders.isEmpty
                                          ? 'Tego dnia nie zamknięto ani nie anulowano żadnego rachunku.'
                                          : 'Wybierz inny filtr, żeby zobaczyć pozostałe rachunki.',
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.all(8),
                                      itemCount: visible.length,
                                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                                      itemBuilder: (context, i) => _OrderRow(
                                        order: visible[i],
                                        label: labelOf(visible[i]),
                                        selected: visible[i].id == _selectedId,
                                        onTap: () => setState(() => _selectedId = visible[i].id),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 420,
                            child: selected == null
                                ? const Card(
                                    child: MessageView(
                                      icon: AppIcons.receipt,
                                      title: 'Wybierz rachunek',
                                      message: 'Zobaczysz tu pozycje, płatność i czas obsługi stolika.',
                                    ),
                                  )
                                : _OrderDetail(order: selected, label: labelOf(selected)),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Kafle z podsumowaniem dnia: obrót, liczba rachunków, średni rachunek i anulowane.
class _Summary extends StatelessWidget {
  const _Summary({required this.orders});

  final List<PanelOrder> orders;

  @override
  Widget build(BuildContext context) {
    final paid = orders.where((o) => o.isPaid).toList();
    final revenue = paid.fold<int>(0, (s, o) => s + o.totalGrosze - o.discountGrosze);
    final gift = paid.fold<int>(0, (s, o) => s + (o.giftCardGrosze ?? 0));
    final tips = paid.fold<int>(0, (s, o) => s + o.tipGrosze);
    final cancelled = orders.where((o) => o.isCancelled).length;

    return Row(
      children: [
        Expanded(
          child: StatTile(
            label: 'Obrót',
            value: Fmt.price(revenue),
            icon: AppIcons.receipt,
            color: TileColors.green,
            hint: [
              if (tips > 0) 'napiwki ${Fmt.price(tips)}',
              if (gift > 0) 'karty podarunkowe ${Fmt.price(gift)}',
            ].join(' · '),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatTile(
            label: 'Opłacone rachunki',
            value: '${paid.length}',
            icon: AppIcons.checkCircle,
            color: TileColors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatTile(
            label: 'Średni rachunek',
            value: paid.isEmpty ? '—' : Fmt.price(revenue ~/ paid.length),
            icon: AppIcons.chartBar,
            color: TileColors.violet,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatTile(
            label: 'Anulowane',
            value: '$cancelled',
            icon: AppIcons.prohibit,
            color: TileColors.rose,
          ),
        ),
      ],
    );
  }
}

String _paymentLabel(PanelOrder o) {
  if (o.isCancelled) return 'Anulowany';
  if (o.payments.length > 1) return 'Podzielony (${o.payments.length})';
  final gift = o.giftCardGrosze;
  final method = o.paymentMethod;
  if (gift != null && method != PaymentMethod.giftCard) {
    return 'Karta podarunkowa + ${method?.label.toLowerCase() ?? 'inne'}';
  }
  return method?.label ?? '—';
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final PanelOrder order;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = order.isCancelled;
    // Anulowany rachunek pokazuje, co na nim było, przekreślone.
    final items = muted ? order.items : order.active;
    final count = items.fold<int>(0, (s, i) => s + i.quantity);
    final value = items.fold<int>(0, (s, i) => s + i.totalGrosze);

    return Material(
      color: selected ? AppColors.surfaceRaised : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        splashColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  order.closedAt == null ? '—' : Fmt.time(order.closedAt!),
                  style: text.titleMedium?.copyWith(fontFeatures: _tabular),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: text.labelLarge),
                    Text(
                      '${_pieces(count)} · ${_paymentLabel(order)}',
                      style: text.bodySmall?.copyWith(
                        color: muted ? AppColors.error : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                Fmt.price(value),
                style: text.titleMedium?.copyWith(
                  fontFeatures: _tabular,
                  color: muted ? AppColors.textMuted : null,
                  decoration: muted ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pieces(int n) {
    if (n == 1) return '1 pozycja';
    final few = n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14);
    return '$n ${few ? 'pozycje' : 'pozycji'}';
  }
}

class _OrderDetail extends StatelessWidget {
  const _OrderDetail({required this.order, required this.label});

  final PanelOrder order;
  final String label;

  static int _vatOf(int gross, int rate) => (gross * rate / (100 + rate)).round();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final closed = order.closedAt;
    final minutes = closed?.difference(order.openedAt).inMinutes;
    final vat = order.byVat.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    final gift = order.giftCardGrosze;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(label, style: text.titleLarge)),
                    if (order.isCancelled) Tag('ANULOWANY', color: AppColors.error),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    '${Fmt.time(order.openedAt)}–${closed == null ? '…' : Fmt.time(closed)}',
                    if (minutes != null) '$minutes min przy stoliku',
                  ].join(' · '),
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                    fontFeatures: _tabular,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.ring),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              children: [
                for (final i in order.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${i.quantity}×',
                            style: text.bodyMedium?.copyWith(
                              color: AppColors.textMuted,
                              fontFeatures: _tabular,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i.name,
                                style: text.bodyMedium?.copyWith(
                                  decoration: i.status == OrderItemStatus.cancelled
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              if (i.details != null)
                                Text(
                                  i.details!,
                                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                                ),
                              if (i.status == OrderItemStatus.cancelled)
                                Text(
                                  'anulowana',
                                  style: text.bodySmall?.copyWith(color: AppColors.error),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          Fmt.price(i.totalGrosze),
                          style: text.bodyMedium?.copyWith(
                            fontFeatures: _tabular,
                            color: i.status == OrderItemStatus.cancelled ? AppColors.textMuted : null,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.ring),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Razem', style: text.titleMedium),
                    const Spacer(),
                    Text(
                      Fmt.price(order.totalGrosze),
                      style: text.headlineSmall?.copyWith(fontFeatures: _tabular),
                    ),
                  ],
                ),
                for (final e in vat)
                  Row(
                    children: [
                      Text(
                        'w tym VAT ${e.key}%',
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                      const Spacer(),
                      Text(
                        Fmt.price(_vatOf(e.value, e.key)),
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                          fontFeatures: _tabular,
                        ),
                      ),
                    ],
                  ),
                if (order.discountGrosze > 0) ...[
                  const SizedBox(height: 6),
                  _PayRow(label: 'Rabat ${order.discountLabel ?? ''}', amount: -order.discountGrosze),
                ],
                if (order.depositGrosze > 0)
                  _PayRow(label: 'Zadatek z rezerwacji (karta online)', amount: order.depositGrosze),
                if (order.isPaid) ...[
                  const SizedBox(height: 10),
                  if (order.payments.isNotEmpty)
                    for (final p in order.payments)
                      _PayRow(
                        label: p.tipGrosze > 0 ? '${p.method.label} · napiwek ${Fmt.price(p.tipGrosze)}' : p.method.label,
                        amount: p.amountGrosze,
                      )
                  else ...[
                    if (gift != null)
                      _PayRow(label: 'Karta podarunkowa', amount: gift),
                    if (order.paymentMethod != null && order.paymentMethod != PaymentMethod.giftCard)
                      _PayRow(
                        label: order.paymentMethod!.label,
                        amount: order.totalGrosze - (gift ?? 0),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PayRow extends StatelessWidget {
  const _PayRow({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Glyph(AppIcons.checkCircle, size: 14, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(label, style: text.bodyMedium),
          const Spacer(),
          Text(Fmt.price(amount), style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
        ],
      ),
    );
  }
}
