import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Kolory czasu czekania gotowego dania. Ciepłe danie nie powinno stać dłużej niż 2 minuty.
const _amber = Color(0xFFE0A21B);
const _late = Color(0xFFE5484D);
const _warnAfter = Duration(minutes: 2);
const _lateAfter = Duration(minutes: 4);

String _two(int n) => n.toString().padLeft(2, '0');

String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';

/// Czas jako 04:37 albo 1:04:37.
String _duration(Duration d) {
  final s = d.inSeconds.clamp(0, 359999);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(sec)}' : '${_two(m)}:${_two(sec)}';
}

String _plural(int n, String one, String few, String many) {
  if (n == 1) return '1 $one';
  final isFew = n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14);
  return '$n ${isFew ? few : many}';
}

/// Ekran „Kompletowanie”: dania gotowe z kuchni czekają, aż ktoś zaniesie je gościom albo spakuje na wynos.
/// Karta to stolik (albo zamówienie na wynos do spakowania), najdłużej czekające pierwsze.
/// Stuknięcie pozycji wydaje ją, „Wydane” wydaje całą kartę. Nowe gotowe danie dzwoni.
class ServingScreen extends ConsumerStatefulWidget {
  const ServingScreen({super.key});

  @override
  ConsumerState<ServingScreen> createState() => _ServingScreenState();
}

class _ServingScreenState extends ConsumerState<ServingScreen> {
  /// Pozycje i zamówienia wydawane właśnie teraz: znikają od razu, zanim baza potwierdzi.
  final _pending = <String>{};

  /// Ostatnio wydana karta, do cofnięcia pomyłki.
  ({String label, List<String> ids})? _lastServed;

  /// Gotowe pozycje widziane wcześniej. Nowa dzwoni, a jej karta przez chwilę się wyróżnia.
  Set<String>? _known;
  final _fresh = <String>{};

  AudioPlayer? _player;
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // Czas czekania rośnie co sekundę.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _noticeNew(List<ServingTicket> tickets) {
    final ready = {for (final t in tickets) ...t.readyIds};
    final known = _known;
    _known = {...?known, ...ready};
    if (known == null) return;
    final added = ready.difference(known);
    if (added.isEmpty) return;
    final orders = {
      for (final t in tickets)
        if (t.readyIds.any(added.contains)) t.orderId,
    };
    _fresh.addAll(orders);
    if (!ref.read(servingMutedProvider)) {
      unawaited(
        (_player ??= AudioPlayer())
            .play(AssetSource('sounds/nowa_rezerwacja.wav'))
            .catchError((_) {}),
      );
    }
    Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _fresh.removeAll(orders));
    });
  }

  Future<void> _serve(String restaurantId, List<String> ids, String label) async {
    if (ids.isEmpty) return;
    setState(() => _pending.addAll(ids));
    try {
      await ref.read(repositoryProvider).serveItems(ids);
      if (mounted) setState(() => _lastServed = (label: label, ids: ids));
      ref.invalidate(servingTicketsProvider(restaurantId));
      await ref.read(servingTicketsProvider(restaurantId).future);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _pending.removeAll(ids));
    }
  }

  Future<void> _undo(String restaurantId) async {
    final last = _lastServed;
    if (last == null) return;
    setState(() => _lastServed = null);
    // Przywrócone danie nie jest nowym daniem z kuchni, więc nie dzwoni.
    _known?.addAll(last.ids);
    try {
      await ref.read(repositoryProvider).serveItems(last.ids, undo: true);
      ref.invalidate(servingTicketsProvider(restaurantId));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Zamówienie na wynos spakowane: w „Dostawach” czeka na gościa albo dostawcę.
  Future<void> _packed(String restaurantId, ServingTicket ticket, String label) async {
    setState(() => _pending.add(ticket.orderId));
    try {
      await ref.read(repositoryProvider).takeawayReady(ticket.orderId);
      if (mounted) {
        showMessage(
          context,
          ticket.takeawayKind == OrderKind.delivery
              ? '$label czeka na dostawcę.'
              : '$label czeka na odbiór gościa.',
          tone: ToastTone.success,
        );
      }
      ref.invalidate(servingTicketsProvider(restaurantId));
      await ref.read(servingTicketsProvider(restaurantId).future);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _pending.remove(ticket.orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();

    if (!restaurant.isPro) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: ProGate(feature: 'Kompletowanie')),
        ],
      );
    }

    ref.listen(servingTicketsProvider(restaurant.id), (_, next) {
      if (next.value case final tickets?) _noticeNew(tickets);
    });

    final async = ref.watch(servingTicketsProvider(restaurant.id));
    final tables = ref.watch(tablesProvider(restaurant.id)).value ?? const <DiningTable>[];
    final labels = {for (final t in tables) ?t.id: '${t.isSeat ? 'Miejsce' : 'Stolik'} ${t.label}'};
    String labelOf(ServingTicket t) => t.takeawayLabel ?? labels[t.tableId] ?? 'Bez stolika';
    final live = ref.watch(ordersLiveProvider(restaurant.id).select((s) => s.status));

    // Wydawane właśnie pozycje znikają od razu.
    final tickets = [
      for (final t in async.value ?? const <ServingTicket>[])
        if (!_pending.contains(t.orderId) && t.readyIds.any((id) => !_pending.contains(id))) t,
    ];
    final dishes = tickets.fold<int>(
      0,
      (sum, t) => sum +
          t.items
              .where((i) => i.status == OrderItemStatus.ready && !_pending.contains(i.id))
              .fold<int>(0, (s, i) => s + i.quantity),
    );

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ServingBar(
            tickets: tickets.length,
            dishes: dishes,
            live: live,
            undoLabel: _lastServed?.label,
            onUndo: () => _undo(restaurant.id),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.ring),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(servingTicketsProvider(restaurant.id)),
              ),
              data: (_) => tickets.isEmpty
                  ? const _Empty()
                  : _Board(
                      tickets: tickets,
                      labelOf: labelOf,
                      pending: _pending,
                      fresh: _fresh,
                      onServeItem: (t, item) => _serve(restaurant.id, [item.id], labelOf(t)),
                      onServeAll: (t) => _serve(
                        restaurant.id,
                        [for (final id in t.readyIds) if (!_pending.contains(id)) id],
                        labelOf(t),
                      ),
                      onPacked: (t) => _packed(restaurant.id, t, labelOf(t)),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Górny pasek: ile czeka, cofnięcie, stan połączenia, dźwięk i zegar.
class _ServingBar extends ConsumerWidget {
  const _ServingBar({
    required this.tickets,
    required this.dishes,
    required this.live,
    required this.undoLabel,
    required this.onUndo,
  });

  final int tickets;
  final int dishes;
  final LiveStatus live;
  final String? undoLabel;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final muted = ref.watch(servingMutedProvider);
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tickets == 0
                  ? 'Brak zamówień'
                  : '${_plural(dishes, 'gotowe danie', 'gotowe dania', 'gotowych dań')} · '
                        '${_plural(tickets, 'zamówienie', 'zamówienia', 'zamówień')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleLarge?.copyWith(
                fontSize: 22,
                color: AppColors.textMuted,
                fontFeatures: _tabular,
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (undoLabel != null) ...[
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: onUndo,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Glyph(AppIcons.undo, size: 18),
                label: Text('Cofnij: $undoLabel', style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          switch (live) {
            LiveStatus.live => const PanelPill('Na żywo', dotColor: Color(0xFF2FB673)),
            LiveStatus.connecting => const PanelPill('Łączenie…', dotColor: _amber),
            LiveStatus.offline => const PanelPill('Brak połączenia', dotColor: _late),
          },
          const SizedBox(width: 8),
          GlowButton(
            icon: muted ? AppIcons.bellSlash : AppIcons.bell,
            tooltip: muted ? 'Włącz dźwięk gotowych dań' : 'Wycisz dźwięk gotowych dań',
            onPressed: () => ref.read(servingMutedProvider.notifier).toggle(),
          ),
          const SizedBox(width: 20),
          Text(
            '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}',
            style: text.headlineMedium?.copyWith(fontSize: 34, fontFeatures: _tabular),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(AppIcons.callBell.duotone, size: 72, color: AppColors.textDisabled),
          const SizedBox(height: 20),
          Text('Brak zamówień do wydania', style: text.headlineMedium?.copyWith(fontSize: 30)),
        ],
      ),
    );
  }
}

/// Karty w kolumnach: najdłużej czekająca w lewym górnym rogu, kolejne w prawo i w dół.
class _Board extends StatelessWidget {
  const _Board({
    required this.tickets,
    required this.labelOf,
    required this.pending,
    required this.fresh,
    required this.onServeItem,
    required this.onServeAll,
    required this.onPacked,
  });

  final List<ServingTicket> tickets;
  final String Function(ServingTicket) labelOf;
  final Set<String> pending;
  final Set<String> fresh;
  final void Function(ServingTicket, OrderItem) onServeItem;
  final ValueChanged<ServingTicket> onServeAll;
  final ValueChanged<ServingTicket> onPacked;

  static const _gap = 16.0;
  static const _minWidth = 330.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final inner = c.maxWidth - 2 * 20;
        final columns = ((inner + _gap) / (_minWidth + _gap)).floor().clamp(1, 8);
        final perColumn = List.generate(columns, (_) => <ServingTicket>[]);
        for (var i = 0; i < tickets.length; i++) {
          perColumn[i % columns].add(tickets[i]);
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var col = 0; col < columns; col++) ...[
                if (col > 0) const SizedBox(width: _gap),
                Expanded(
                  child: Column(
                    children: [
                      for (final t in perColumn[col])
                        Padding(
                          padding: const EdgeInsets.only(bottom: _gap),
                          child: _Card(
                            key: ValueKey(t.orderId),
                            ticket: t,
                            label: labelOf(t),
                            pending: pending,
                            fresh: fresh.contains(t.orderId),
                            onServeItem: (item) => onServeItem(t, item),
                            onServeAll: () => onServeAll(t),
                            onPacked: () => onPacked(t),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.ticket,
    required this.label,
    required this.pending,
    required this.fresh,
    required this.onServeItem,
    required this.onServeAll,
    required this.onPacked,
  });

  final ServingTicket ticket;
  final String label;
  final Set<String> pending;
  final bool fresh;
  final ValueChanged<OrderItem> onServeItem;
  final VoidCallback onServeAll;
  final VoidCallback onPacked;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final waiting = DateTime.now().difference(ticket.readySince);
    final (Color? headerBg, Color headerFg) = waiting >= _lateAfter
        ? (_late, Colors.white)
        : waiting >= _warnAfter
        ? (_amber, Colors.black)
        : (null, AppColors.text);
    final items = [
      for (final i in ticket.items)
        if (!pending.contains(i.id)) i,
    ];
    final cooking = ticket.items.where((i) => i.status == OrderItemStatus.sent).fold(0, (s, i) => s + i.quantity);
    final promised = ticket.promisedAt;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: AppMotion.easeOut,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: fresh ? AppColors.accent : AppColors.ringStrong,
          width: fresh ? 3 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Nagłówek: stolik albo numer na wynos, kto nabił i jak długo danie czeka.
          Container(
            color: headerBg ?? AppColors.surfaceRaised,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Row(
              children: [
                if (ticket.isTakeaway) ...[
                  Glyph(
                    (ticket.takeawayKind == OrderKind.delivery ? AppIcons.moped : AppIcons.shoppingBag).duotone,
                    size: 26,
                    color: headerFg,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.headlineSmall?.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: headerFg,
                        ),
                      ),
                      Text(
                        ticket.waiter ?? (ticket.isTakeaway ? 'Spakuj zamówienie' : 'Zanieś do stolika'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(color: headerFg.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _duration(waiting),
                      style: text.headlineSmall?.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: headerFg,
                        fontFeatures: _tabular,
                      ),
                    ),
                    // Na wynos ważniejsze jest, na którą lokal obiecał zamówienie.
                    Text(
                      promised != null ? 'na ${_hm(promised)}' : 'gotowe od ${_hm(ticket.readySince)}',
                      style: text.bodyMedium?.copyWith(
                        color: headerFg.withValues(alpha: 0.75),
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items)
                  _Line(
                    item: item,
                    takeaway: ticket.isTakeaway,
                    onTap: !ticket.isTakeaway && item.status == OrderItemStatus.ready ? () => onServeItem(item) : null,
                  ),
              ],
            ),
          ),
          if (!ticket.isTakeaway && cooking > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Glyph(AppIcons.chefHat, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    'Jeszcze na kuchni: ${_plural(cooking, 'danie', 'dania', 'dań')}',
                    style: text.titleMedium?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: SizedBox(
              height: 56,
              child: ticket.isTakeaway
                  ? FilledButton.icon(
                      onPressed: ticket.allReady ? onPacked : null,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                      icon: Glyph(ticket.allReady ? AppIcons.package : AppIcons.chefHat, size: 22),
                      label: Text(
                        !ticket.allReady
                            ? 'Czeka na kuchnię (${_plural(cooking, 'danie', 'dania', 'dań')})'
                            : ticket.takeawayKind == OrderKind.delivery
                            ? 'Spakowane dla dostawcy'
                            : 'Spakowane do odbioru',
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: onServeAll,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                      icon: const Glyph(AppIcons.check, size: 22),
                      label: const Text('Wydane', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Jedna pozycja: ilość i nazwa, pod spodem wariant, dodatki i uwaga.
/// Na sali stuknięcie wydaje pozycję. Na wynos ikona mówi, czy kuchnia już ją zrobiła.
class _Line extends StatelessWidget {
  const _Line({required this.item, required this.takeaway, required this.onTap});

  final OrderItem item;
  final bool takeaway;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final details = item.details;
    final cooking = item.status == OrderItemStatus.sent;
    final color = cooking ? AppColors.textMuted : AppColors.text;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 9, 20, 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (takeaway) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Glyph(
                  cooking ? AppIcons.chefHat : AppIcons.checkCircle.duotone,
                  size: 22,
                  color: cooking ? AppColors.textDisabled : AppColors.accent,
                ),
              ),
              const SizedBox(width: 10),
            ],
            SizedBox(
              width: 50,
              child: Text(
                '${item.quantity}×',
                style: text.headlineSmall?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: item.quantity > 1 && !cooking ? AppColors.accent : color,
                  fontFeatures: _tabular,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: text.headlineSmall?.copyWith(
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (details != null)
                    Text(details, style: text.titleMedium?.copyWith(color: AppColors.textMuted)),
                  if (item.note != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _amber.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '! ${item.note}',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: _amber),
                      ),
                    ),
                  if (cooking)
                    Text('na kuchni', style: text.bodyMedium?.copyWith(color: AppColors.textDisabled)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
