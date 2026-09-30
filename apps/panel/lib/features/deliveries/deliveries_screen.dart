import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';

const _deliveryColor = Color(0xFF3B82F6);
const _pickupColor = Color(0xFF8B5CF6);
const _cashColor = Color(0xFFE08A1E);

/// Zamówienia gości z aplikacji Table: dostawa i odbiór osobisty. Nowe przyjmuje się z czasem przygotowania
/// (pozycje idą na kuchnię), gotowe dostawy rozwożą dostawcy z kolejki w Table for employees,
/// odbiór osobisty wydaje obsługa.
class DeliveriesScreen extends ConsumerStatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  ConsumerState<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends ConsumerState<DeliveriesScreen> {
  int _tab = 0;
  bool _busy = false;

  String? get _memberId => ref.read(panelMemberProvider)?.dbMemberId;

  Future<void> _run(String restaurantId, Future<void> Function() action, [String? done]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref
        ..invalidate(takeawayOrdersProvider(restaurantId))
        ..invalidate(couriersProvider(restaurantId));
      if (done != null && mounted) showMessage(context, done, tone: ToastTone.success);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(String restaurantId, TakeawayOrder order) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Odrzucić ${order.label}?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                order.cash
                    ? 'Gość zobaczy w aplikacji, że zamówienie zostało odrzucone.'
                    : 'Gość zapłacił kartą online. Zwrot zrobi operator płatności (w trybie testowym nic nie pobrano).',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Powód dla gościa (opcjonalnie)', hintText: 'Na przykład: kuchnia już zamknięta'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Wróć')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Odrzuć'),
          ),
        ],
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (ok != true) return;
    await _run(
      restaurantId,
      () => ref.read(repositoryProvider).rejectTakeaway(order.id, reason: text, memberId: _memberId),
      '${order.label} odrzucone.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    if (!restaurant.isPro) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Dostawy'),
          Expanded(child: ProGate(feature: 'Dostawy i odbiór osobisty')),
        ],
      );
    }
    final rid = restaurant.id;
    final canEdit = ref.watch(memberPermissionsProvider).contains('orders');
    final settings = ref.watch(profileProvider(rid)).value?.delivery ?? const DeliverySettings();
    final async = ref.watch(takeawayOrdersProvider(rid));
    final couriers = ref.watch(couriersProvider(rid)).value ?? const <Courier>[];
    final orders = async.value ?? const <TakeawayOrder>[];
    final active = orders.where((o) => !o.stage.finished).toList();
    final finished = orders.where((o) => o.stage.finished).toList()
      ..sort((a, b) => (b.closedAt ?? b.openedAt).compareTo(a.closedAt ?? a.openedAt));

    final subtitle = !settings.any
        ? 'Dostawa i odbiór osobisty są wyłączone. Włącz je w „Dane lokalu” → „Dostawa i odbiór”.'
        : [
            if (settings.deliveryEnabled) 'dostawa',
            if (settings.pickupEnabled) 'odbiór osobisty',
            settings.cash ? 'gotówka i karta online' : 'tylko karta online',
            '${couriers.length} ${couriers.length == 1 ? 'dostawca' : 'dostawców'} na zmianie',
          ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Dostawy',
          subtitle: Fmt.capitalize(subtitle),
          below: Row(
            children: [
              IconTabs<int>(
                options: [
                  (0, AppIcons.moped, 'Aktywne (${active.length})'),
                  (1, AppIcons.checkCircle, 'Zakończone dziś (${finished.length})'),
                ],
                selected: _tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
              const Spacer(),
              if (couriers.isNotEmpty) _CouriersStrip(couriers: couriers),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(takeawayOrdersProvider(rid))),
            data: (_) {
              if (_tab == 1) return _FinishedList(orders: finished);
              if (active.isEmpty) {
                return MessageView(
                  icon: AppIcons.moped,
                  title: 'Brak zamówień na wynos',
                  message: settings.any
                      ? 'Nowe zamówienia z aplikacji Table pojawią się tutaj z dźwiękiem.'
                      : 'Włącz dostawę albo odbiór osobisty w „Dane lokalu”, żeby goście mogli zamawiać w aplikacji.',
                );
              }
              Widget column(String title, Color color, List<TakeawayOrder> list) => Expanded(
                child: _Column(
                  title: title,
                  color: color,
                  count: list.length,
                  children: [
                    for (final o in list)
                      _OrderCard(
                        order: o,
                        couriers: couriers,
                        busy: _busy || !canEdit,
                        onAccept: (minutes) => _run(
                          rid,
                          () => ref.read(repositoryProvider).acceptTakeaway(o.id, minutes, memberId: _memberId),
                          '${o.label} przyjęte: gotowe ok. ${_hm(DateTime.now().add(Duration(minutes: minutes)))}.',
                        ),
                        onReject: () => _reject(rid, o),
                        onReady: () => _run(rid, () => ref.read(repositoryProvider).takeawayReady(o.id), '${o.label} gotowe.'),
                        onHanded: () => _run(
                          rid,
                          () => ref.read(repositoryProvider).takeawayHanded(o.id, memberId: _memberId),
                          '${o.label} wydane gościowi.',
                        ),
                        onAssign: (courierId) => _run(
                          rid,
                          () => ref.read(repositoryProvider).assignCourier(o.id, courierId),
                          courierId == null ? 'Kurs wrócił do kolejki.' : 'Dostawca zmieniony.',
                        ),
                      ),
                  ],
                ),
              );
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    column('Nowe', _cashColor, active.where((o) => o.stage == TakeawayStage.placed).toList()),
                    const SizedBox(width: 16),
                    column('W przygotowaniu', AppColors.textMuted, active.where((o) => o.stage == TakeawayStage.accepted).toList()),
                    const SizedBox(width: 16),
                    column(
                      'Gotowe i w drodze',
                      AppColors.accent,
                      active.where((o) => o.stage == TakeawayStage.ready || o.stage == TakeawayStage.onTheWay).toList(),
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

class _Column extends StatelessWidget {
  const _Column({required this.title, required this.color, required this.count, required this.children});

  final String title;
  final Color color;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(title, style: text.titleSmall),
              const SizedBox(width: 6),
              Text('$count', style: text.titleSmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular)),
            ],
          ),
        ),
        Expanded(
          child: children.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.ring),
                  ),
                  alignment: Alignment.center,
                  child: Text('Pusto', style: text.bodyMedium?.copyWith(color: AppColors.textDisabled)),
                )
              : ListView.separated(
                  itemCount: children.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => children[i],
                ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatefulWidget {
  const _OrderCard({
    required this.order,
    required this.couriers,
    required this.busy,
    required this.onAccept,
    required this.onReject,
    required this.onReady,
    required this.onHanded,
    required this.onAssign,
  });

  final TakeawayOrder order;
  final List<Courier> couriers;
  final bool busy;
  final ValueChanged<int> onAccept;
  final VoidCallback onReject;
  final VoidCallback onReady;
  final VoidCallback onHanded;
  final ValueChanged<String?> onAssign;

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  int _minutes = 30;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final o = widget.order;
    final delivery = o.kind == OrderKind.delivery;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('#${o.number}', style: text.titleLarge?.copyWith(fontFeatures: _tabular)),
                const SizedBox(width: 8),
                Tag(delivery ? 'DOSTAWA' : 'ODBIÓR', color: delivery ? _deliveryColor : _pickupColor),
                const Spacer(),
                Text(
                  o.promisedAt != null ? 'na ${_hm(o.promisedAt!)}' : 'z ${_hm(o.openedAt)}',
                  style: text.titleSmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${o.customerName} · ${o.customerPhone}', style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
            if (o.address != null) Text(o.address!, style: text.titleSmall),
            if (o.note != null)
              Text(o.note!, style: text.bodySmall?.copyWith(color: _cashColor, fontStyle: FontStyle.italic)),
            const SizedBox(height: 10),
            for (final i in o.active)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${i.quantity}× ${[i.name, ?i.details].join(' · ')}',
                  style: text.bodyMedium,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Glyph(o.cash ? AppIcons.money : AppIcons.creditCard, size: 16, color: o.cash ? _cashColor : AppColors.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    o.cash
                        ? 'Gotówka ${delivery ? 'u dostawcy' : 'przy odbiorze'}'
                        : 'Karta online · opłacone${o.testPayment ? ' (test)' : ''}',
                    style: muted,
                  ),
                ),
                Text(Fmt.price(o.totalGrosze), style: text.titleMedium?.copyWith(fontFeatures: _tabular)),
              ],
            ),
            if (delivery && o.stage != TakeawayStage.placed) ...[
              const SizedBox(height: 10),
              _CourierRow(order: o, couriers: widget.couriers, busy: widget.busy, onAssign: widget.onAssign),
            ],
            const SizedBox(height: 12),
            ..._actions(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final o = widget.order;
    final busy = widget.busy;
    const compact = Size(0, 44);
    switch (o.stage) {
      case TakeawayStage.placed:
        return [
          Text('Czas przygotowania', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 6),
          SegmentedTabs<int>(
            options: const [(15, '15 min'), (30, '30'), (45, '45'), (60, '60')],
            selected: _minutes,
            onChanged: (m) => setState(() => _minutes = m),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                onPressed: busy ? null : widget.onReject,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Odrzuć'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: compact),
                  onPressed: busy ? null : () => widget.onAccept(_minutes),
                  child: Text('Przyjmij · $_minutes min'),
                ),
              ),
            ],
          ),
        ];
      case TakeawayStage.accepted:
        return [
          Row(
            children: [
              TextButton(
                onPressed: busy ? null : widget.onReject,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Odrzuć'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: compact),
                  onPressed: busy ? null : widget.onReady,
                  child: const Text('Gotowe'),
                ),
              ),
            ],
          ),
        ];
      case TakeawayStage.ready when o.kind == OrderKind.pickup:
        return [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: compact),
            onPressed: busy ? null : widget.onHanded,
            child: Text(o.cash ? 'Wydane · pobrano ${Fmt.price(o.totalGrosze)}' : 'Wydane gościowi'),
          ),
        ];
      case TakeawayStage.ready:
        return [
          Text(
            o.courierName == null ? 'Czeka na wolnego dostawcę.' : '${o.courierName} odbierze zamówienie z lokalu.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ];
      case TakeawayStage.onTheWay:
        return [
          Text(
            'W drodze${o.pickedUpAt == null ? '' : ' od ${_hm(o.pickedUpAt!)}'}.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _deliveryColor),
          ),
        ];
      default:
        return const [];
    }
  }
}

/// Dostawca przydzielony przez kolejkę. Przed wyjazdem można go zmienić albo oddać kurs kolejce.
class _CourierRow extends StatelessWidget {
  const _CourierRow({required this.order, required this.couriers, required this.busy, required this.onAssign});

  final TakeawayOrder order;
  final List<Courier> couriers;
  final bool busy;
  final ValueChanged<String?> onAssign;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final canChange = !busy && (order.stage == TakeawayStage.accepted || order.stage == TakeawayStage.ready);
    final label = Row(
      children: [
        Glyph(AppIcons.moped, size: 16, color: order.courierName == null ? _cashColor : _deliveryColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            order.courierName ?? 'Czeka na wolnego dostawcę',
            style: text.bodyMedium?.copyWith(color: order.courierName == null ? _cashColor : null),
          ),
        ),
        if (canChange) Glyph(AppIcons.caretDown, size: 14, color: AppColors.textMuted),
      ],
    );
    if (!canChange) return label;
    return PopupMenuButton<String>(
      tooltip: 'Zmień dostawcę',
      onSelected: (v) => onAssign(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        if (order.courierId != null) const PopupMenuItem(value: '', child: Text('Oddaj kolejce (następny wolny)')),
        for (final c in couriers)
          if (c.memberId != order.courierId)
            PopupMenuItem(value: c.memberId, child: Text('${c.name}${c.busy ? ' · w kursie' : ' · wolny'}')),
      ],
      child: label,
    );
  }
}

/// Dostawcy na zmianie: kto wolny, kto w kursie.
class _CouriersStrip extends StatelessWidget {
  const _CouriersStrip({required this.couriers});

  final List<Courier> couriers;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: 8,
      children: [
        for (final c in couriers)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: c.busy ? _deliveryColor : AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(c.name, style: text.labelLarge),
              ],
            ),
          ),
      ],
    );
  }
}

class _FinishedList extends StatelessWidget {
  const _FinishedList({required this.orders});

  final List<TakeawayOrder> orders;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (orders.isEmpty) {
      return const MessageView(
        icon: AppIcons.checkCircle,
        title: 'Dziś jeszcze nic',
        message: 'Tu pojawią się dostarczone, wydane i odrzucone zamówienia z dzisiaj.',
      );
    }
    final done = orders.where((o) => o.stage == TakeawayStage.delivered).toList();
    final sum = done.fold(0, (s, o) => s + o.totalGrosze);
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      children: [
        Text(
          'Zrealizowane: ${done.length} · ${Fmt.price(sum)}',
          style: text.titleSmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, o) in orders.indexed) ...[
                if (i > 0) Divider(height: 1, color: AppColors.ring),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(width: 60, child: Text('#${o.number}', style: text.titleSmall?.copyWith(fontFeatures: _tabular))),
                      SizedBox(
                        width: 90,
                        child: Tag(
                          o.kind == OrderKind.delivery ? 'DOSTAWA' : 'ODBIÓR',
                          color: o.kind == OrderKind.delivery ? _deliveryColor : _pickupColor,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          [o.customerName, ?o.address, if (o.courierName != null) 'dostawca: ${o.courierName}'].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        switch (o.stage) {
                          TakeawayStage.delivered => o.kind == OrderKind.delivery ? 'Dostarczone' : 'Wydane',
                          TakeawayStage.rejected => 'Odrzucone',
                          _ => 'Odwołane przez gościa',
                        },
                        style: text.bodySmall?.copyWith(
                          color: o.stage == TakeawayStage.delivered ? AppColors.accent : AppColors.error,
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 90,
                        child: Text(
                          Fmt.price(o.totalGrosze),
                          textAlign: TextAlign.right,
                          style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          o.closedAt == null ? '' : _hm(o.closedAt!),
                          textAlign: TextAlign.right,
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
