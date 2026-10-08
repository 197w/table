import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import 'settle_dialog.dart';
import 'takeaway_form.dart';
import '../floor/floor_canvas.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Zamówienia przy stoliku: kelner wybiera stolik, nabija pozycje z menu,
/// wysyła je na kuchnię i zamyka rachunek. Układ jest pod dotyk, żeby działał też na tablecie.
/// „Nowe zamówienie” na górze listy stolików przyjmuje też dostawę i odbiór osobisty (np. przez telefon):
/// dane klienta, dania z menu i „Przyjmij”, po którym zamówienie idzie na kuchnię i do Dostaw.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key, this.tableId});

  /// Stolik otwarty od razu, np. po kliknięciu „Zamówienie” na planie sali.
  final String? tableId;

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  late String? _tableId = widget.tableId;

  /// Wybrany szkic zamówienia na wynos (zamiast stolika).
  String? _takeawayId;

  /// Czas przygotowania przy „Przyjmij” zamówienia na wynos.
  int _prepMinutes = 30;
  String? _sectionId;
  String _query = '';
  final _search = TextEditingController();

  /// Kolejka zmian rachunku. Kelner stuka szybko, a każde stuknięcie musi trafić do bazy
  /// po kolei, bez gubienia i bez podwójnego otwierania rachunku.
  Future<void> _queue = Future.value();

  @override
  void didUpdateWidget(covariant OrdersScreen old) {
    super.didUpdateWidget(old);
    if (widget.tableId != null && widget.tableId != old.tableId) {
      setState(() {
        _tableId = widget.tableId;
        _takeawayId = null;
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Dokłada zmianę na koniec kolejki i odświeża rachunki, gdy przejdzie.
  Future<void> _enqueue(String restaurantId, Future<void> Function() action) {
    final next = _queue.then((_) async {
      try {
        await action();
      } catch (e) {
        if (mounted) showError(context, e);
      } finally {
        if (mounted) ref.invalidate(openOrdersProvider(restaurantId));
      }
    });
    _queue = next;
    return next;
  }

  /// Otwarty rachunek stolika. Gdy lista z bazy jeszcze go nie zna, pyta bazę:
  /// otwarcie zwraca istniejący rachunek, więc dwa szybkie stuknięcia nie otworzą dwóch.
  Future<String> _orderIdFor(String restaurantId, String tableId) async {
    final order = _orderOf(restaurantId, tableId);
    if (order != null) return order.id;
    return ref
        .read(repositoryProvider)
        .openOrder(restaurantId, tableId, memberId: ref.read(panelMemberProvider)?.dbMemberId);
  }

  /// Dokłada pozycję do rachunku stolika albo szkicu na wynos ([orderId] daje numer rachunku).
  Future<void> _add(
    String restaurantId,
    Future<String> Function() orderId,
    MenuItem item, {
    bool withOptions = false,
  }) async {
    if (!item.available) {
      showMessage(context, '„${item.name}” jest chwilowo niedostępne.');
      return;
    }
    final _Choice choice;
    if (item.hasOptions || withOptions) {
      final picked = await showDialog<_Choice>(
        context: context,
        builder: (_) => _AddItemDialog(item: item),
      );
      if (picked == null || !mounted) return;
      choice = picked;
    } else {
      choice = const _Choice();
    }
    HapticFeedback.selectionClick();
    final repo = ref.read(repositoryProvider);
    unawaited(
      _enqueue(restaurantId, () async {
        await repo.addOrderItem(
          orderId: await orderId(),
          menuItemId: item.id,
          variant: choice.variant,
          addons: choice.addons,
          quantity: choice.quantity,
          note: choice.note,
          changes: choice.changes,
          memberId: ref.read(panelMemberProvider)?.dbMemberId,
        );
        if (_takeawayId != null) ref.invalidate(takeawayDraftsProvider(restaurantId));
      }),
    );
  }

  PanelOrder? _orderOf(String restaurantId, String tableId) {
    final orders = ref.read(openOrdersProvider(restaurantId)).value ?? const [];
    for (final o in orders) {
      if (o.tableId == tableId) return o;
    }
    return null;
  }

  Future<void> _send(String restaurantId, PanelOrder order) async {
    var count = 0;
    await _enqueue(restaurantId, () async {
      count = await ref.read(repositoryProvider).sendOrder(order.id);
    });
    if (mounted && count > 0) {
      showMessage(context, count == 1 ? 'Wysłano 1 pozycję na kuchnię.' : 'Wysłano na kuchnię: $count.');
    }
  }

  Future<void> _close(String restaurantId, DiningTable table, PanelOrder order) async {
    // Okno samo zamyka rachunek (całość, równo albo po pozycjach) i pokazuje potwierdzenie.
    final closed = await showDialog<bool>(
      context: context,
      builder: (_) => SettleDialog(restaurantId: restaurantId, orderId: order.id, title: 'Rachunek · stolik ${table.label}'),
    );
    if (closed != true || !mounted) return;
    // Zamknięty rachunek kończy też wizytę z rezerwacji, więc plan sali musi się odświeżyć.
    ref.invalidate(reservationsProvider((restaurantId: restaurantId, day: dateOnly(DateTime.now()))));
  }

  /// Kelner zaniósł wszystko, co kuchnia zbiła.
  Future<void> _serveAll(String restaurantId, List<OrderItem> items) {
    return _enqueue(restaurantId, () async {
      final repo = ref.read(repositoryProvider);
      for (final i in items) {
        await repo.updateOrderItem(i.id, status: OrderItemStatus.served);
      }
    });
  }

  Future<void> _cancel(String restaurantId, DiningTable table, PanelOrder order) async {
    final sent = order.items.any((i) => i.status != OrderItemStatus.fresh);
    final ok = await confirm(
      context,
      title: 'Anulować rachunek?',
      message: sent
          ? 'Część pozycji jest już na kuchni. Anulować taki rachunek może tylko kierownik albo właściciel.'
          : 'Wszystkie pozycje znikną z rachunku stolika ${table.label}.',
      action: 'Anuluj rachunek',
      destructive: true,
    );
    if (!ok) return;
    await _enqueue(restaurantId, () => ref.read(repositoryProvider).cancelOrder(order.id));
  }

  Future<void> _move(
    String restaurantId,
    DiningTable from,
    PanelOrder order,
    List<DiningTable> tables,
    List<PanelOrder> orders,
  ) async {
    final busy = {for (final o in orders) ?o.tableId};
    final target = await showDialog<DiningTable>(
      context: context,
      builder: (_) => _MoveDialog(
        from: from,
        tables: tables.where((t) => t.id != from.id && !busy.contains(t.id)).toList(),
      ),
    );
    if (target == null || !mounted) return;
    var ok = false;
    await _enqueue(restaurantId, () async {
      await ref.read(repositoryProvider).moveOrder(order.id, target.id!);
      ok = true;
    });
    if (!ok || !mounted) return;
    setState(() => _tableId = target.id);
    showMessage(context, 'Rachunek przeniesiony na stolik ${target.label}.');
  }

  Future<void> _itemMenu(String restaurantId, Future<String> Function()? target, MenuItem item, Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      color: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.ringStrong),
      ),
      items: [
        if (target != null && item.available)
          const PopupMenuItem(value: 'note', child: Text('Dodaj ze zmianą składników albo uwagą…')),
        if (ref.read(memberPermissionsProvider).contains('menu_availability'))
          PopupMenuItem(
            value: 'toggle',
            child: Text(item.available ? 'Skończyło się (niedostępne)' : 'Znowu dostępne'),
          ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'note' && target != null) {
      await _add(restaurantId, target, item, withOptions: true);
      return;
    }
    try {
      await ref.read(repositoryProvider).setItemAvailable(item.id, !item.available);
      ref.invalidate(menuProvider(restaurantId));
      if (mounted) {
        showMessage(
          context,
          item.available ? '„${item.name}” oznaczone jako niedostępne.' : '„${item.name}” znowu dostępne.',
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String? get _memberId => ref.read(panelMemberProvider)?.dbMemberId;

  /// „Nowe zamówienie”: stolik w lokalu albo dostawa lub odbiór z danymi klienta (szkic do uzupełnienia daniami).
  Future<void> _newOrder(PanelRestaurant restaurant, List<DiningTable> tables, List<PanelOrder> orders) async {
    final choice = await showDialog<NewOrderChoice>(
      context: context,
      builder: (_) => NewOrderDialog(restaurantId: restaurant.id, city: restaurant.city, tables: tables, orders: orders),
    );
    if (choice == null || !mounted) return;
    if (choice.table case final table?) {
      setState(() {
        _tableId = table.id;
        _takeawayId = null;
      });
      return;
    }
    final kind = choice.kind!;
    try {
      final id = await ref
          .read(repositoryProvider)
          .createTakeaway(restaurant.id, kind, choice.customer!, memberId: _memberId);
      ref.invalidate(takeawayDraftsProvider(restaurant.id));
      if (!mounted) return;
      setState(() {
        _takeawayId = id;
        _tableId = null;
      });
      showMessage(context, 'Dane klienta zapisane. Dodaj dania z menu i kliknij „Przyjmij”.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _editTakeaway(String restaurantId, TakeawayOrder order) async {
    final customer = await showDialog<TakeawayCustomer>(
      context: context,
      builder: (_) => TakeawayEditDialog(restaurantId: restaurantId, order: order),
    );
    if (customer == null || !mounted) return;
    await _enqueue(restaurantId, () async {
      await ref.read(repositoryProvider).updateTakeaway(order.id, customer, memberId: _memberId);
      ref
        ..invalidate(takeawayDraftsProvider(restaurantId))
        ..invalidate(customerLookupProvider);
    });
  }

  Future<void> _submitTakeaway(String restaurantId, TakeawayOrder order) async {
    var ok = false;
    await _enqueue(restaurantId, () async {
      await ref.read(repositoryProvider).submitTakeaway(order.id, _prepMinutes, memberId: _memberId);
      ok = true;
    });
    if (!ok || !mounted) return;
    ref
      ..invalidate(takeawayDraftsProvider(restaurantId))
      ..invalidate(takeawayOrdersProvider(restaurantId));
    setState(() => _takeawayId = null);
    showMessage(
      context,
      '${order.label} przyjęte: gotowe ok. ${Fmt.time(DateTime.now().add(Duration(minutes: _prepMinutes)))}. '
      'Jest na kuchni i w zakładce Dostawy.',
      tone: ToastTone.success,
    );
  }

  Future<void> _discardTakeaway(String restaurantId, TakeawayOrder order) async {
    final ok = await confirm(
      context,
      title: 'Porzucić ${order.label}?',
      message: 'Zamówienie i dodane dania znikną. Nic nie poszło jeszcze na kuchnię.',
      action: 'Porzuć',
      destructive: true,
    );
    if (!ok) return;
    await _enqueue(restaurantId, () => ref.read(repositoryProvider).discardTakeaway(order.id));
    ref.invalidate(takeawayDraftsProvider(restaurantId));
    if (mounted) setState(() => _takeawayId = null);
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();

    if (!restaurant.isPro) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: ProGate(feature: 'Zamówienia przy stoliku')),
        ],
      );
    }

    // Pracownika zalogowanego w tej zakładce i jego uprawnienia pilnuje układ panelu (PanelShell).
    final permissions = ref.watch(memberPermissionsProvider);
    final canClose = permissions.contains('orders_close');
    final canCancel = permissions.contains('orders_cancel');

    // Dostęp do zakładki sprawdza boczne menu (PanelShell) według uprawnień stanowiska.
    final tablesAsync = ref.watch(tablesProvider(restaurant.id));
    final zones = ref.watch(zonesProvider(restaurant.id)).value ?? const <FloorZone>[];
    final menuAsync = ref.watch(menuProvider(restaurant.id));
    final ordersAsync = ref.watch(openOrdersProvider(restaurant.id));
    final live = ref.watch(ordersLiveProvider(restaurant.id).select((s) => s.status));
    final today = ref.watch(
      reservationsProvider((restaurantId: restaurant.id, day: dateOnly(DateTime.now()))),
    ).value ?? const <PanelReservation>[];

    final tables = tablesAsync.value ?? const <DiningTable>[];
    final orders = ordersAsync.value ?? const <PanelOrder>[];
    final drafts = ref.watch(takeawayDraftsProvider(restaurant.id)).value ?? const <TakeawayOrder>[];
    TakeawayOrder? draft;
    for (final d in drafts) {
      if (d.id == _takeawayId) draft = d;
    }
    // Czas oczekiwania stolików na jedzenie: progi z ustawień kuchni, odświeżanie co 30 s.
    final kitchen = ref.watch(kitchenConfigProvider(restaurant.id)).value ?? const KitchenConfig();
    if (orders.any((o) => o.waitingSince != null)) ref.watch(clockProvider);
    DiningTable? table;
    for (final t in tables) {
      if (draft == null && t.id == _tableId) table = t;
    }
    PanelOrder? order;
    for (final o in orders) {
      if (table != null && o.tableId == table.id) order = o;
    }
    PanelReservation? reservation;
    for (final r in today) {
      if (order?.reservationId == r.id) reservation = r;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          actions: [
            switch (live) {
              LiveStatus.live => const PanelPill('Na żywo', dotColor: Color(0xFF2FB673)),
              LiveStatus.connecting => const PanelPill('Łączenie…', dotColor: Color(0xFFD99A15)),
              LiveStatus.offline => PanelPill('Brak połączenia', dotColor: AppColors.error),
            },
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
            child: tablesAsync.when(
              skipLoadingOnReload: true,
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(tablesProvider(restaurant.id)),
              ),
              data: (_) {
                if (tables.isEmpty) {
                  return const MessageView(
                    icon: AppIcons.squaresFour,
                    title: 'Sala jest pusta',
                    message: 'Rozstaw stoliki w zakładce „Edycja sali”, a tutaj nabijesz do nich zamówienia.',
                  );
                }
                // Rachunek, do którego trafiają dania z menu: stolika albo szkicu na wynos.
                final Future<String> Function()? target = draft != null
                    ? (() async => draft!.id)
                    : table != null
                    ? (() => _orderIdFor(restaurant.id, table!.id!))
                    : null;
                return LayoutBuilder(
                  builder: (context, c) {
                    // Na wąskim oknie kolumny stolików i rachunku się zwężają, żeby menu miało miejsce.
                    final wide = c.maxWidth >= 1150;
                    final tablesWidth = wide ? 260.0 : 190.0;
                    final orderWidth = wide ? 400.0 : 330.0;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: tablesWidth,
                          child: _TablesPanel(
                            zones: zones,
                            tables: tables,
                            orders: orders,
                            drafts: drafts,
                            selectedId: table?.id,
                            selectedDraftId: draft?.id,
                            kitchen: kitchen,
                            onSelect: (t) => setState(() {
                              _tableId = t.id;
                              _takeawayId = null;
                            }),
                            onSelectDraft: (d) => setState(() {
                              _takeawayId = d.id;
                              _tableId = null;
                            }),
                            onNewOrder: () => _newOrder(restaurant, tables, orders),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _MenuPanel(
                            async: menuAsync,
                            sectionId: _sectionId,
                            query: _query,
                            search: _search,
                            enabled: table != null || draft != null,
                            onSection: (id) => setState(() => _sectionId = id),
                            onQuery: (q) => setState(() => _query = q.trim().toLowerCase()),
                            onRetry: () => ref.invalidate(menuProvider(restaurant.id)),
                            onTap: (item) => target == null
                                ? showMessage(context, 'Najpierw wybierz stolik albo „Nowe zamówienie” po lewej.')
                                : _add(restaurant.id, target, item),
                            onOptions: (item) => target == null
                                ? showMessage(context, 'Najpierw wybierz stolik albo „Nowe zamówienie” po lewej.')
                                : _add(restaurant.id, target, item, withOptions: true),
                            onMenu: (item, at) => _itemMenu(restaurant.id, target, item, at),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: orderWidth,
                          child: draft != null
                              ? _TakeawayPanel(
                                  restaurantId: restaurant.id,
                                  order: draft,
                                  minutes: _prepMinutes,
                                  onMinutes: (m) => setState(() => _prepMinutes = m),
                                  onEdit: () => _editTakeaway(restaurant.id, draft!),
                                  onDiscard: () => _discardTakeaway(restaurant.id, draft!),
                                  onSubmit: () => _submitTakeaway(restaurant.id, draft!),
                                  onQuantity: (item, q) => _enqueue(restaurant.id, () async {
                                    await (q < 1
                                        ? ref.read(repositoryProvider).updateOrderItem(item.id, status: OrderItemStatus.cancelled)
                                        : ref.read(repositoryProvider).updateOrderItem(item.id, quantity: q));
                                    ref.invalidate(takeawayDraftsProvider(restaurant.id));
                                  }),
                                  onNote: (item) async {
                                    final note = await showDialog<String>(
                                      context: context,
                                      builder: (_) => _NoteDialog(initial: item.note ?? ''),
                                    );
                                    if (note == null) return;
                                    await _enqueue(restaurant.id, () async {
                                      await ref.read(repositoryProvider).updateOrderItem(item.id, note: note);
                                      ref.invalidate(takeawayDraftsProvider(restaurant.id));
                                    });
                                  },
                                )
                              : table == null
                              ? const Card(
                                  child: MessageView(
                                    icon: AppIcons.receipt,
                                    title: 'Wybierz stolik',
                                    message: 'Stoliki z otwartym rachunkiem mają kwotę przy numerze. '
                                        'Dostawę i odbiór przyjmiesz przyciskiem „Nowe zamówienie”.',
                                  ),
                                )
                              : _OrderPanel(
                                  table: table,
                                  order: order,
                                  reservation: reservation,
                                  kitchen: kitchen,
                                  onQuantity: (item, q) => _enqueue(
                                    restaurant.id,
                                    () => q < 1
                                        ? ref
                                              .read(repositoryProvider)
                                              .updateOrderItem(item.id, status: OrderItemStatus.cancelled)
                                        : ref.read(repositoryProvider).updateOrderItem(item.id, quantity: q),
                                  ),
                                  onNote: (item) async {
                                    final note = await showDialog<String>(
                                      context: context,
                                      builder: (_) => _NoteDialog(initial: item.note ?? ''),
                                    );
                                    if (note == null) return;
                                    await _enqueue(
                                      restaurant.id,
                                      () => ref.read(repositoryProvider).updateOrderItem(item.id, note: note),
                                    );
                                  },
                                  onStatus: (item, status) async {
                                    if (status == OrderItemStatus.cancelled) {
                                      final ok = await confirm(
                                        context,
                                        title: 'Anulować „${item.name}”?',
                                        message: 'Pozycja jest już na kuchni. Kuchnia zobaczy ją jako anulowaną.',
                                        action: 'Anuluj pozycję',
                                        destructive: true,
                                      );
                                      if (!ok) return;
                                    }
                                    await _enqueue(
                                      restaurant.id,
                                      () => ref.read(repositoryProvider).updateOrderItem(item.id, status: status),
                                    );
                                  },
                                  onServeAll: (items) => _serveAll(restaurant.id, items),
                                  onSend: order == null ? null : () => _send(restaurant.id, order!),
                                  // Zamknięcie i anulowanie wymagają osobnych uprawnień stanowiska.
                                  onClose: order == null || !canClose
                                      ? null
                                      : () => _close(restaurant.id, table!, order!),
                                  onCancel: order == null || !canCancel
                                      ? null
                                      : () => _cancel(restaurant.id, table!, order!),
                                  canCancelSent: canCancel,
                                  onMove: order == null
                                      ? null
                                      : () => _move(restaurant.id, table!, order!, tables, orders),
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Numery stolików rosną jak liczby: 2 przed 10, a „B1” za „12”.
int compareLabels(String a, String b) {
  final na = int.tryParse(a);
  final nb = int.tryParse(b);
  if (na != null && nb != null) return na.compareTo(nb);
  if (na != null) return -1;
  if (nb != null) return 1;
  return a.toLowerCase().compareTo(b.toLowerCase());
}

// ---------------------------------------------------------------
// Stoliki
// ---------------------------------------------------------------

class _TablesPanel extends StatelessWidget {
  const _TablesPanel({
    required this.zones,
    required this.tables,
    required this.orders,
    required this.drafts,
    required this.selectedId,
    required this.selectedDraftId,
    required this.kitchen,
    required this.onSelect,
    required this.onSelectDraft,
    required this.onNewOrder,
  });

  final List<FloorZone> zones;
  final List<DiningTable> tables;
  final List<PanelOrder> orders;
  final List<TakeawayOrder> drafts;
  final String? selectedId;
  final String? selectedDraftId;

  /// Progi czasu oczekiwania (żółty, czerwony) z ustawień kuchni.
  final KitchenConfig kitchen;
  final ValueChanged<DiningTable> onSelect;
  final ValueChanged<TakeawayOrder> onSelectDraft;
  final VoidCallback onNewOrder;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final byTable = {for (final o in orders) ?o.tableId: o};
    final zoneList = orderedZones(zones, tables);

    // Karta przycina zawartość, a lista ma odstęp od góry i dołu, żeby suwak nie wychodził poza zaokrąglony obrys.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: FilledButton.icon(
              onPressed: onNewOrder,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Glyph(AppIcons.plus, size: 18),
              label: const Text('Nowe zamówienie'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
              children: [
          if (drafts.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: Text(
                'NA WYNOS · DO PRZYJĘCIA',
                style: text.labelSmall?.copyWith(color: AppColors.textDisabled, fontWeight: FontWeight.w600),
              ),
            ),
            for (final d in drafts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _DraftTile(order: d, selected: d.id == selectedDraftId, onTap: () => onSelectDraft(d)),
              ),
          ],
          for (final zone in zoneList) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: Text(
                zone.name.toUpperCase(),
                style: text.labelSmall?.copyWith(
                  color: AppColors.textDisabled,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final t in tables.where((t) => t.zone == zone.name).toList()
              ..sort((a, b) => compareLabels(a.label, b.label)))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _TableTile(
                  table: t,
                  order: byTable[t.id],
                  selected: t.id == selectedId,
                  kitchen: kitchen,
                  onTap: () => onSelect(t),
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

/// Szkic zamówienia na wynos na liście: numer, klient i kwota.
class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.order, required this.selected, required this.onTap});

  final TakeawayOrder order;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final delivery = order.kind == OrderKind.delivery;
    return PanelPress(
      scale: 0.98,
      child: Material(
        color: selected ? AppColors.surfaceRaised : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? AppColors.accent : Colors.transparent),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD99A15).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFD99A15)),
                  ),
                  child: Glyph(delivery ? AppIcons.moped : AppIcons.shoppingBag, size: 17, color: const Color(0xFFD99A15)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelLarge),
                      Text(
                        [order.company ?? order.customerName, if (order.active.isNotEmpty) Fmt.price(order.totalGrosze)]
                            .join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Czas oczekiwania stolika na jedzenie, np. „12 min”, i kolor według progów kuchni.
(String, Color) _waitLabel(DateTime since, KitchenConfig kitchen) {
  final minutes = DateTime.now().difference(since).inMinutes;
  final color = minutes >= kitchen.lateMinutes
      ? const Color(0xFFE5484D)
      : minutes >= kitchen.warnMinutes
      ? const Color(0xFFD99A15)
      : AppColors.textMuted;
  return (minutes < 1 ? '<1 min' : '$minutes min', color);
}

class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.table,
    required this.order,
    required this.selected,
    required this.kitchen,
    required this.onTap,
  });

  final DiningTable table;
  final PanelOrder? order;
  final bool selected;
  final KitchenConfig kitchen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final open = order != null;
    final unsent = order?.unsent ?? 0;
    final ready = order?.ready ?? 0;
    final waiting = order?.waitingSince;
    final wait = waiting == null ? null : _waitLabel(waiting, kitchen);

    return PanelPress(
      scale: 0.98,
      child: Material(
        color: selected ? AppColors.surfaceRaised : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? AppColors.accent : Colors.transparent),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: Colors.transparent,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  // Kostka z numerem: zielona, gdy przy stoliku jest otwarty rachunek.
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: open ? AppColors.accentTint : AppColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: open ? AppColors.accent : AppColors.ringStrong),
                    ),
                    child: Text(
                      table.label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: text.labelLarge?.copyWith(
                        color: open ? AppColors.accent : AppColors.text,
                        fontSize: table.label.length > 3 ? 11 : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          open ? Fmt.price(order!.totalGrosze) : '${table.seats} os.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (open ? text.labelLarge : text.bodyMedium)?.copyWith(
                            color: open ? AppColors.text : AppColors.textMuted,
                            fontFeatures: _tabular,
                          ),
                        ),
                        // Ile stolik czeka na jedzenie od wysłania na kuchnię.
                        if (wait != null)
                          Tooltip(
                            message: 'Stolik czeka na danie od ${Fmt.time(waiting!)}',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Glyph(AppIcons.clock, size: 12, color: wait.$2),
                                const SizedBox(width: 4),
                                Text(
                                  wait.$1,
                                  style: text.labelSmall?.copyWith(color: wait.$2, fontFeatures: _tabular),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Zielony licznik: kuchnia zbiła dania, trzeba je zanieść.
                  if (ready > 0) ...[
                    Tooltip(
                      message: 'Kuchnia skończyła: do wydania',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accentFill,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$ready',
                          style: text.labelSmall?.copyWith(
                            color: AppColors.onAccent,
                            fontWeight: FontWeight.w600,
                            fontFeatures: _tabular,
                          ),
                        ),
                      ),
                    ),
                    if (unsent > 0) const SizedBox(width: 4),
                  ],
                  if (unsent > 0)
                    Tooltip(
                      message: 'Nowe pozycje czekają na wysłanie na kuchnię',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD99A15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$unsent',
                          style: text.labelSmall?.copyWith(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                            fontFeatures: _tabular,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Menu do nabijania
// ---------------------------------------------------------------

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({
    required this.async,
    required this.sectionId,
    required this.query,
    required this.search,
    required this.enabled,
    required this.onSection,
    required this.onQuery,
    required this.onRetry,
    required this.onTap,
    required this.onOptions,
    required this.onMenu,
  });

  final AsyncValue<List<MenuSection>> async;
  final String? sectionId;
  final String query;
  final TextEditingController search;

  /// Bez wybranego stolika pozycje są przygaszone.
  final bool enabled;
  final ValueChanged<String> onSection;
  final ValueChanged<String> onQuery;
  final VoidCallback onRetry;
  final ValueChanged<MenuItem> onTap;

  /// Dodanie ze zmianą składników albo uwagą.
  final ValueChanged<MenuItem> onOptions;
  final void Function(MenuItem item, Offset globalPosition) onMenu;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: async.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: onRetry),
        data: (sections) {
          final withItems = sections.where((s) => s.items.isNotEmpty).toList();
          if (withItems.isEmpty) {
            return const MessageView(
              icon: AppIcons.bookOpen,
              title: 'Menu jest puste',
              message: 'Kierownik dodaje dania w zakładce „Menu”. Potem pojawią się tutaj.',
            );
          }
          final current = withItems.firstWhere(
            (s) => s.id == sectionId,
            orElse: () => withItems.first,
          );
          final items = query.isEmpty
              ? current.items
              : [
                  for (final s in withItems)
                    for (final i in s.items)
                      if (i.name.toLowerCase().contains(query)) i,
                ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: TextField(
                  controller: search,
                  onChanged: onQuery,
                  decoration: InputDecoration(
                    hintText: 'Szukaj w menu',
                    isDense: true,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: Glyph(AppIcons.search, size: 18, color: AppColors.textMuted),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Wyczyść',
                            icon: const Glyph(AppIcons.close, size: 16),
                            onPressed: () {
                              search.clear();
                              onQuery('');
                            },
                          ),
                  ),
                ),
              ),
              if (query.isEmpty)
                SizedBox(
                  height: 54,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    children: [
                      SegmentedTabs<String>(
                        options: [for (final s in withItems) (s.id, s.name)],
                        selected: current.id,
                        onChanged: onSection,
                      ),
                    ],
                  ),
                ),
              Divider(height: 1, color: AppColors.ring),
              Expanded(
                child: items.isEmpty
                    ? const MessageView(
                        icon: AppIcons.search,
                        title: 'Nic nie pasuje',
                        message: 'Spróbuj innej nazwy dania.',
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(14),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 210,
                          mainAxisExtent: 104,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) => _ItemTile(
                          item: items[i],
                          enabled: enabled,
                          onTap: () => onTap(items[i]),
                          onOptions: () => onOptions(items[i]),
                          onMenu: (at) => onMenu(items[i], at),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.enabled,
    required this.onTap,
    required this.onOptions,
    required this.onMenu,
  });

  final MenuItem item;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onOptions;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final off = !item.available;

    return PanelPress(
      child: Opacity(
        opacity: off || !enabled ? 0.45 : 1,
        child: Material(
          color: AppColors.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.ringStrong),
          ),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            // Prawy przycisk myszy albo przytrzymanie palcem: „skończyło się” i uwaga.
            onSecondaryTapDown: (d) => onMenu(d.globalPosition),
            onLongPressStart: (d) => onMenu(d.globalPosition),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelLarge?.copyWith(height: 1.25),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            off
                                ? 'Niedostępne'
                                : item.priceVaries
                                ? 'od ${Fmt.price(item.fromPrice)}'
                                : Fmt.price(item.fromPrice),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                              color: off ? AppColors.error : AppColors.textMuted,
                              fontFeatures: _tabular,
                            ),
                          ),
                        ),
                        // Zmiana składników („bez cebuli”, „więcej sera”) i uwaga dla kuchni.
                        if (!off)
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: IconButton(
                              tooltip: 'Zmień składniki albo dodaj uwagę',
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(backgroundColor: Colors.transparent, side: BorderSide.none),
                              onPressed: onOptions,
                              icon: Glyph(item.hasOptions ? AppIcons.sliders : AppIcons.notePencil, size: 15, color: AppColors.textMuted),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wybór kelnera w oknie pozycji z wariantami i dodatkami.
class _Choice {
  const _Choice({this.variant, this.addons = const [], this.quantity = 1, this.note, this.changes = const []});

  final String? variant;
  final List<String> addons;
  final int quantity;
  final String? note;

  /// Zmiany składników: „bez cebuli”, „więcej sera”.
  final List<ItemChange> changes;
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({required this.item});

  final MenuItem item;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  late String? _variant = widget.item.variants.length == 1 ? widget.item.variants.first.name : null;
  final _addons = <String>{};
  int _quantity = 1;
  final _note = TextEditingController();

  /// Składniki z receptury: false = bez, true = więcej (brak w mapie: normalnie).
  final _recipe = <String, bool>{};

  /// Inne składniki wpisane ręcznie (nie z receptury).
  final _custom = <ItemChange>[];
  final _customName = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    _customName.dispose();
    super.dispose();
  }

  List<RecipeLine> get _ingredients => [
    for (final r in widget.item.ingredients)
      if (r.name != null) r,
  ];

  void _addCustom(bool extra) {
    final name = _customName.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _custom.removeWhere((c) => c.name.toLowerCase() == name.toLowerCase());
      _custom.add(ItemChange(name, extra: extra));
      _customName.clear();
    });
  }

  int get _unitPrice {
    final item = widget.item;
    var price = item.priceGrosze;
    if (item.variants.isNotEmpty) {
      price = item.variants.firstWhere(
        (v) => v.name == _variant,
        orElse: () => MenuOption('', item.fromPrice),
      ).priceGrosze;
    }
    for (final a in item.addons) {
      if (_addons.contains(a.name)) price += a.priceGrosze;
    }
    return price;
  }

  void _submit() {
    if (widget.item.variants.isNotEmpty && _variant == null) {
      showMessage(context, 'Wybierz wariant.');
      return;
    }
    Navigator.pop(
      context,
      _Choice(
        variant: _variant,
        // Dodatki w kolejności z menu, żeby rachunek i kuchnia widziały je tak samo.
        addons: [
          for (final a in widget.item.addons)
            if (_addons.contains(a.name)) a.name,
        ],
        quantity: _quantity,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        changes: [
          for (final r in _ingredients)
            if (_recipe[r.itemId] case final extra?) ItemChange(r.name!, extra: extra, itemId: r.itemId),
          ..._custom,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = widget.item;

    return AlertDialog(
      title: Text(item.name),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (item.variants.isNotEmpty) ...[
                Text('Wariant', style: text.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in item.variants)
                      _OptionButton(
                        label: v.name,
                        price: Fmt.price(v.priceGrosze),
                        selected: _variant == v.name,
                        onTap: () => setState(() => _variant = v.name),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              if (item.addons.isNotEmpty) ...[
                Text('Dodatki', style: text.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in item.addons)
                      _OptionButton(
                        label: a.name,
                        price: '+${Fmt.price(a.priceGrosze)}',
                        selected: _addons.contains(a.name),
                        onTap: () => setState(
                          () => _addons.contains(a.name) ? _addons.remove(a.name) : _addons.add(a.name),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              Text('Składniki', style: text.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Usuń albo dodaj składnik. Kuchnia zobaczy zmianę na bilecie.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              for (final r in _ingredients)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(r.name!, style: text.bodyMedium)),
                      SegmentedTabs<int>(
                        options: const [(0, 'Bez'), (1, 'Normalnie'), (2, 'Więcej')],
                        selected: switch (_recipe[r.itemId]) {
                          false => 0,
                          true => 2,
                          null => 1,
                        },
                        onChanged: (v) => setState(() {
                          if (v == 1) {
                            _recipe.remove(r.itemId);
                          } else {
                            _recipe[r.itemId] = v == 2;
                          }
                        }),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customName,
                      maxLength: 40,
                      decoration: InputDecoration(
                        hintText: _ingredients.isEmpty ? 'Składnik, np. cebula' : 'Inny składnik',
                        isDense: true,
                        counterText: '',
                      ),
                      onSubmitted: (_) => _addCustom(false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => _addCustom(false), child: const Text('Bez')),
                  const SizedBox(width: 6),
                  OutlinedButton(onPressed: () => _addCustom(true), child: const Text('Więcej')),
                ],
              ),
              if (_custom.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in _custom)
                      InputChip(
                        label: Text(c.label),
                        onDeleted: () => setState(() => _custom.remove(c)),
                        deleteIcon: const Glyph(AppIcons.close, size: 14),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Text('Ilość', style: text.titleSmall),
                  const Spacer(),
                  _Stepper(
                    value: _quantity,
                    onChanged: (v) => setState(() => _quantity = v.clamp(1, 99)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _note,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Uwaga dla kuchni (opcjonalnie)',
                  hintText: 'np. bez cebuli',
                  counterText: '',
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        // Cena pojawia się dopiero po wyborze wariantu, żeby kelner nie nabił złej kwoty.
        FilledButton(
          onPressed: item.variants.isNotEmpty && _variant == null ? null : _submit,
          child: Text(
            item.variants.isNotEmpty && _variant == null
                ? 'Wybierz wariant'
                : 'Dodaj · ${Fmt.price(_unitPrice * _quantity)}',
            style: const TextStyle(fontFeatures: _tabular),
          ),
        ),
      ],
    );
  }
}

/// Duży przycisk wyboru pod palec: nazwa i cena.
class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.label,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PanelPress(
      child: Material(
        color: selected ? AppColors.accentTint : AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? AppColors.accent : AppColors.ringStrong),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 110, minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: text.labelLarge?.copyWith(color: selected ? AppColors.accent : AppColors.text),
                  ),
                  Text(
                    price,
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.compact = false,
  });

  final int value;
  final int min;
  final ValueChanged<int> onChanged;

  /// Mniejsze przyciski do wierszy rachunku.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final size = compact ? 32.0 : 44.0;
    final constraints = BoxConstraints.tightFor(width: size, height: size);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Mniej',
          constraints: constraints,
          padding: EdgeInsets.zero,
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: Glyph(AppIcons.minus, size: compact ? 14 : 16),
        ),
        SizedBox(
          width: compact ? 24 : 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: (compact ? text.labelLarge : text.titleMedium)?.copyWith(fontFeatures: _tabular),
          ),
        ),
        IconButton(
          tooltip: 'Więcej',
          constraints: constraints,
          padding: EdgeInsets.zero,
          onPressed: value < 99 ? () => onChanged(value + 1) : null,
          icon: Glyph(AppIcons.plus, size: compact ? 14 : 16),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Rachunek stolika
// ---------------------------------------------------------------

class _OrderPanel extends StatelessWidget {
  const _OrderPanel({
    required this.table,
    required this.order,
    required this.reservation,
    required this.onQuantity,
    required this.onNote,
    required this.onStatus,
    required this.onServeAll,
    required this.onSend,
    required this.onClose,
    required this.onCancel,
    required this.onMove,
    required this.canCancelSent,
    required this.kitchen,
  });

  final DiningTable table;
  final PanelOrder? order;
  final PanelReservation? reservation;
  final KitchenConfig kitchen;
  final void Function(OrderItem item, int quantity) onQuantity;
  final ValueChanged<OrderItem> onNote;
  final void Function(OrderItem item, OrderItemStatus status) onStatus;
  final ValueChanged<List<OrderItem>> onServeAll;
  final VoidCallback? onSend;
  final VoidCallback? onClose;
  final VoidCallback? onCancel;
  final VoidCallback? onMove;

  /// Czy zalogowany pracownik może anulować pozycje, które są już na kuchni.
  final bool canCancelSent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final order = this.order;
    final items = order?.items ?? const <OrderItem>[];
    final groups = [
      for (final status in [
        OrderItemStatus.ready,
        OrderItemStatus.fresh,
        OrderItemStatus.sent,
        OrderItemStatus.served,
      ])
        (status, items.where((i) => i.status == status).toList()),
    ].where((g) => g.$2.isNotEmpty).toList();
    final unsent = order?.unsent ?? 0;
    final total = order?.totalGrosze ?? 0;
    final waiting = order?.waitingSince;
    final wait = waiting == null ? null : _waitLabel(waiting, kitchen);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${table.isSeat ? 'Miejsce' : 'Stolik'} ${table.label}',
                        style: text.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        order == null
                            ? 'Brak otwartego rachunku'
                            : [
                                'Rachunek od ${Fmt.time(order.openedAt)}',
                                if (reservation != null) reservation!.guestName,
                              ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                      ),
                      if (wait != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Glyph(AppIcons.clock, size: 14, color: wait.$2),
                              const SizedBox(width: 6),
                              Text(
                                'Czeka na danie ${wait.$1} (od ${Fmt.time(waiting!)})',
                                style: text.labelMedium?.copyWith(color: wait.$2, fontFeatures: _tabular),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (order != null)
                  PopupMenuButton<String>(
                    tooltip: 'Więcej',
                    icon: Glyph(AppIcons.dotsVertical, size: 18, color: AppColors.textMuted),
                    onSelected: (v) => v == 'move' ? onMove?.call() : onCancel?.call(),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'move', child: Text('Przenieś na inny stolik')),
                      PopupMenuItem(
                        value: 'cancel',
                        child: Text('Anuluj rachunek', style: TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.ring),
          Expanded(
            child: groups.isEmpty
                ? const MessageView(
                    icon: AppIcons.forkKnife,
                    title: 'Rachunek jest pusty',
                    message: 'Stuknij danie w menu. Rachunek otworzy się sam przy pierwszej pozycji.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    children: [
                      for (final (status, list) in groups) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                          child: Row(
                            children: [
                              Glyph(
                                switch (status) {
                                  OrderItemStatus.fresh => AppIcons.notePencil,
                                  OrderItemStatus.sent => AppIcons.cookingPot,
                                  OrderItemStatus.ready => AppIcons.bell,
                                  _ => AppIcons.checkCircle,
                                },
                                size: 14,
                                color: switch (status) {
                                  OrderItemStatus.fresh => const Color(0xFFD99A15),
                                  OrderItemStatus.ready => AppColors.accent,
                                  _ => AppColors.textDisabled,
                                },
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  status.label.toUpperCase(),
                                  style: text.labelSmall?.copyWith(
                                    color: status == OrderItemStatus.ready
                                        ? AppColors.accent
                                        : AppColors.textDisabled,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              // Kuchnia zbiła dania: kelner jednym kliknięciem oznacza, że je zaniósł.
                              if (status == OrderItemStatus.ready)
                                TextButton.icon(
                                  onPressed: () => onServeAll(list),
                                  icon: const Glyph(AppIcons.check, size: 14),
                                  label: const Text('Wydaj wszystko'),
                                ),
                            ],
                          ),
                        ),
                        for (final item in list)
                          _OrderLine(
                            item: item,
                            canCancelSent: canCancelSent,
                            onQuantity: (q) => onQuantity(item, q),
                            onNote: () => onNote(item),
                            onStatus: (s) => onStatus(item, s),
                          ),
                      ],
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
                      Fmt.price(total),
                      style: text.headlineSmall?.copyWith(fontFeatures: _tabular),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: unsent > 0 ? onSend : null,
                    icon: const Glyph(AppIcons.send, size: 18),
                    label: Text(unsent > 0 ? 'Wyślij na kuchnię ($unsent)' : 'Wyślij na kuchnię'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: total > 0 ? onClose : null,
                    icon: const Glyph(AppIcons.receipt, size: 18),
                    label: const Text('Zamknij rachunek'),
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

/// Szkic zamówienia na wynos: dane klienta, dania i „Przyjmij” z czasem przygotowania.
class _TakeawayPanel extends StatelessWidget {
  const _TakeawayPanel({
    required this.restaurantId,
    required this.order,
    required this.minutes,
    required this.onMinutes,
    required this.onEdit,
    required this.onDiscard,
    required this.onSubmit,
    required this.onQuantity,
    required this.onNote,
  });

  final String restaurantId;
  final TakeawayOrder order;
  final int minutes;
  final ValueChanged<int> onMinutes;
  final VoidCallback onEdit;
  final VoidCallback onDiscard;
  final VoidCallback onSubmit;
  final void Function(OrderItem item, int quantity) onQuantity;
  final ValueChanged<OrderItem> onNote;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final o = order;
    final items = o.active;
    final dishes = items.fold(0, (s, i) => s + i.totalGrosze);
    final delivery = o.kind == OrderKind.delivery;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.label, style: text.titleLarge),
                      Text(
                        'Do przyjęcia · dodaj dania z menu',
                        style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Więcej',
                  icon: Glyph(AppIcons.dotsVertical, size: 18, color: AppColors.textMuted),
                  onSelected: (v) => v == 'edit' ? onEdit() : onDiscard(),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Zmień dane klienta')),
                    PopupMenuItem(
                      value: 'discard',
                      child: Text('Porzuć zamówienie', style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                TakeawayCustomerCard(restaurantId: restaurantId, order: o, onEdit: onEdit),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Stuknij danie w menu, żeby dodać je do zamówienia.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  )
                else
                  for (final item in items)
                    _OrderLine(
                      item: item,
                      canCancelSent: false,
                      onQuantity: (q) => onQuantity(item, q),
                      onNote: () => onNote(item),
                      onStatus: (s) => onQuantity(item, 0),
                    ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.ring),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (delivery && o.feeGrosze > 0) ...[
                  Row(
                    children: [
                      Text('Dania', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                      const Spacer(),
                      Text(Fmt.price(dishes), style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Dostawa', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                      const Spacer(),
                      Text(Fmt.price(o.feeGrosze), style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
                    ],
                  ),
                ],
                Row(
                  children: [
                    Text('Razem', style: text.titleMedium),
                    const Spacer(),
                    Text(Fmt.price(dishes + o.feeGrosze), style: text.headlineSmall?.copyWith(fontFeatures: _tabular)),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Czas przygotowania', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 6),
                SegmentedTabs<int>(
                  options: const [(15, '15 min'), (30, '30'), (45, '45'), (60, '60')],
                  selected: minutes,
                  onChanged: onMinutes,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: items.isEmpty ? null : onSubmit,
                    icon: const Glyph(AppIcons.send, size: 18),
                    label: Text('Przyjmij · $minutes min'),
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

class _OrderLine extends StatelessWidget {
  const _OrderLine({
    required this.item,
    required this.canCancelSent,
    required this.onQuantity,
    required this.onNote,
    required this.onStatus,
  });

  final OrderItem item;
  final bool canCancelSent;
  final ValueChanged<int> onQuantity;
  final VoidCallback onNote;
  final ValueChanged<OrderItemStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fresh = item.status == OrderItemStatus.fresh;
    final ready = item.status == OrderItemStatus.ready;
    final details = item.details;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: ready
            ? AppColors.accentTint
            : fresh
            ? AppColors.surfaceRaised
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: ready ? Border.all(color: AppColors.accent.withValues(alpha: 0.5)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      if (!fresh || item.quantity > 1)
                        TextSpan(
                          text: '${item.quantity}× ',
                          style: TextStyle(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                      TextSpan(text: item.name),
                    ],
                  ),
                  style: text.labelLarge,
                ),
                if (details != null)
                  Text(details, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                if (item.note != null)
                  Text(
                    item.note!,
                    style: text.bodySmall?.copyWith(
                      color: const Color(0xFFD99A15),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Cena nad przyciskami ilości, żeby nazwa dania miała całą szerokość wiersza.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  Fmt.price(item.totalGrosze),
                  style: text.labelLarge?.copyWith(fontFeatures: _tabular),
                ),
              ),
              if (fresh) _Stepper(value: item.quantity, min: 0, compact: true, onChanged: onQuantity),
            ],
          ),
          if (ready)
            IconButton(
              tooltip: 'Wydane',
              onPressed: () => onStatus(OrderItemStatus.served),
              icon: Glyph(AppIcons.check, size: 18, color: AppColors.accent),
            ),
          PopupMenuButton<String>(
            tooltip: 'Więcej',
            // Bez tła: przy każdej pozycji rachunku kostka byłaby zbyt ciężka.
            style: IconButton.styleFrom(backgroundColor: Colors.transparent, side: BorderSide.none),
            icon: Glyph(AppIcons.dotsVertical, size: 16, color: AppColors.textMuted),
            onSelected: (v) => switch (v) {
              'note' => onNote(),
              'served' => onStatus(OrderItemStatus.served),
              _ => onStatus(OrderItemStatus.cancelled),
            },
            itemBuilder: (_) => [
              if (fresh) const PopupMenuItem(value: 'note', child: Text('Uwaga dla kuchni')),
              if (item.status == OrderItemStatus.sent || ready)
                const PopupMenuItem(value: 'served', child: Text('Wydane')),
              if (fresh || canCancelSent)
                PopupMenuItem(
                  value: 'cancel',
                  child: Text(
                    fresh ? 'Usuń z rachunku' : 'Anuluj pozycję',
                    style: TextStyle(color: AppColors.error),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial});

  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Uwaga dla kuchni'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(hintText: 'np. bez cebuli', counterText: ''),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Zamknięcie rachunku i przeniesienie
// ---------------------------------------------------------------

class _MoveDialog extends StatelessWidget {
  const _MoveDialog({required this.from, required this.tables});

  final DiningTable from;

  /// Stoliki bez otwartego rachunku.
  final List<DiningTable> tables;

  @override
  Widget build(BuildContext context) {
    final sorted = [...tables]..sort((a, b) => compareLabels(a.label, b.label));
    return AlertDialog(
      title: Text('Przenieś rachunek ze stolika ${from.label}'),
      content: SizedBox(
        width: 420,
        child: sorted.isEmpty
            ? const Text('Wszystkie stoliki mają otwarte rachunki.')
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in sorted)
                    _OptionButton(
                      label: t.label,
                      price: '${Fmt.capitalize(t.zone)} · ${t.seats} os.',
                      selected: false,
                      onTap: () => Navigator.pop(context, t),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
      ],
    );
  }
}
