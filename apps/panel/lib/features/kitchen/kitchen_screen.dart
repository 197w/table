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

/// Kolory upływu czasu i stanów pozycji. Mocne, żeby było je widać z drugiego końca kuchni.
const _amber = Color(0xFFE0A21B);
const _late = Color(0xFFE5484D);
const _blue = Color(0xFF3B82F6);
const _blueText = Color(0xFF8AB8FF);

String _two(int n) => n.toString().padLeft(2, '0');

/// Godzina z sekundami, np. 18:42:07.
String _hms(DateTime t) {
  final l = t.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
}

/// Czas trwania jako 04:37 albo 1:04:37.
String _duration(Duration d) {
  final s = d.inSeconds.clamp(0, 359999);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(sec)}' : '${_two(m)}:${_two(sec)}';
}

/// Ekran kuchni: zamówienia wysłane przez kelnerów, duże i czytelne z kilku metrów.
/// Obsługa myszą, palcem albo klawiaturą (skróty na dolnym pasku).
class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  /// Zmiany kuchni, zanim baza je potwierdzi: numer pozycji i czy jest zbita.
  /// Dzięki temu bilecik reaguje od razu, bez czekania na serwer.
  final _pending = <String, bool>{};

  /// Ostatnio zamknięty bilecik, do cofnięcia pomyłki.
  ({String key, String label, List<String> ids})? _lastDone;

  /// Bileciki widziane wcześniej. Nowy dzwoni i przez chwilę się wyróżnia.
  Set<String>? _known;
  final _fresh = <String>{};

  /// Odtwarzacz powstaje przy pierwszym dźwięku, nie przy otwarciu ekranu.
  AudioPlayer? _player;
  late final Timer _tick;
  final _focus = FocusNode(debugLabel: 'kuchnia');

  /// Wybór klawiaturą: bilecik i pozycja na nim (-1: żadna).
  String? _selectedKey;
  int _cursor = -1;

  @override
  void initState() {
    super.initState();
    // Zegar i czasy bilecików idą co sekundę.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    _player?.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _isDone(OrderItem i) => _pending[i.id] ?? i.status == OrderItemStatus.ready;

  /// Pozycja cofnięta przez kuchnię i robiona od nowa.
  bool _isRecalled(OrderItem i) {
    final pending = _pending[i.id];
    // Cofana właśnie pozycja od razu robi się niebieska, zanim baza to potwierdzi.
    if (pending != null) return !pending;
    return i.status == OrderItemStatus.sent && i.recalledAt != null;
  }

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

  Future<void> _toggle(String restaurantId, OrderItem item) {
    if (item.status == OrderItemStatus.cancelled) return Future.value();
    return _set(restaurantId, [item.id], done: !_isDone(item));
  }

  Future<void> _bump(String restaurantId, KitchenTicket ticket, String label) async {
    final ids = [
      for (final i in ticket.items)
        if (i.status != OrderItemStatus.cancelled && !_isDone(i)) i.id,
    ];
    if (ids.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _lastDone = (key: ticket.key, label: label, ids: ids);
      if (_selectedKey == ticket.key) {
        _selectedKey = null;
        _cursor = -1;
      }
    });
    await _set(restaurantId, ids, done: true);
  }

  Future<void> _undo(String restaurantId) async {
    final last = _lastDone;
    if (last == null) return;
    // Przywrócony bilecik nie jest nowym zamówieniem, więc nie dzwoni.
    _known?.add(last.key);
    setState(() => _lastDone = null);
    await _set(restaurantId, last.ids, done: false);
  }

  /// Dzwoni, gdy pojawi się bilecik, którego jeszcze nie było.
  void _noticeNew(List<KitchenTicket> tickets) {
    final keys = {for (final t in tickets) t.key};
    final known = _known;
    _known = {...?known, ...keys};
    if (known == null) return;
    final added = keys.difference(known);
    if (added.isEmpty) return;
    _fresh.addAll(added);
    if (!ref.read(kitchenMutedProvider)) {
      unawaited(
        (_player ??= AudioPlayer())
            .play(AssetSource('sounds/nowa_rezerwacja.wav'))
            .catchError((_) {}),
      );
    }
    Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _fresh.removeAll(added));
    });
  }

  /// Skróty klawiszowe działają tylko na tym ekranie, gdy ma on fokus.
  KeyEventResult _onKey(
    KeyEvent event,
    String restaurantId,
    List<KitchenTicket> tickets,
    String Function(KitchenTicket) labelOf,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final index = tickets.indexWhere((t) => t.key == _selectedKey);
    final selected = index < 0 ? null : tickets[index];

    void select(int i) => setState(() {
      _selectedKey = tickets.isEmpty ? null : tickets[i.clamp(0, tickets.length - 1)].key;
      _cursor = -1;
    });

    const digits = [
      LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
    ];
    const numpad = [
      LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
    ];
    final digit = digits.contains(key) ? digits.indexOf(key) : numpad.indexOf(key);
    if (digit >= 0) {
      if (digit < tickets.length) select(digit);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (tickets.isNotEmpty) select(index < 0 ? 0 : (index + 1) % tickets.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (tickets.isNotEmpty) select(index <= 0 ? tickets.length - 1 : index - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      if (selected == null) {
        if (tickets.isNotEmpty) select(0);
      } else {
        final last = selected.items.length - 1;
        setState(() {
          _cursor = key == LogicalKeyboardKey.arrowDown
              ? (_cursor >= last ? 0 : _cursor + 1)
              : (_cursor <= 0 ? last : _cursor - 1);
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      if (selected != null && _cursor >= 0 && _cursor < selected.items.length) {
        _toggle(restaurantId, selected.items[_cursor]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      // Bez wyboru Enter zbija najstarszy bilecik.
      final target = selected ?? (tickets.isEmpty ? null : tickets.first);
      if (target != null) _bump(restaurantId, target, labelOf(target));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.keyZ) {
      _undo(restaurantId);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      ref.read(kitchenFullscreenProvider.notifier).set(!ref.read(kitchenFullscreenProvider));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      ref.read(kitchenMutedProvider.notifier).toggle();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (ref.read(kitchenFullscreenProvider)) {
        ref.read(kitchenFullscreenProvider.notifier).set(false);
      } else {
        setState(() {
          _selectedKey = null;
          _cursor = -1;
        });
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _settings(String restaurantId, KitchenConfig config) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _KitchenSettingsDialog(restaurantId: restaurantId, config: config),
    );
    _focus.requestFocus();
    if (saved == true && mounted) {
      ref
        ..invalidate(kitchenConfigProvider(restaurantId))
        ..invalidate(menuProvider(restaurantId))
        ..invalidate(kitchenTicketsProvider(restaurantId));
      showMessage(context, 'Ustawienia kuchni zapisane.');
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
    final config = ref.watch(kitchenConfigProvider(restaurant.id)).value ?? const KitchenConfig();
    final stats = ref.watch(kitchenStatsProvider(restaurant.id)).value ?? const KitchenStats();
    final tables = ref.watch(tablesProvider(restaurant.id)).value ?? const <DiningTable>[];
    final labels = {for (final t in tables) ?t.id: '${t.isSeat ? 'Miejsce' : 'Stolik'} ${t.label}'};
    String labelOf(KitchenTicket t) => labels[t.tableId] ?? 'Bez stolika';
    final live = ref.watch(ordersLiveProvider(restaurant.id).select((s) => s.status));
    final fullscreen = ref.watch(kitchenFullscreenProvider);

    final tickets = (async.value ?? const <KitchenTicket>[])
        .where(
          (t) => t.items.any((i) => i.status != OrderItemStatus.cancelled && !_isDone(i)),
        )
        .toList();
    final pendingItems = tickets.fold<int>(
      0,
      (sum, t) =>
          sum +
          t.items
              .where((i) => i.status != OrderItemStatus.cancelled && !_isDone(i))
              .fold<int>(0, (s, i) => s + i.quantity),
    );

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, event) => _onKey(event, restaurant.id, tickets, labelOf),
      child: Listener(
        // Kliknięcie w ekran oddaje mu klawiaturę, np. po zamknięciu okna ustawień.
        onPointerDown: (_) => _focus.requestFocus(),
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
                onSettings: () => _settings(restaurant.id, config),
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
                          config: config,
                          labelOf: labelOf,
                          isDone: _isDone,
                          isRecalled: _isRecalled,
                          fresh: _fresh,
                          selectedKey: _selectedKey,
                          cursor: _cursor,
                          onToggle: (item) => _toggle(restaurant.id, item),
                          onBump: (t) => _bump(restaurant.id, t, labelOf(t)),
                        ),
                ),
              ),
              _StatsBar(stats: stats),
            ],
          ),
        ),
      ),
    );
  }
}

/// Górny pasek: liczba zamówień, zegar z sekundami, stan połączenia i przyciski.
class _KitchenBar extends ConsumerWidget {
  const _KitchenBar({
    required this.tickets,
    required this.items,
    required this.live,
    required this.fullscreen,
    required this.undoLabel,
    required this.onUndo,
    required this.onSettings,
    required this.onFullscreen,
  });

  final int tickets;
  final int items;
  final LiveStatus live;
  final bool fullscreen;
  final String? undoLabel;
  final VoidCallback onUndo;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final muted = ref.watch(kitchenMutedProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 20, 16),
      child: Row(
        children: [
          Text('Kuchnia', style: text.headlineMedium?.copyWith(fontSize: 34)),
          const SizedBox(width: 20),
          // Napis zajmuje całe wolne miejsce, więc przyciski i zegar stoją przy prawej krawędzi.
          Expanded(
            child: Text(
              tickets == 0 ? 'Nic nie czeka' : '${_orders(tickets)} · ${_dishes(items)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleLarge?.copyWith(
                fontSize: 24,
                color: AppColors.textMuted,
                fontFeatures: _tabular,
              ),
            ),
          ),
          const SizedBox(width: 16),
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
            icon: AppIcons.gear,
            tooltip: 'Ustawienia kuchni',
            onPressed: onSettings,
          ),
          const SizedBox(width: 8),
          GlowButton(
            icon: muted ? AppIcons.bellSlash : AppIcons.bell,
            tooltip: muted ? 'Włącz dźwięk nowych zamówień (M)' : 'Wycisz dźwięk nowych zamówień (M)',
            onPressed: () => ref.read(kitchenMutedProvider.notifier).toggle(),
          ),
          const SizedBox(width: 8),
          GlowButton(
            icon: AppIcons.move,
            tooltip: fullscreen ? 'Wyjdź z pełnego ekranu (Esc)' : 'Pełny ekran (F)',
            onPressed: onFullscreen,
          ),
          const SizedBox(width: 20),
          Text(
            _hms(DateTime.now()),
            style: text.headlineMedium?.copyWith(fontSize: 40, fontFeatures: _tabular),
          ),
        ],
      ),
    );
  }

  static String _orders(int n) => _plural(n, 'zamówienie', 'zamówienia', 'zamówień');
  static String _dishes(int n) => _plural(n, 'danie', 'dania', 'dań');
}

String _plural(int n, String one, String few, String many) {
  if (n == 1) return '1 $one';
  final isFew = n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14);
  return '$n ${isFew ? few : many}';
}

/// Dolny pasek: średni czas przygotowania i skróty klawiszowe.
class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.stats});

  final KitchenStats stats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final value = text.titleLarge?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      fontFeatures: _tabular,
    );
    final label = text.titleMedium?.copyWith(color: AppColors.textMuted, fontSize: 18);

    Widget average(String title, int? seconds, int count) => Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title, style: label),
        const SizedBox(width: 10),
        Text(seconds == null ? '—' : _duration(Duration(seconds: seconds)), style: value),
        const SizedBox(width: 8),
        Text('(${_plural(count, 'zamówienie', 'zamówienia', 'zamówień')})', style: label),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.ring)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
      child: Row(
        children: [
          Glyph(AppIcons.timer, size: 24, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Text('Średni czas', style: label?.copyWith(color: AppColors.text)),
          const SizedBox(width: 24),
          average('dziś', stats.todaySeconds, stats.todayCount),
          const SizedBox(width: 28),
          average('ostatnia godzina', stats.hourSeconds, stats.hourCount),
          const SizedBox(width: 24),
          // Ściąga skrótów dla kuchni obsługiwanej klawiaturą, dosunięta do prawej.
          Expanded(
            child: Text(
              '1–9 bilecik · ↑↓ pozycja · Spacja zbij · Enter gotowe · Backspace cofnij · F ekran',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: text.bodyLarge?.copyWith(color: AppColors.textDisabled),
            ),
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
    required this.config,
    required this.labelOf,
    required this.isDone,
    required this.isRecalled,
    required this.fresh,
    required this.selectedKey,
    required this.cursor,
    required this.onToggle,
    required this.onBump,
  });

  final List<KitchenTicket> tickets;
  final KitchenConfig config;
  final String Function(KitchenTicket) labelOf;
  final bool Function(OrderItem) isDone;
  final bool Function(OrderItem) isRecalled;
  final Set<String> fresh;
  final String? selectedKey;
  final int cursor;
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
        final perColumn = List.generate(columns, (_) => <(int, KitchenTicket)>[]);
        for (var i = 0; i < tickets.length; i++) {
          perColumn[i % columns].add((i, tickets[i]));
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
                      for (final (i, t) in perColumn[col])
                        Padding(
                          padding: const EdgeInsets.only(bottom: _gap),
                          child: _Ticket(
                            key: ValueKey(t.key),
                            number: i + 1,
                            ticket: t,
                            config: config,
                            label: labelOf(t),
                            isDone: isDone,
                            isRecalled: isRecalled,
                            fresh: fresh.contains(t.key),
                            selected: t.key == selectedKey,
                            cursor: t.key == selectedKey ? cursor : -1,
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
    required this.number,
    required this.ticket,
    required this.config,
    required this.label,
    required this.isDone,
    required this.isRecalled,
    required this.fresh,
    required this.selected,
    required this.cursor,
    required this.onToggle,
    required this.onBump,
  });

  /// Numer do wyboru klawiszem 1–9.
  final int number;
  final KitchenTicket ticket;
  final KitchenConfig config;
  final String label;
  final bool Function(OrderItem) isDone;
  final bool Function(OrderItem) isRecalled;
  final bool fresh;
  final bool selected;
  final int cursor;
  final ValueChanged<OrderItem> onToggle;
  final VoidCallback onBump;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final elapsed = DateTime.now().difference(ticket.sentAt);
    final minutes = elapsed.inSeconds / 60;
    final (Color? headerBg, Color headerFg) = minutes >= config.lateMinutes
        ? (_late, Colors.white)
        : minutes >= config.warnMinutes
        ? (_amber, Colors.black)
        : (null, AppColors.text);
    final courses = {for (final i in ticket.items) i.course};

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: AppMotion.easeOut,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? AppColors.text
              : fresh
              ? AppColors.accent
              : AppColors.ringStrong,
          width: selected || fresh ? 3 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Nagłówek: numer, stolik i czas od wysłania. Kolor mówi, co czeka najdłużej.
          Container(
            color: headerBg ?? AppColors.surfaceRaised,
            padding: const EdgeInsets.fromLTRB(14, 12, 20, 12),
            child: Row(
              children: [
                if (number <= 9) ...[
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: headerFg.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$number',
                      style: text.titleLarge?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: headerFg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
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
                      _duration(elapsed),
                      style: text.headlineSmall?.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                        color: headerFg,
                        fontFeatures: _tabular,
                      ),
                    ),
                    Text(
                      'od ${_hms(ticket.sentAt)}',
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
                    recalled: isRecalled(ticket.items[i]),
                    focused: i == cursor,
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
/// Stuknięcie zbija pozycję, drugie ją cofa (wtedy robi się niebieska).
class _Line extends StatelessWidget {
  const _Line({
    required this.item,
    required this.done,
    required this.recalled,
    required this.focused,
    required this.onTap,
  });

  final OrderItem item;
  final bool done;
  final bool recalled;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final details = item.details;
    final cancelled = item.status == OrderItemStatus.cancelled;
    final struck = done || cancelled;
    final decoration = struck ? TextDecoration.lineThrough : null;
    final nameColor = cancelled
        ? _late
        : recalled
        ? _blueText
        : AppColors.text;

    return InkWell(
      onTap: cancelled ? null : onTap,
      child: AnimatedOpacity(
        opacity: done ? 0.35 : 1,
        duration: const Duration(milliseconds: 160),
        child: Container(
          decoration: BoxDecoration(
            // Cofnięta pozycja ma niebieskie tło, pozycja wybrana klawiaturą jaśniejsze.
            color: recalled
                ? _blue.withValues(alpha: 0.16)
                : focused
                ? AppColors.surfaceRaised
                : null,
            border: Border(
              left: BorderSide(
                color: focused
                    ? AppColors.text
                    : recalled
                    ? _blue
                    : Colors.transparent,
                width: 5,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(15, 10, 20, 10),
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
                    color: cancelled
                        ? _late
                        : item.quantity > 1
                        ? AppColors.accent
                        : nameColor,
                    fontFeatures: _tabular,
                    decoration: decoration,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (recalled || cancelled)
                      Text(
                        cancelled ? 'ANULOWANE' : 'COFNIĘTE',
                        style: text.titleSmall?.copyWith(
                          fontSize: 15,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                          color: cancelled ? _late : _blueText,
                        ),
                      ),
                    Text(
                      item.name,
                      style: text.headlineMedium?.copyWith(
                        fontSize: 30,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        color: nameColor,
                        decoration: decoration,
                        decorationColor: cancelled ? _late : null,
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

// ---------------------------------------------------------------
// Ustawienia kuchni
// ---------------------------------------------------------------

/// Progi kolorów czasu i pozycje menu, które nie idą na kuchnię (np. napoje z baru).
class _KitchenSettingsDialog extends ConsumerStatefulWidget {
  const _KitchenSettingsDialog({required this.restaurantId, required this.config});

  final String restaurantId;
  final KitchenConfig config;

  @override
  ConsumerState<_KitchenSettingsDialog> createState() => _KitchenSettingsDialogState();
}

class _KitchenSettingsDialogState extends ConsumerState<_KitchenSettingsDialog> {
  late int _warnMin = widget.config.warnMinutes;
  late int _lateMin = widget.config.lateMinutes;

  /// Pozycje ukryte przed kuchnią. Null, dopóki menu się nie wczyta.
  Set<String>? _hidden;
  bool _busy = false;

  Future<void> _save() async {
    if (_lateMin <= _warnMin) {
      showMessage(context, 'Czas „czerwony” musi być dłuższy niż „żółty”.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).setKitchenConfig(
        restaurantId: widget.restaurantId,
        warnMinutes: _warnMin,
        lateMinutes: _lateMin,
        hiddenItemIds: (_hidden ?? const <String>{}).toList(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final menu = ref.watch(menuProvider(widget.restaurantId));
    if (_hidden == null && menu.hasValue) {
      _hidden = {
        for (final s in menu.value!)
          for (final i in s.items)
            if (!i.showInKitchen) i.id,
      };
    }
    final hidden = _hidden ?? <String>{};

    Widget threshold(String title, String hint, Color color, int value, ValueChanged<int> onChanged) {
      return Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                Text(hint, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Mniej',
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
            icon: const Glyph(AppIcons.minus, size: 16),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '$value min',
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(fontFeatures: _tabular),
            ),
          ),
          IconButton(
            tooltip: 'Więcej',
            onPressed: value < 120 ? () => onChanged(value + 1) : null,
            icon: const Glyph(AppIcons.plus, size: 16),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Ustawienia kuchni'),
      content: SizedBox(
        width: 520,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            threshold(
              'Żółty po',
              'Bilecik czeka dłużej niż zwykle.',
              _amber,
              _warnMin,
              (v) => setState(() => _warnMin = v),
            ),
            const SizedBox(height: 8),
            threshold(
              'Czerwony po',
              'Bilecik czeka za długo.',
              _late,
              _lateMin,
              (v) => setState(() => _lateMin = v),
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: AppColors.ring),
            const SizedBox(height: 14),
            Text('Co pokazywać na kuchni', style: text.titleSmall),
            Text(
              'Odznacz pozycje, których kuchnia nie robi, np. napoje z baru. '
              'Kelner zobaczy je od razu jako „do wydania”.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: menu.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(menuProvider(widget.restaurantId)),
                ),
                data: (sections) => ListView(
                  children: [
                    for (final s in sections.where((s) => s.items.isNotEmpty)) ...[
                      // Cała sekcja jednym kliknięciem, np. „Napoje”.
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        tristate: true,
                        value: s.items.every((i) => !hidden.contains(i.id))
                            ? true
                            : s.items.every((i) => hidden.contains(i.id))
                            ? false
                            : null,
                        onChanged: (_) => setState(() {
                          final allShown = s.items.every((i) => !hidden.contains(i.id));
                          for (final i in s.items) {
                            allShown ? hidden.add(i.id) : hidden.remove(i.id);
                          }
                        }),
                        title: Text(s.name, style: text.titleSmall),
                      ),
                      for (final i in s.items)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 32),
                          controlAffinity: ListTileControlAffinity.leading,
                          value: !hidden.contains(i.id),
                          onChanged: (v) => setState(
                            () => v == true ? hidden.remove(i.id) : hidden.add(i.id),
                          ),
                          title: Text(i.name, style: text.bodyMedium),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _busy || _hidden == null ? null : _save,
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}
