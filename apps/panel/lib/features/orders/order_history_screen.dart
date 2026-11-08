import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../../shared/side_panel.dart';
import '../printing/devices_pages.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Stan rachunku w filtrach panelu.
enum _State {
  paid('Opłacone'),
  cancelled('Anulowane');

  const _State(this.label);
  final String label;

  bool matches(PanelOrder o) => switch (this) {
    paid => o.isPaid,
    cancelled => o.isCancelled,
  };
}

/// Gdzie było zamówienie: w restauracji, z dostawą albo z odbiorem osobistym.
enum HistoryKind {
  all('Wszystkie', AppIcons.receipt),
  dineIn('W restauracji', AppIcons.forkKnife),
  delivery('Dostawy', AppIcons.moped),
  pickup('Odbiór osobisty', AppIcons.shoppingBag);

  const HistoryKind(this.label, this.icon);
  final String label;
  final AppIconData icon;

  bool matches(PanelOrder o) => switch (this) {
    all => true,
    dineIn => o.kind == OrderKind.dineIn,
    delivery => o.kind == OrderKind.delivery,
    pickup => o.kind == OrderKind.pickup,
  };
}

/// Historia zamówień w układzie jak Statystyki i Pracownicy (5.11.2026, prośba użytkownika): po lewej zwijany panel
/// z wyszukiwaniem po imieniu, firmie, telefonie i adresie ze wszystkich dni oraz filtrami z liczbą rachunków dnia
/// (rodzaj: restauracja, dostawy, odbiór osobisty; stan: opłacone, anulowane; puste grupy nie filtrują), dzień
/// w prawym górnym rogu, pod nim kafle podsumowania (tylko z uprawnieniem „Przychody”), lista rachunków
/// i szczegóły wybranego.
class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  late DateTime _day = businessToday(ref.read(dayCloseProvider));
  String? _selectedId;

  // Panel po lewej: zaznaczone filtry (puste: wszystko), zwinięte grupy i zwinięcie panelu.
  final _kinds = <HistoryKind>{};
  final _states = <_State>{};
  final _closed = <String>{};
  bool _panelOpen = true;

  /// Wpisany tekst wyszukiwania; od 2 znaków lista pokazuje wyniki ze wszystkich dni zamiast wybranego dnia.
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  bool get _searching => _query.length >= 2;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _query = _search.text.trim();
        _selectedId = null;
      });
    });
  }

  void _toggle<T>(Set<T> set, T value) => setState(() {
    set.contains(value) ? set.remove(value) : set.add(value);
    _selectedId = null;
  });

  bool _kindMatches(PanelOrder o) => _kinds.isEmpty || _kinds.any((k) => k.matches(o));
  bool _stateMatches(PanelOrder o) => _states.isEmpty || _states.any((s) => s.matches(o));

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
    if (!restaurant.isPro) return const ProGate(feature: 'Historia zamówień');

    final today = businessToday(ref.watch(dayCloseProvider));
    final canRevenue = ref.watch(memberPermissionsProvider).contains('revenue');
    final query = (restaurantId: restaurant.id, day: _day);
    final searchQuery = (restaurantId: restaurant.id, query: _query);
    // Wyszukiwanie przeszukuje wszystkie dni; bez niego lista wybranego dnia.
    final async = _searching ? ref.watch(orderSearchProvider(searchQuery)) : ref.watch(orderHistoryProvider(query));
    void retry() =>
        _searching ? ref.invalidate(orderSearchProvider(searchQuery)) : ref.invalidate(orderHistoryProvider(query));
    final tables = ref.watch(tablesProvider(restaurant.id)).value ?? const <DiningTable>[];
    final labels = {for (final t in tables) ?t.id: '${t.isSeat ? 'Miejsce' : 'Stolik'} ${t.label}'};
    String labelOf(PanelOrder o) => o.takeawayLabel ?? labels[o.tableId] ?? 'Bez stolika';
    final all = async.value ?? const <PanelOrder>[];

    final panel = SidePanel(
      header: const PanelTitle(icon: AppIcons.clockBack, title: 'Historia zamówień'),
      search: _search,
      searchHint: 'Imię, telefon albo adres',
      onSearch: _onSearch,
      children: [
        FilterSection(
          title: 'Rodzaj',
          first: true,
          open: !_closed.contains('kind'),
          onToggle: () => _toggle(_closed, 'kind'),
          options: [
            for (final k in HistoryKind.values)
              if (k != HistoryKind.all)
                (
                  label: k.label,
                  count: all.where(k.matches).length,
                  checked: _kinds.contains(k),
                  onChanged: (_) => _toggle(_kinds, k),
                  dot: null,
                ),
          ],
        ),
        FilterSection(
          title: 'Stan',
          open: !_closed.contains('state'),
          onToggle: () => _toggle(_closed, 'state'),
          options: [
            for (final st in _State.values)
              (
                label: st.label,
                count: all.where(st.matches).length,
                checked: _states.contains(st),
                onChanged: (_) => _toggle(_states, st),
                dot: st == _State.cancelled ? AppColors.error : null,
              ),
          ],
        ),
      ],
    );

    final text = Theme.of(context).textTheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Dzień w prawym górnym rogu, jak okres w Statystykach; przy wyszukiwaniu w jego miejscu wynik.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 32, 12),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: _searching && async.hasValue
                      ? Text(
                          all.isEmpty
                              ? 'Nic nie znaleziono dla „$_query”.'
                              : all.length >= 100
                              ? 'Pierwsze 100 wyników dla „$_query” (najnowsze). Wpisz więcej, żeby zawęzić.'
                              : 'Wyniki dla „$_query”: ${all.length}, ze wszystkich dni.',
                          style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                        )
                      : const SizedBox.shrink(),
                ),
                if (!_searching) _daySwitcher(today),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 32, 24),
            child: async.when(
              skipLoadingOnReload: true,
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(error: e, onRetry: retry),
              data: (everything) {
                // Kafle liczą rachunki wybranych rodzajów (także anulowane), lista pokazuje też filtr stanu.
                final ofKind = everything.where(_kindMatches).toList();
                final visible = ofKind.where(_stateMatches).toList();
                PanelOrder? selected;
                for (final o in everything) {
                  if (o.id == _selectedId) selected = o;
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_searching && canRevenue) ...[_Summary(orders: ofKind), const SizedBox(height: 16)],
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Card(
                              child: visible.isEmpty
                                  ? MessageView(
                                      icon: _searching ? AppIcons.search : AppIcons.receipt,
                                      title: everything.isEmpty
                                          ? (_searching ? 'Brak wyników' : 'Brak zamkniętych rachunków')
                                          : 'Nic w tych filtrach',
                                      message: _searching && everything.isEmpty
                                          ? 'Szukamy w imieniu, nazwie firmy, telefonie i adresie dostawy.'
                                          : everything.isEmpty
                                          ? 'Tego dnia nic tu nie zamknięto ani nie anulowano.'
                                          : 'Zmień filtry po lewej, żeby zobaczyć pozostałe rachunki.',
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.all(8),
                                      itemCount: visible.length,
                                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                                      itemBuilder: (context, i) => _OrderRow(
                                        order: visible[i],
                                        label: labelOf(visible[i]),
                                        showDate: _searching,
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

    return SidePanelLayout(
      open: _panelOpen,
      onToggle: () => setState(() => _panelOpen = !_panelOpen),
      panel: panel,
      content: content,
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
    final revenue = paid.fold<int>(0, (s, o) => s + o.billGrosze - o.discountGrosze);
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
          child: StatTile(label: 'Anulowane', value: '$cancelled', icon: AppIcons.prohibit, color: TileColors.rose),
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
    this.showDate = false,
  });

  final PanelOrder order;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Wyniki wyszukiwania są z różnych dni: nad godziną dzień.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = order.isCancelled;
    // Anulowany rachunek pokazuje, co na nim było, przekreślone.
    final items = muted ? order.items : order.active;
    final count = items.fold<int>(0, (s, i) => s + i.quantity);
    final value = items.fold<int>(0, (s, i) => s + i.totalGrosze) + order.deliveryFeeGrosze;
    final customer = order.customerCompany ?? order.customerName;

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
                width: showDate ? 84 : 64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showDate && order.closedAt != null)
                      Text(
                        Fmt.dayShort(order.closedAt!),
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                      ),
                    Text(
                      order.closedAt == null ? '—' : Fmt.time(order.closedAt!),
                      style: text.titleMedium?.copyWith(fontFeatures: _tabular),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        if (customer == null || order.kind == OrderKind.dineIn) label else '$label · $customer',
                        // Przy wyszukiwaniu widać, co pasuje: telefon i adres.
                        if (showDate && order.customerPhone != null) order.customerPhone!,
                        if (showDate && order.deliveryAddress != null) order.deliveryAddress!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge,
                    ),
                    Text(
                      '${_pieces(count)} · ${_paymentLabel(order)}',
                      style: text.bodySmall?.copyWith(color: muted ? AppColors.error : AppColors.textMuted),
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
                if (order.kind != OrderKind.dineIn && (order.customerName ?? order.customerCompany) != null)
                  Text(
                    [
                      ?order.customerCompany,
                      if (order.customerName != order.customerCompany) ?order.customerName,
                      ?order.customerPhone,
                    ].join(' · '),
                    style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                  ),
                if (order.deliveryAddress != null) Text(order.deliveryAddress!, style: text.bodyMedium),
                Text(
                  [
                    '${Fmt.time(order.openedAt)}–${closed == null ? '…' : Fmt.time(closed)}',
                    if (minutes != null)
                      order.kind == OrderKind.dineIn ? '$minutes min przy stoliku' : '$minutes min od zamówienia',
                  ].join(' · '),
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
                FiscalReceiptRow(order: order),
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
                            style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i.name,
                                style: text.bodyMedium?.copyWith(
                                  decoration: i.status == OrderItemStatus.cancelled ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              if (i.details != null)
                                Text(i.details!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                              if (i.status == OrderItemStatus.cancelled)
                                Text('anulowana', style: text.bodySmall?.copyWith(color: AppColors.error)),
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
                if (order.deliveryFeeGrosze > 0)
                  Row(
                    children: [
                      Text('Dostawa', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                      const Spacer(),
                      Text(
                        Fmt.price(order.deliveryFeeGrosze),
                        style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                      ),
                    ],
                  ),
                Row(
                  children: [
                    Text('Razem', style: text.titleMedium),
                    const Spacer(),
                    Text(Fmt.price(order.billGrosze), style: text.headlineSmall?.copyWith(fontFeatures: _tabular)),
                  ],
                ),
                for (final e in vat)
                  Row(
                    children: [
                      Text('w tym VAT ${e.key}%', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                      const Spacer(),
                      Text(
                        Fmt.price(_vatOf(e.value, e.key)),
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
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
                        label: p.tipGrosze > 0
                            ? '${p.method.label} · napiwek ${Fmt.price(p.tipGrosze)}'
                            : p.method.label,
                        amount: p.amountGrosze,
                      )
                  else ...[
                    if (gift != null) _PayRow(label: 'Karta podarunkowa', amount: gift),
                    if (order.paymentMethod != null && order.paymentMethod != PaymentMethod.giftCard)
                      _PayRow(
                        label: order.paymentMethod!.label,
                        amount: order.billGrosze - order.discountGrosze - (gift ?? 0),
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
