import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../orders/settle_dialog.dart';

const _tabular = [FontFeature.tabularFigures()];

enum _Filter { all, dineIn, takeaway }

/// Management → Niezamknięte zamówienia: otwarte rachunki na sali i niezakończone zamówienia na wynos (dostawy
/// i odbiór) ze wszystkich dni, najstarsze pierwsze, w jednej liście. Te z poprzednich dni są osobno na górze, bo
/// zwykle ktoś zapomniał zamknąć rachunek. Każde zamówienie, także dostawę w drodze, można stąd zamknąć („Zamknij”,
/// przy gotówce i karcie przy odbiorze z wyborem, jak gość zapłacił) albo anulować („Anuluj”); „Otwórz” prowadzi
/// do jego zakładki. Uprawnienie „Podsumowanie dnia”, zamykanie i anulowanie „Zamykanie rachunków”.
class UnclosedOrdersScreen extends ConsumerStatefulWidget {
  const UnclosedOrdersScreen({super.key});

  @override
  ConsumerState<UnclosedOrdersScreen> createState() => _UnclosedOrdersScreenState();
}

class _UnclosedOrdersScreenState extends ConsumerState<UnclosedOrdersScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final async = ref.watch(unclosedOrdersProvider(restaurant.id));
    final tables = ref.watch(tablesProvider(restaurant.id)).value ?? const <DiningTable>[];
    final labels = {for (final t in tables) ?t.id: '${t.isSeat ? 'Miejsce' : 'Stolik'} ${t.label}'};
    String labelOf(PanelOrder o) => o.takeawayLabel ?? labels[o.tableId] ?? 'Bez stolika';
    final all = async.value ?? const <UnclosedOrder>[];
    final dineIn = all.where((o) => o.stage == null).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          below: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedTabs<_Filter>(
              options: [
                (_Filter.all, 'Wszystkie (${all.length})'),
                (_Filter.dineIn, 'Na sali ($dineIn)'),
                (_Filter.takeaway, 'Na wynos (${all.length - dineIn})'),
              ],
              selected: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(unclosedOrdersProvider(restaurant.id))),
            data: (orders) {
              if (orders.isEmpty) {
                return MessageView(
                  icon: AppIcons.checkCircle.duotone,
                  title: 'Wszystko zamknięte',
                  message: 'Nie ma otwartych rachunków ani niezakończonych zamówień na wynos.',
                );
              }
              final now = DateTime.now();
              final close = ref.watch(dayCloseProvider);
              final visible = [
                for (final o in orders)
                  if (switch (_filter) {
                    _Filter.all => true,
                    _Filter.dineIn => o.stage == null,
                    _Filter.takeaway => o.stage != null,
                  })
                    o,
              ];
              final earlier = [
                for (final o in visible)
                  if (o.fromEarlierDay(now, close)) o,
              ];
              final today = [
                for (final o in visible)
                  if (!o.fromEarlierDay(now, close)) o,
              ];
              final earlierAll = orders.where((o) => o.fromEarlierDay(now, close)).toList();
              Widget tile(UnclosedOrder o) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OrderTile(
                  entry: o,
                  label: labelOf(o.order),
                  earlier: o.fromEarlierDay(now, close),
                  restaurantId: restaurant.id,
                ),
              );

              return ListView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Niezamknięte',
                          value: '${orders.length}',
                          hint: 'rachunki i zamówienia na wynos',
                          icon: AppIcons.hourglass,
                          color: TileColors.blue,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: StatTile(
                          label: 'Z poprzednich dni',
                          value: '${earlierAll.length}',
                          hint: earlierAll.isEmpty
                              ? 'wszystkie są z dzisiaj'
                              : 'najstarsze z ${Fmt.dayShort(earlierAll.first.order.openedAt)}',
                          icon: AppIcons.warning,
                          color: earlierAll.isEmpty ? TileColors.green : TileColors.rose,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: StatTile(
                          label: 'Do rozliczenia',
                          value: Fmt.price(orders.fold(0, (s, o) => s + o.order.billGrosze)),
                          hint: 'suma pozycji z dostawą',
                          icon: AppIcons.receipt,
                          color: TileColors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text(
                        'Nic w tym filtrze.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  if (earlier.isNotEmpty) ...[
                    const _SectionTitle(
                      icon: AppIcons.warning,
                      color: TileColors.rose,
                      title: 'Z poprzednich dni',
                      hint:
                          'Zamknij je albo sprawdź, czy ktoś nie zapomniał. Nie liczą się do obrotu, dopóki są otwarte.',
                    ),
                    for (final o in earlier) tile(o),
                    const SizedBox(height: 14),
                  ],
                  if (today.isNotEmpty) ...[
                    _SectionTitle(icon: AppIcons.clock, color: AppColors.textMuted, title: 'Dzisiaj'),
                    for (final o in today) tile(o),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.color, required this.title, this.hint});

  final AppIconData icon;
  final Color color;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Glyph(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(title, style: text.titleMedium),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// Jak długo zamówienie jest otwarte: „25 min”, „3 h 10 min”, „2 dni”.
String openFor(Duration d) {
  if (d.inDays >= 1) return d.inDays == 1 ? '1 dzień' : '${d.inDays} dni';
  if (d.inHours >= 1) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inMinutes.clamp(0, 59)} min';
}

/// Pozycje w skrócie: ile wszystkich i co jeszcze się z nimi dzieje.
String itemsSummary(PanelOrder o) {
  int count(OrderItemStatus s) => o.items.where((i) => i.status == s).fold(0, (sum, i) => sum + i.quantity);
  final all = o.active.fold(0, (sum, i) => sum + i.quantity);
  return [
    all == 0
        ? 'bez pozycji'
        : '$all ${all == 1
              ? 'pozycja'
              : (all % 10 >= 2 && all % 10 <= 4 && (all % 100 < 12 || all % 100 > 14))
              ? 'pozycje'
              : 'pozycji'}',
    if (count(OrderItemStatus.fresh) > 0) 'niewysłane: ${count(OrderItemStatus.fresh)}',
    if (count(OrderItemStatus.sent) > 0) 'na kuchni: ${count(OrderItemStatus.sent)}',
    if (count(OrderItemStatus.ready) > 0) 'do wydania: ${count(OrderItemStatus.ready)}',
  ].join(' · ');
}

class _OrderTile extends ConsumerWidget {
  const _OrderTile({required this.entry, required this.label, required this.earlier, required this.restaurantId});

  final UnclosedOrder entry;
  final String label;
  final bool earlier;
  final String restaurantId;

  /// Zakładka, w której to zamówienie się obsługuje.
  String get _route {
    final o = entry.order;
    return switch (entry.stage) {
      null => o.tableId == null ? PanelRoutes.orders : '${PanelRoutes.orders}?stolik=${o.tableId}',
      TakeawayStage.draft => PanelRoutes.orders,
      _ => o.kind == OrderKind.pickup ? PanelRoutes.pickup : PanelRoutes.deliveries,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final o = entry.order;
    final stage = entry.stage;
    final permissions = ref.watch(memberPermissionsProvider);
    final canOpen = canOpenRoute(_route, permissions);
    final canClose = permissions.contains('orders_close');
    // Rachunek na sali z pozycjami albo przyjęte zamówienie na wynos (szkic i czekające na płatność tylko anulować).
    final canSettle =
        canClose &&
        (stage == null
            ? o.active.isNotEmpty
            : stage != TakeawayStage.draft && stage != TakeawayStage.awaitingPayment);
    final (icon, color) = switch (o.kind) {
      OrderKind.dineIn => (AppIcons.forkKnife, TileColors.green),
      OrderKind.delivery => (AppIcons.moped, TileColors.violet),
      OrderKind.pickup => (AppIcons.shoppingBag, TileColors.blue),
    };
    final customer = [
      ?(o.customerName ?? o.customerCompany),
      if (o.customerPhone != null) Fmt.phone(o.customerPhone),
    ].join(' · ');
    final opened = o.openedAt.toLocal();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: earlier ? TileColors.rose.withValues(alpha: 0.45) : AppColors.ring),
      ),
      child: Row(
        children: [
          IconBadge(icon, color: color, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(label, style: text.titleMedium),
                    if (stage != null)
                      StatusChip(label: stage.label, icon: AppIcons.hourglass, color: AppColors.textMuted),
                    if (earlier)
                      StatusChip(label: 'z ${Fmt.dayShort(opened)}', icon: AppIcons.warning, color: TileColors.rose),
                    if (entry.paymentNotice case final notice?)
                      StatusChip(
                        label: notice,
                        icon: entry.payOnDelivery ? AppIcons.money : AppIcons.checkCircle,
                        color: entry.payOnDelivery ? TileColors.amber : TileColors.green,
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (customer.isNotEmpty) customer,
                    itemsSummary(o),
                    if (o.deliveryAddress != null && o.deliveryAddress!.isNotEmpty) o.deliveryAddress!,
                    if (entry.courierName != null) 'dostawca: ${entry.courierName}',
                    if (entry.openedBy != null) 'otworzył(a): ${entry.openedBy}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Fmt.price(o.billGrosze),
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontFeatures: _tabular),
              ),
              Text(
                '${earlier ? '${Fmt.dayShort(opened)}, ' : ''}${Fmt.time(opened)} · '
                '${openFor(DateTime.now().difference(opened))}',
                style: text.bodySmall?.copyWith(
                  color: earlier ? TileColors.rose : AppColors.textMuted,
                  fontFeatures: _tabular,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          if (canOpen)
            OutlinedButton(
              onPressed: () => context.go(_route),
              child: Text(stage == null ? 'Otwórz rachunek' : 'Otwórz'),
            ),
          if (canClose) ...[
            const SizedBox(width: 4),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: () => _cancel(context, ref),
              child: const Text('Anuluj'),
            ),
          ],
          if (canSettle) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: stage == null
                  ? () => showDialog<void>(
                      context: context,
                      builder: (_) => SettleDialog(restaurantId: restaurantId, orderId: o.id, title: 'Rachunek · $label'),
                    )
                  : () => _finish(context, ref),
              child: const Text('Zamknij'),
            ),
          ],
        ],
      ),
    );
  }

  void _refresh(WidgetRef ref) => ref
    ..invalidate(unclosedOrdersProvider(restaurantId))
    ..invalidate(takeawayOrdersProvider(restaurantId));

  /// Zamknięcie dostawy albo odbioru: zamówienie jest dostarczone i opłacone, także gdy dostawca go nie zamknął.
  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final method = await showDialog<PaymentMethod>(
      context: context,
      builder: (_) => _FinishDialog(entry: entry, label: label),
    );
    if (method == null) return;
    try {
      await ref
          .read(repositoryProvider)
          .finishTakeaway(entry.order.id, method, memberId: ref.read(panelMemberProvider)?.dbMemberId);
      _refresh(ref);
      if (context.mounted) showMessage(context, '$label zamknięte.', tone: ToastTone.success);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  /// Anulowanie rachunku albo zamówienia na wynos w dowolnym etapie.
  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final o = entry.order;
    final takeaway = entry.stage != null;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Anulować: $label?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                takeaway
                    ? [
                        'Zamówienie przestanie się liczyć, a gość zobaczy w aplikacji, że zostało odwołane.',
                        if (entry.stage == TakeawayStage.onTheWay) 'Dostawca jest w drodze, więc uprzedź go.',
                        if (entry.paymentChoice == 'card_online')
                          'Gość zapłacił kartą online: zwrot zrobi operator płatności.',
                      ].join(' ')
                    : 'Pozycje rachunku zostaną anulowane. Przy daniach wysłanych na kuchnię potrzebny jest kierownik.',
              ),
              if (takeaway) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Powód dla gościa (opcjonalnie)'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Wróć')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Anuluj zamówienie'),
          ),
        ],
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (ok != true) return;
    try {
      final repo = ref.read(repositoryProvider);
      if (takeaway) {
        await repo.cancelTakeaway(o.id, reason: text, memberId: ref.read(panelMemberProvider)?.dbMemberId);
      } else {
        await repo.cancelOrder(o.id);
      }
      _refresh(ref);
      if (context.mounted) showMessage(context, '$label anulowane.', tone: ToastTone.success);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// Zamknięcie dostawy albo odbioru z Niezamkniętych: przy gotówce i karcie przy odbiorze wybór, jak gość zapłacił.
class _FinishDialog extends StatefulWidget {
  const _FinishDialog({required this.entry, required this.label});

  final UnclosedOrder entry;
  final String label;

  @override
  State<_FinishDialog> createState() => _FinishDialogState();
}

class _FinishDialogState extends State<_FinishDialog> {
  late PaymentMethod _method = widget.entry.paymentChoice == 'card_on_delivery' ? PaymentMethod.card : PaymentMethod.cash;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Zamknąć: ${widget.label}?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                'Zamówienie zostanie oznaczone jako dostarczone i opłacone.',
                if (e.stage == TakeawayStage.onTheWay) 'Dostawca jest w drodze: zamykasz je za niego.',
              ].join(' '),
            ),
            const SizedBox(height: 14),
            if (e.payOnDelivery) ...[
              Text('Do zapłaty ${Fmt.price(e.order.billGrosze)}. Jak gość zapłacił?', style: text.titleSmall),
              const SizedBox(height: 10),
              SegmentedTabs<PaymentMethod>(
                options: const [
                  (PaymentMethod.cash, 'Gotówka'),
                  (PaymentMethod.card, 'Karta'),
                  (PaymentMethod.other, 'Inne'),
                ],
                selected: _method,
                onChanged: (m) => setState(() => _method = m),
              ),
            ] else
              Text(
                'Gość zapłacił z góry (${e.paymentChoice == 'prepaid' ? 'przyjęte w panelu' : 'karta online'}).',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Wróć')),
        FilledButton(onPressed: () => Navigator.pop(context, _method), child: const Text('Zamknij zamówienie')),
      ],
    );
  }
}
