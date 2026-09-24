import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Kolory upływu czasu: po 10 minutach bilecik żółknie, po 20 czerwienieje.
const _amber = Color(0xFFE0A21B);
const _late = Color(0xFFE5484D);

/// Ekran kuchni: zamówienia wysłane przez kelnerów, duże i czytelne z kilku metrów.
/// Stuknięcie pozycji oznacza ją jako gotową, „Gotowe” zamyka cały bilecik.
class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  /// Zmiany kuchni, zanim baza je potwierdzi: numer pozycji i czy jest gotowa.
  /// Dzięki temu bilecik reaguje od razu, bez czekania na serwer.
  final _pending = <String, bool>{};

  /// Ostatnio zamknięty bilecik, do cofnięcia pomyłki.
  ({String label, List<String> ids})? _lastDone;

  /// Bileciki widziane wcześniej. Nowy dzwoni i przez chwilę się wyróżnia.
  Set<String>? _known;
  final _fresh = <String>{};
  /// Odtwarzacz powstaje przy pierwszym dźwięku, nie przy otwarciu ekranu.
  AudioPlayer? _player;
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // Minuty oczekiwania i zegar odświeżają się same.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    _player?.dispose();
    super.dispose();
  }

  bool _isDone(OrderItem i) => _pending[i.id] ?? i.status == OrderItemStatus.served;

  Future<void> _set(String restaurantId, List<String> ids, {required bool done}) async {
    if (ids.isEmpty) return;
    setState(() {
      for (final id in ids) {
        _pending[id] = done;
      }
    });
    try {
      await ref.read(repositoryProvider).kitchenSet(ids, done: done);
      // Czekamy na świeże dane, żeby bilecik nie mignął starym stanem po zdjęciu zmian kuchni.
      ref.invalidate(kitchenTicketsProvider(restaurantId));
      await ref.read(kitchenTicketsProvider(restaurantId).future);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) {
        setState(() {
          for (final id in ids) {
            _pending.remove(id);
          }
        });
      }
    }
  }

  Future<void> _bump(String restaurantId, KitchenTicket ticket, String label) async {
    final ids = [
      for (final i in ticket.items)
        if (!_isDone(i)) i.id,
    ];
    HapticFeedback.mediumImpact();
    setState(() => _lastDone = (label: label, ids: ids));
    await _set(restaurantId, ids, done: true);
  }

  Future<void> _undo(String restaurantId) async {
    final last = _lastDone;
    if (last == null) return;
    setState(() => _lastDone = null);
    await _set(restaurantId, last.ids, done: false);
  }

  /// Dzwoni, gdy pojawi się bilecik, którego jeszcze nie było.
  void _noticeNew(List<KitchenTicket> tickets) {
    final keys = {for (final t in tickets) t.key};
    final known = _known;
    _known = keys;
    if (known == null) return;
    final added = keys.difference(known);
    if (added.isEmpty) return;
    _fresh.addAll(added);
    if (!ref.read(kitchenMutedProvider)) {
      unawaited(
        (_player ??= AudioPlayer()).play(AssetSource('sounds/nowa_rezerwacja.wav')).catchError((_) {}),
      );
    }
    Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _fresh.removeAll(added));
    });
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();

    if (!restaurant.isPro) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Kuchnia'),
          Expanded(child: ProGate(feature: 'Ekran kuchni')),
        ],
      );
    }

    final permissions = ref.watch(myPermissionsProvider(restaurant.id));
    if (!permissions.hasValue) {
      return permissions.hasError
          ? ErrorView(
              error: permissions.error!,
              onRetry: () => ref.invalidate(myPermissionsProvider(restaurant.id)),
            )
          : const LoadingView();
    }
    if (!permissions.value!.contains('kitchen')) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Kuchnia'),
          Expanded(
            child: MessageView(
              icon: AppIcons.lock,
              title: 'Brak dostępu do ekranu kuchni',
              message:
                  'Ekran kuchni widzi stanowisko z uprawnieniem „Kuchnia”, na przykład Kucharz. '
                  'Stanowiska ustawia właściciel w zakładce „Pracownicy”.',
            ),
          ),
        ],
      );
    }

    ref.listen(kitchenTicketsProvider(restaurant.id), (_, next) {
      if (next.value case final tickets?) _noticeNew(tickets);
    });

    final async = ref.watch(kitchenTicketsProvider(restaurant.id));
    final tables = ref.watch(tablesProvider(restaurant.id)).value ?? const <DiningTable>[];
    final labels = {for (final t in tables) ?t.id: '${t.isSeat ? 'Miejsce' : 'Stolik'} ${t.label}'};
    final live = ref.watch(ordersLiveProvider(restaurant.id).select((s) => s.status));
    final fullscreen = ref.watch(kitchenFullscreenProvider);

    final tickets = (async.value ?? const <KitchenTicket>[])
        .where((t) => t.items.any((i) => !_isDone(i)))
        .toList();
    final pendingItems = tickets.fold<int>(
      0,
      (sum, t) => sum + t.items.where((i) => !_isDone(i)).fold<int>(0, (s, i) => s + i.quantity),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (fullscreen) ref.read(kitchenFullscreenProvider.notifier).set(false);
        },
      },
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: AppColors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KitchenBar(
                tickets: tickets.length,
                items: pendingItems,
                live: live,
                fullscreen: fullscreen,
                undoLabel: _lastDone?.label,
                onUndo: () => _undo(restaurant.id),
                onFullscreen: () => ref.read(kitchenFullscreenProvider.notifier).set(!fullscreen),
              ),
              Divider(height: 1, thickness: 1, color: AppColors.ring),
              Expanded(
                child: async.when(
                  skipLoadingOnReload: true,
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(kitchenTicketsProvider(restaurant.id)),
                  ),
                  data: (_) => tickets.isEmpty
                      ? const _Empty()
                      : _TicketBoard(
                          tickets: tickets,
                          labelOf: (t) => labels[t.tableId] ?? 'Bez stolika',
                          isDone: _isDone,
                          fresh: _fresh,
                          onToggle: (item) =>
                              _set(restaurant.id, [item.id], done: !_isDone(item)),
                          onBump: (t) => _bump(restaurant.id, t, labels[t.tableId] ?? 'Bez stolika'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Górny pasek: liczba zamówień, zegar, stan połączenia i przyciski.
class _KitchenBar extends ConsumerWidget {
  const _KitchenBar({
    required this.tickets,
    required this.items,
    required this.live,
    required this.fullscreen,
    required this.undoLabel,
    required this.onUndo,
    required this.onFullscreen,
  });

  final int tickets;
  final int items;
  final LiveStatus live;
  final bool fullscreen;
  final String? undoLabel;
  final VoidCallback onUndo;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final muted = ref.watch(kitchenMutedProvider);
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 20, 16),
      child: Row(
        children: [
          Text('Kuchnia', style: text.headlineMedium?.copyWith(fontSize: 34)),
          const SizedBox(width: 20),
          Text(
            tickets == 0 ? 'Nic nie czeka' : '${_orders(tickets)} · ${_dishes(items)}',
            style: text.titleLarge?.copyWith(
              fontSize: 24,
              color: AppColors.textMuted,
              fontFeatures: _tabular,
            ),
          ),
          const Spacer(),
          if (undoLabel != null) ...[
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: onUndo,
                icon: const Glyph(AppIcons.undo, size: 20),
                label: Text('Cofnij: $undoLabel', style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          switch (live) {
            LiveStatus.live => const PanelPill('Na żywo', dotColor: Color(0xFF2FB673)),
            LiveStatus.connecting => const PanelPill('Łączenie…', dotColor: _amber),
            LiveStatus.offline => const PanelPill('Brak połączenia', dotColor: _late),
          },
          const SizedBox(width: 12),
          GlowButton(
            icon: muted ? AppIcons.bellSlash : AppIcons.bell,
            tooltip: muted ? 'Włącz dźwięk nowych zamówień' : 'Wycisz dźwięk nowych zamówień',
            onPressed: () => ref.read(kitchenMutedProvider.notifier).toggle(),
          ),
          const SizedBox(width: 8),
          GlowButton(
            icon: AppIcons.move,
            tooltip: fullscreen ? 'Wyjdź z pełnego ekranu (Esc)' : 'Pełny ekran',
            onPressed: onFullscreen,
          ),
          const SizedBox(width: 20),
          Text(
            Fmt.time(now),
            style: text.headlineMedium?.copyWith(fontSize: 40, fontFeatures: _tabular),
          ),
        ],
      ),
    );
  }

  static String _orders(int n) => _plural(n, 'zamówienie', 'zamówienia', 'zamówień');
  static String _dishes(int n) => _plural(n, 'danie', 'dania', 'dań');

  static String _plural(int n, String one, String few, String many) {
    if (n == 1) return '1 $one';
    final few_ = n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14);
    return '$n ${few_ ? few : many}';
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
          Glyph(AppIcons.cookingPot, size: 72, color: AppColors.textDisabled),
          const SizedBox(height: 20),
          Text('Brak zamówień na kuchni', style: text.headlineMedium?.copyWith(fontSize: 34)),
          const SizedBox(height: 8),
          Text(
            'Nowe zamówienie pojawi się tu samo, z dźwiękiem.',
            style: text.titleLarge?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Bileciki w kolumnach: najstarszy w lewym górnym rogu, kolejne w prawo i w dół.
class _TicketBoard extends StatelessWidget {
  const _TicketBoard({
    required this.tickets,
    required this.labelOf,
    required this.isDone,
    required this.fresh,
    required this.onToggle,
    required this.onBump,
  });

  final List<KitchenTicket> tickets;
  final String Function(KitchenTicket) labelOf;
  final bool Function(OrderItem) isDone;
  final Set<String> fresh;
  final ValueChanged<OrderItem> onToggle;
  final ValueChanged<KitchenTicket> onBump;

  static const _gap = 16.0;
  static const _minWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final inner = c.maxWidth - 2 * 20;
        final columns = ((inner + _gap) / (_minWidth + _gap)).floor().clamp(1, 8);
        // Po kolei do kolumn, więc kolejność czytania zgadza się z kolejnością zamówień.
        final perColumn = List.generate(columns, (_) => <KitchenTicket>[]);
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
                          child: _Ticket(
                            key: ValueKey(t.key),
                            ticket: t,
                            label: labelOf(t),
                            isDone: isDone,
                            fresh: fresh.contains(t.key),
                            onToggle: onToggle,
                            onBump: () => onBump(t),
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

class _Ticket extends StatelessWidget {
  const _Ticket({
    super.key,
    required this.ticket,
    required this.label,
    required this.isDone,
    required this.fresh,
    required this.onToggle,
    required this.onBump,
  });

  final KitchenTicket ticket;
  final String label;
  final bool Function(OrderItem) isDone;
  final bool fresh;
  final ValueChanged<OrderItem> onToggle;
  final VoidCallback onBump;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final minutes = DateTime.now().difference(ticket.sentAt).inMinutes.clamp(0, 999);
    final (Color? headerBg, Color headerFg) = minutes >= 20
        ? (_late, Colors.white)
        : minutes >= 10
        ? (_amber, Colors.black)
        : (null, AppColors.text);
    final courses = {for (final i in ticket.items) i.course};

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
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
          // Nagłówek: stolik i czas od wysłania. Kolor mówi, co czeka najdłużej.
          Container(
            color: headerBg ?? AppColors.surfaceRaised,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineMedium?.copyWith(
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                      color: headerFg,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$minutes min',
                      style: text.headlineSmall?.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: headerFg,
                        fontFeatures: _tabular,
                      ),
                    ),
                    Text(
                      Fmt.time(ticket.sentAt),
                      style: text.titleMedium?.copyWith(
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
                for (var i = 0; i < ticket.items.length; i++) ...[
                  // Kolejne dania (np. deser) oddziela podpis, żeby kuchnia nie wydała ich za wcześnie.
                  if (courses.length > 1 &&
                      (i == 0 || ticket.items[i].course != ticket.items[i - 1].course))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                      child: Text(
                        'DANIE ${ticket.items[i].course}',
                        style: text.titleSmall?.copyWith(
                          fontSize: 16,
                          letterSpacing: 1.2,
                          color: AppColors.textDisabled,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  _Line(
                    item: ticket.items[i],
                    done: isDone(ticket.items[i]),
                    onTap: () => onToggle(ticket.items[i]),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: SizedBox(
              height: 64,
              child: FilledButton.icon(
                onPressed: onBump,
                icon: const Glyph(AppIcons.check, size: 26),
                label: const Text(
                  'Gotowe',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Jedna pozycja: ilość i nazwa dużymi literami, pod spodem wariant, dodatki i uwaga.
/// Stuknięcie przekreśla pozycję jako gotową, drugie przywraca.
class _Line extends StatelessWidget {
  const _Line({required this.item, required this.done, required this.onTap});

  final OrderItem item;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final details = item.details;
    final decoration = done ? TextDecoration.lineThrough : null;

    return InkWell(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: done ? 0.35 : 1,
        duration: const Duration(milliseconds: 160),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  '${item.quantity}×',
                  style: text.headlineMedium?.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: item.quantity > 1 ? AppColors.accent : AppColors.text,
                    fontFeatures: _tabular,
                    decoration: decoration,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: text.headlineMedium?.copyWith(
                        fontSize: 30,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        decoration: decoration,
                      ),
                    ),
                    if (details != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          details,
                          style: text.titleLarge?.copyWith(
                            fontSize: 22,
                            color: AppColors.textMuted,
                            decoration: decoration,
                          ),
                        ),
                      ),
                    if (item.note != null)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _amber.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '! ${item.note}',
                          style: text.titleLarge?.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: _amber,
                            decoration: decoration,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
