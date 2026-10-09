import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'orders_data.dart';
import 'ui.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Przyciski w motywie Table mają pełną szerokość. W rzędach dajemy im zwykły rozmiar.
final _compact = FilledButton.styleFrom(minimumSize: const Size(0, 48));
final _compactOutlined = OutlinedButton.styleFrom(minimumSize: const Size(0, 48));

/// Numery stolików rosną jak liczby: 2 przed 10.
int _byLabel(WTable a, WTable b) {
  final na = int.tryParse(a.label);
  final nb = int.tryParse(b.label);
  if (na != null && nb != null) return na.compareTo(nb);
  if (na != null) return -1;
  if (nb != null) return 1;
  return a.label.toLowerCase().compareTo(b.label.toLowerCase());
}

// ---------------------------------------------------------------
// Stoliki
// ---------------------------------------------------------------

/// Kelner wybiera stolik. Kafel pokazuje kwotę otwartego rachunku, dania do wydania i niewysłane na kuchnię
/// (liczba z ikoną, nie sam kolor). Na górze podsumowanie lokalu.
class WaiterTablesScreen extends ConsumerWidget {
  const WaiterTablesScreen({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final tables = ref.watch(tablesProvider(job.restaurantId));
    final orders = ref.watch(openOrdersProvider(job.restaurantId)).value ?? const <WOrder>[];
    final byTable = {for (final o in orders) ?o.tableId: o};
    final ready = orders.fold(0, (sum, o) => sum + o.ready);
    final unsent = orders.fold(0, (sum, o) => sum + o.unsent);
    // Kafel rośnie z czcionką telefonu, żeby numer, kwota i liczby się mieściły.
    final tileHeight = 70 + MediaQuery.textScalerOf(context).scale(48);

    return Scaffold(
      appBar: AppBar(title: const Text('Zamówienia')),
      body: tables.when(
        loading: () => const _TablesSkeleton(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(tablesProvider(job.restaurantId))),
        data: (list) {
          if (list.isEmpty) {
            return const MessageView(
              icon: AppIcons.squaresFour,
              title: 'Lokal nie ma jeszcze stolików',
              message: 'Kierownik rozstawia stoliki w panelu, w zakładce „Edycja sali”.',
            );
          }
          final zones = <String>[];
          for (final t in list) {
            if (!zones.contains(t.zone)) zones.add(t.zone);
          }
          final open = list.where((t) => byTable.containsKey(t.id)).length;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(openOrdersProvider(job.restaurantId));
              await ref.read(openOrdersProvider(job.restaurantId).future);
            },
            child: ContentWidth(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      job.restaurantName,
                      style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Co jest do zrobienia na sali: słowo, liczba i ikona.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatusChip(
                        label: 'Otwarte rachunki: $open',
                        icon: AppIcons.receipt,
                        color: open > 0 ? AppColors.text : AppColors.textMuted,
                      ),
                      if (ready > 0)
                        StatusChip(label: 'Do wydania: $ready', icon: AppIcons.callBell, color: AppColors.accent),
                      if (unsent > 0)
                        StatusChip(label: 'Do wysłania: $unsent', icon: AppIcons.send, color: StaffColors.pending),
                    ],
                  ),
                  for (final zone in zones) ...[
                    SectionHeader(
                      zone.isEmpty ? 'Sala' : zone,
                      top: 20,
                      trailing: Text(
                        _openLabel(list.where((t) => t.zone == zone && byTable.containsKey(t.id)).length),
                        style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                      ),
                    ),
                    GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 132,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        mainAxisExtent: tileHeight,
                      ),
                      children: [
                        for (final t in list.where((t) => t.zone == zone).toList()..sort(_byLabel))
                          _TableTile(
                            table: t,
                            order: byTable[t.id],
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(builder: (_) => TableOrderScreen(job: job, table: t)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// „2 otwarte” przy nazwie strefy.
String _openLabel(int n) => n == 0 ? 'wszystkie wolne' : (n == 1 ? '1 otwarty' : '$n otwarte');

class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, required this.order, required this.onTap});

  final WTable table;
  final WOrder? order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final o = order;
    final open = o != null;
    final ready = o?.ready ?? 0;
    final unsent = o?.unsent ?? 0;
    final label = [
      table.title,
      if (o == null) 'wolny, ${table.seats} ${table.seats == 1 ? 'miejsce' : 'miejsca'}' else 'rachunek ${Fmt.price(o.total)}',
      if (ready > 0) 'do wydania: $ready',
      if (unsent > 0) 'do wysłania: $unsent',
    ].join(', ');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        child: Material(
          color: open ? AppColors.accentTint : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: open ? AppColors.accent.withValues(alpha: 0.6) : AppColors.ring),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    table.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineSmall?.copyWith(
                      color: open ? AppColors.accent : AppColors.text,
                      fontFeatures: _tabular,
                    ),
                  ),
                  const Spacer(),
                  if (ready > 0 || unsent > 0) ...[
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (ready > 0) _CountBadge(icon: AppIcons.callBell, count: ready, color: AppColors.accent),
                        if (unsent > 0) _CountBadge(icon: AppIcons.send, count: unsent, color: StaffColors.pending),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  // Kwota zmniejsza się, zamiast gubić „zł” przy dużej czcionce.
                  if (open)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(Fmt.price(o.total), style: text.titleSmall?.copyWith(fontFeatures: _tabular)),
                    )
                  else
                    Row(
                      children: [
                        Glyph(AppIcons.users, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          '${table.seats}',
                          style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                      ],
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

/// Liczba z ikoną na kafelku stolika: dzwonek = do wydania, samolocik = do wysłania na kuchnię.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.icon, required this.count, required this.color});

  final AppIconData icon;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Glyph(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: _tabular,
          ),
        ),
      ],
    ),
  );
}

/// Szkielet siatki stolików, zanim dane dojdą.
class _TablesSkeleton extends StatelessWidget {
  const _TablesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ContentWidth(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          children: [
            const SkeletonBox(width: 140, height: 14),
            const SizedBox(height: 14),
            const SkeletonBox(width: 180, height: 26, radius: 8),
            const SizedBox(height: 28),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                for (var i = 0; i < 6; i++)
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.ring),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Rachunek stolika
// ---------------------------------------------------------------

/// Rachunek stolika na telefonie: co zanieść, co wysłać na kuchnię, dodawanie z menu i zamknięcie.
class TableOrderScreen extends ConsumerStatefulWidget {
  const TableOrderScreen({super.key, required this.job, required this.table});

  final Job job;
  final WTable table;

  @override
  ConsumerState<TableOrderScreen> createState() => _TableOrderScreenState();
}

class _TableOrderScreenState extends ConsumerState<TableOrderScreen> {
  bool _busy = false;

  /// Pozycje usunięte przesunięciem. Znikają od razu, zanim baza potwierdzi usunięcie.
  final _removed = <String>{};

  String get _rid => widget.job.restaurantId;

  WOrder? _order() {
    for (final o in ref.read(openOrdersProvider(_rid)).value ?? const <WOrder>[]) {
      if (o.tableId == widget.table.id) return o;
    }
    return null;
  }

  Future<void> _run(Future<void> Function() action, [String? done]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(openOrdersProvider(_rid));
      if (done != null && mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Usunięcie niewysłanej pozycji przesunięciem w lewo.
  Future<void> _remove(WLine line) async {
    setState(() => _removed.add(line.id));
    HapticFeedback.lightImpact();
    try {
      await ref.read(waiterRepositoryProvider).updateItem(line.id, status: 'cancelled');
      ref.invalidate(openOrdersProvider(_rid));
      if (mounted) showMessage(context, 'Usunięto: ${line.name}.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _removed.remove(line.id));
      showError(context, e);
    }
  }

  Future<void> _addFromMenu() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => MenuPickerScreen(job: widget.job, table: widget.table)),
    );
    ref.invalidate(openOrdersProvider(_rid));
  }

  Future<void> _close(WOrder order) async {
    // Arkusz sam zamyka rachunek: całość, równo na osoby albo za wybrane pozycje.
    final closed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _SettleSheet(restaurantId: _rid, orderId: order.id, memberId: widget.job.memberId),
    );
    ref.invalidate(openOrdersProvider(_rid));
    if (closed == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final orders = ref.watch(openOrdersProvider(_rid));
    WOrder? order;
    for (final o in orders.value ?? const <WOrder>[]) {
      if (o.tableId == widget.table.id) order = o;
    }
    final lines = [...?order?.lines.where((l) => !_removed.contains(l.id))];
    final repo = ref.read(waiterRepositoryProvider);
    // Grupy pozycji: nazwa, ikona i kolor (słowo z ikoną, nie sam kolor).
    final groups = [
      (LineStatus.ready, 'Do wydania', AppIcons.callBell, AppColors.accent),
      (LineStatus.fresh, 'Do wysłania', AppIcons.send, StaffColors.pending),
      (LineStatus.sent, 'Na kuchni', AppIcons.cookingPot, StaffColors.info),
      (LineStatus.served, 'Wydane', AppIcons.checkCircle, AppColors.textMuted),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.table.title),
        actions: [
          if (order != null && order.total > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _busy ? null : () => _close(order!),
                icon: const Glyph(AppIcons.cashRegister, size: 18),
                label: const Text('Rachunek'),
              ),
            ),
        ],
      ),
      body: order == null || lines.isEmpty
          ? MessageView(
              icon: AppIcons.forkKnife,
              title: 'Rachunek jest pusty',
              message: 'Dodaj dania z menu. Rachunek otworzy się sam przy pierwszej pozycji.',
              actionLabel: 'Dodaj z menu',
              onAction: _addFromMenu,
            )
          : ContentWidth(
              child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                for (final (status, title, icon, color) in groups)
                  if (lines.any((l) => l.status == status)) ...[
                    // Nazwa grupy z liczbą pozycji (jak na kafelku stolika). Przy dużej czcionce
                    // „Wydaj wszystko” przechodzi pod nazwę zamiast ją łamać.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Glyph(icon.duotone, size: 20, color: color),
                              const SizedBox(width: 8),
                              Semantics(
                                header: true,
                                child: Text(
                                  '$title · ${lines.where((l) => l.status == status).length}',
                                  style: text.titleMedium?.copyWith(fontFeatures: _tabular),
                                ),
                              ),
                            ],
                          ),
                          if (status == LineStatus.ready)
                            TextButton(
                              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async {
                                      for (final l in order!.lines.where((l) => l.status == LineStatus.ready)) {
                                        await repo.updateItem(l.id, status: 'served');
                                      }
                                    }, 'Wydane.'),
                              child: const Text('Wydaj wszystko'),
                            ),
                        ],
                      ),
                    ),
                    // Gest przesunięcia nie jest widoczny, więc mówimy o nim wprost.
                    if (status == LineStatus.fresh)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                        child: Text(
                          'Przesuń pozycję w lewo, żeby ją usunąć.',
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
                      ),
                    for (final line in lines.where((l) => l.status == status))
                      if (line.status == LineStatus.fresh)
                        // Niewysłaną pozycję usuwa się przesunięciem w lewo.
                        Dismissible(
                          key: ValueKey('line-${line.id}'),
                          direction: _busy ? DismissDirection.none : DismissDirection.endToStart,
                          onDismissed: (_) => _remove(line),
                          background: const _RemoveBackground(),
                          child: _LineTile(
                            line: line,
                            busy: _busy,
                            onQuantity: (q) => _run(() => repo.updateItem(line.id, quantity: q)),
                            onServed: () {},
                          ),
                        )
                      else
                        _LineTile(
                          line: line,
                          busy: _busy,
                          onQuantity: (q) => _run(() => repo.updateItem(line.id, quantity: q)),
                          onServed: () => _run(() => repo.updateItem(line.id, status: 'served')),
                        ),
                  ],
              ],
              ),
            ),
      bottomNavigationBar: BottomActionBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Razem', style: text.titleMedium),
                const Spacer(),
                Text(Fmt.price(order?.total ?? 0), style: text.titleLarge?.copyWith(fontFeatures: _tabular)),
              ],
            ),
            const SizedBox(height: 10),
            // Przy dużej czcionce przyciski stają jeden pod drugim.
            ButtonPair(
              first: OutlinedButton.icon(
                style: _compactOutlined,
                onPressed: _busy ? null : _addFromMenu,
                icon: const Glyph(AppIcons.plus, size: 18),
                label: const Text('Dodaj z menu'),
              ),
              second: FilledButton.icon(
                style: _compact,
                onPressed: _busy || (order?.unsent ?? 0) == 0
                    ? null
                    : () => _run(() async {
                        final n = await repo.send(_order()!.id);
                        if (mounted) HapticFeedback.mediumImpact();
                        if (n == 0) return;
                      }, 'Wysłano na kuchnię.'),
                icon: const Glyph(AppIcons.send, size: 18),
                label: Text((order?.unsent ?? 0) > 0 ? 'Wyślij (${order!.unsent})' : 'Wyślij'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.busy, required this.onQuantity, required this.onServed});

  final WLine line;
  final bool busy;
  final ValueChanged<int> onQuantity;
  final VoidCallback onServed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fresh = line.status == LineStatus.fresh;
    final ready = line.status == LineStatus.ready;
    final served = line.status == LineStatus.served;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      decoration: BoxDecoration(
        color: ready ? AppColors.accentTint : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ready ? AppColors.accent.withValues(alpha: 0.6) : AppColors.ring),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Ilość w kwadracie po lewej, jak na bileciku kuchni.
          Container(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(10)),
            child: Text(
              '${line.quantity}×',
              style: text.titleSmall?.copyWith(fontFeatures: _tabular),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  style: text.titleSmall?.copyWith(color: served ? AppColors.textMuted : AppColors.text),
                ),
                if (line.details != null)
                  Text(line.details!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                if (line.note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Glyph(AppIcons.chatText, size: 13, color: StaffColors.pending),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(line.note!, style: text.bodySmall?.copyWith(color: StaffColors.pending)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  Fmt.price(line.total),
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
              ],
            ),
          ),
          if (fresh) ...[
            // Przy jednej sztuce minus jest wyłączony: pozycję usuwa się przesunięciem w lewo.
            IconButton(
              tooltip: 'Mniej',
              onPressed: busy || line.quantity <= 1 ? null : () => onQuantity(line.quantity - 1),
              icon: const Glyph(AppIcons.minus, size: 18),
            ),
            IconButton(
              tooltip: 'Więcej',
              onPressed: busy || line.quantity >= 99 ? null : () => onQuantity(line.quantity + 1),
              icon: const Glyph(AppIcons.plus, size: 18),
            ),
          ],
          if (ready)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 2),
              child: IconButton.filled(
                tooltip: 'Wydane',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.accentFill,
                  foregroundColor: AppColors.onAccent,
                  minimumSize: const Size(48, 48),
                ),
                onPressed: busy ? null : onServed,
                icon: Glyph(AppIcons.check, size: 22, color: AppColors.onAccent),
              ),
            ),
        ],
      ),
    );
  }
}

/// Czerwone tło pod pozycją przesuwaną w lewo.
class _RemoveBackground extends StatelessWidget {
  const _RemoveBackground();

  @override
  Widget build(BuildContext context) {
    // Na czerwieni ciemnego motywu biały napis ma za mały kontrast, więc kolor bierzemy z motywu.
    final onError = Theme.of(context).colorScheme.onError;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Usuń',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: onError),
          ),
          const SizedBox(width: 8),
          Glyph(AppIcons.trash, size: 20, color: onError),
        ],
      ),
    );
  }
}

enum _SettleMode {
  whole('Całość'),
  equal('Równo'),
  items('Pozycje');

  const _SettleMode(this.label);
  final String label;
}

/// Zamknięcie rachunku: rabat (kod wpisany przy rachunku albo z rezerwacji), napiwek i płatność całości, równy podział na osoby
/// albo płatność za wybrane pozycje (reszta zostaje na stoliku). Zwraca true, gdy rachunek jest zamknięty.
class _SettleSheet extends ConsumerStatefulWidget {
  const _SettleSheet({required this.restaurantId, required this.orderId, required this.memberId});

  final String restaurantId;
  final String orderId;
  final String memberId;

  @override
  ConsumerState<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends ConsumerState<_SettleSheet> {
  var _mode = _SettleMode.whole;
  var _method = WPayment.cash;
  final _tip = TextEditingController();
  final _received = TextEditingController();
  int _people = 2;
  final _personMethods = <int, WPayment>{};
  final _personTips = <int, TextEditingController>{};
  final _picked = <String, int>{};
  bool _busy = false;

  @override
  void dispose() {
    _tip.dispose();
    _received.dispose();
    for (final c in _personTips.values) {
      c.dispose();
    }
    super.dispose();
  }

  static int _money(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return v == null || v < 0 ? 0 : (v * 100).round();
  }

  static String _text(int grosze) {
    final zl = grosze ~/ 100;
    final gr = grosze % 100;
    return gr == 0 ? '$zl' : '$zl,${gr.toString().padLeft(2, '0')}';
  }

  TextEditingController _personTip(int i) => _personTips.putIfAbsent(i, TextEditingController.new);

  int _partTotal(WOrder order) => [
    for (final l in order.lines)
      if (l.status != LineStatus.cancelled) (_picked[l.id] ?? 0) * l.unitPriceGrosze,
  ].fold(0, (a, b) => a + b);

  /// Kod rabatowy przy rachunku: wybór w arkuszu z podpowiedziami albo usunięcie (null).
  Future<void> _discount({required bool remove}) async {
    String? code;
    if (!remove) {
      code = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _DiscountSheet(restaurantId: widget.restaurantId),
      );
      if (code == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(waiterRepositoryProvider).setDiscount(widget.orderId, code, widget.memberId);
      ref.invalidate(orderDueProvider(widget.orderId));
      if (mounted) {
        showMessage(context, code == null ? 'Kod usunięty z rachunku.' : 'Kod $code dodany do rachunku.', tone: ToastTone.success);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action, {required bool closes, required String message}) async {
    setState(() => _busy = true);
    try {
      await action();
      ref
        ..invalidate(openOrdersProvider(widget.restaurantId))
        ..invalidate(orderDueProvider(widget.orderId));
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, message, tone: ToastTone.success);
      if (closes) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _picked.clear();
          _tip.clear();
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pay(WOrder order, WDue due) {
    final repo = ref.read(waiterRepositoryProvider);
    switch (_mode) {
      case _SettleMode.whole:
        final tip = _money(_tip);
        _run(
          () => repo.settle(widget.orderId, [WPart(_method, due.due, tip: tip)], widget.memberId),
          closes: true,
          message: 'Rachunek zamknięty: ${Fmt.price(due.due)}, ${_method.label.toLowerCase()}'
              '${tip > 0 ? ', napiwek ${Fmt.price(tip)}' : ''}.',
        );
      case _SettleMode.equal:
        final parts = splitEqually(due.due, _people);
        _run(
          () => repo.settle(
            widget.orderId,
            [
              for (final (i, amount) in parts.indexed)
                WPart(_personMethods[i] ?? WPayment.cash, amount, tip: _money(_personTip(i))),
            ],
            widget.memberId,
          ),
          closes: true,
          message: 'Rachunek zamknięty: ${Fmt.price(due.due)} na $_people osoby.',
        );
      case _SettleMode.items:
        final part = _partTotal(order);
        final (_, partDue) = due.forPart(part);
        final all = order.lines.where((l) => l.status != LineStatus.cancelled).every((l) => (_picked[l.id] ?? 0) == l.quantity);
        _run(
          () => repo.payItems(
            widget.orderId,
            Map.of(_picked),
            [WPart(_method, all ? due.due : partDue, tip: _money(_tip))],
            widget.memberId,
          ),
          closes: all,
          message: all ? 'Rachunek zamknięty: ${Fmt.price(due.due)}.' : 'Opłacono część: ${Fmt.price(partDue)}.',
        );
    }
  }

  Widget _methods(WPayment value, ValueChanged<WPayment> onChanged) => Row(
    children: [
      for (final m in WPayment.values) ...[
        if (m != WPayment.values.first) const SizedBox(width: 8),
        Expanded(
          child: ChoiceChip(
            label: SizedBox(width: double.infinity, child: Text(m.label, textAlign: TextAlign.center)),
            selected: value == m,
            onSelected: (_) => onChanged(m),
          ),
        ),
      ],
    ],
  );

  Widget _tipRow(int base) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _tip,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
          decoration: const InputDecoration(labelText: 'Napiwek', suffixText: 'zł', isDense: true),
        ),
      ),
      for (final pct in const [5, 10, 15]) ...[
        const SizedBox(width: 6),
        OutlinedButton(
          onPressed: base <= 0 ? null : () => setState(() => _tip.text = _text((base * pct / 100).round())),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 10)),
          child: Text('$pct%'),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    WOrder? order;
    for (final o in ref.watch(openOrdersProvider(widget.restaurantId)).value ?? const <WOrder>[]) {
      if (o.id == widget.orderId) order = o;
    }
    final due = ref.watch(orderDueProvider(widget.orderId)).value;
    if (order == null) {
      return const SizedBox(height: 200, child: LoadingView());
    }
    final active = [for (final l in order.lines) if (l.status != LineStatus.cancelled) l];
    final part = _partTotal(order);
    final (partDiscount, partDue) = due?.forPart(part) ?? (0, part);
    final payDue = _mode == _SettleMode.items ? partDue : (due?.due ?? order.total);
    final tip = _money(_tip);
    final received = _money(_received);
    final change = _received.text.trim().isEmpty ? null : received - payDue - tip;

    Widget money(String label, int value, {TextStyle? style, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: (style ?? text.bodyMedium)?.copyWith(color: color))),
          Text(Fmt.price(value), style: (style ?? text.bodyMedium)?.copyWith(color: color, fontFeatures: _tabular)),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + _bottomInset(context)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (final m in _SettleMode.values) ...[
                  if (m != _SettleMode.values.first) const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: SizedBox(width: double.infinity, child: Text(m.label, textAlign: TextAlign.center)),
                      selected: _mode == m,
                      onSelected: (_) => setState(() => _mode = m),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            if (_mode == _SettleMode.items)
              for (final l in active)
                Row(
                  children: [
                    Expanded(child: Text([l.name, ?l.details].join(' · '), style: text.bodyMedium)),
                    IconButton(
                      tooltip: 'Mniej',
                      onPressed: (_picked[l.id] ?? 0) == 0 ? null : () => setState(() => _picked[l.id] = _picked[l.id]! - 1),
                      icon: const Glyph(AppIcons.minus, size: 18),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${_picked[l.id] ?? 0}/${l.quantity}',
                        textAlign: TextAlign.center,
                        style: text.titleSmall?.copyWith(
                          fontFeatures: _tabular,
                          color: (_picked[l.id] ?? 0) > 0 ? AppColors.accent : AppColors.textMuted,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Więcej',
                      onPressed: (_picked[l.id] ?? 0) >= l.quantity
                          ? null
                          : () => setState(() => _picked[l.id] = (_picked[l.id] ?? 0) + 1),
                      icon: const Glyph(AppIcons.plus, size: 18),
                    ),
                  ],
                ),
            if (_mode == _SettleMode.items) const SizedBox(height: 8),
            // Kod rabatowy przy rachunku (zastępuje kod z rezerwacji).
            if (due?.code case final code?)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                decoration: BoxDecoration(color: AppColors.accentTint, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Glyph(AppIcons.sealPercent, size: 18, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Kod ${due?.label ?? code}', style: text.bodyMedium)),
                    TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: _busy ? null : () => _discount(remove: true),
                      child: const Text('Usuń'),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : () => _discount(remove: false),
                  icon: const Glyph(AppIcons.sealPercent, size: 18),
                  label: Text(due?.reservationCode != null ? 'Inny kod rabatowy' : 'Kod rabatowy'),
                ),
              ),
            money('Suma', order.total, color: AppColors.textMuted),
            if (due != null && due.discount > 0) money('Rabat ${due.label ?? ''}', -due.discount, color: AppColors.accent),
            if (due != null && due.deposit > 0) money('Zadatek z rezerwacji', -due.deposit, color: AppColors.accent),
            money('Do zapłaty', due?.due ?? order.total, style: text.titleLarge),
            if (_mode == _SettleMode.items) ...[
              const SizedBox(height: 6),
              money('Wybrane pozycje', part),
              if (partDiscount > 0) money('Rabat', -partDiscount, color: AppColors.accent),
              money('Płaci teraz', partDue, style: text.titleMedium),
            ],
            const SizedBox(height: 16),
            if (_mode == _SettleMode.equal) ...[
              Row(
                children: [
                  Text('Osób', style: text.titleSmall),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Mniej osób',
                    onPressed: _people <= 2 ? null : () => setState(() => _people--),
                    icon: const Glyph(AppIcons.minus, size: 18),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text('$_people', textAlign: TextAlign.center, style: text.titleMedium?.copyWith(fontFeatures: _tabular)),
                  ),
                  IconButton(
                    tooltip: 'Więcej osób',
                    onPressed: _people >= 20 ? null : () => setState(() => _people++),
                    icon: const Glyph(AppIcons.plus, size: 18),
                  ),
                ],
              ),
              for (final (i, amount) in splitEqually(due?.due ?? order.total, _people).indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Osoba ${i + 1}\n${Fmt.price(amount)}',
                          style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                        ),
                      ),
                      DropdownButton<WPayment>(
                        value: _personMethods[i] ?? WPayment.cash,
                        underline: const SizedBox.shrink(),
                        items: [for (final m in WPayment.values) DropdownMenuItem(value: m, child: Text(m.label))],
                        onChanged: (m) => setState(() => _personMethods[i] = m!),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 92,
                        child: TextField(
                          controller: _personTip(i),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                          decoration: const InputDecoration(labelText: 'Napiwek', isDense: true),
                        ),
                      ),
                    ],
                  ),
                ),
            ] else ...[
              _methods(_method, (m) => setState(() => _method = m)),
              const SizedBox(height: 12),
              _tipRow(payDue),
              if (_method == WPayment.cash) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _received,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  decoration: const InputDecoration(labelText: 'Otrzymano', suffixText: 'zł'),
                  onChanged: (_) => setState(() {}),
                ),
                if (change != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Glyph(
                        change >= 0 ? AppIcons.handCoins : AppIcons.warning,
                        size: 18,
                        color: change >= 0 ? AppColors.accent : AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          change >= 0 ? 'Reszta ${Fmt.price(change)}' : 'Brakuje ${Fmt.price(-change)}',
                          style: text.titleMedium?.copyWith(
                            color: change >= 0 ? AppColors.accent : AppColors.error,
                            fontFeatures: _tabular,
                          ),
                        ),
                      ),
                      // Gość zostawia resztę: idzie do Twojego napiwku.
                      if (change > 0)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                          onPressed: () => setState(() => _tip.text = _text(received - payDue)),
                          icon: const Glyph(AppIcons.handCoins, size: 16),
                          label: const Text('Bez reszty'),
                        ),
                    ],
                  ),
                ],
              ],
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy || due == null || (_mode == _SettleMode.items && part == 0) ? null : () => _pay(order!, due),
              icon: const Glyph(AppIcons.checkCircle, size: 20),
              label: Text(_mode == _SettleMode.items ? 'Zapłać za wybrane' : 'Zamknij rachunek'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Menu do nabijania
// ---------------------------------------------------------------

/// Menu lokalu: stuknięcie dodaje danie do rachunku stolika. Ekran zostaje otwarty,
/// więc można nabić kilka dań po kolei. „Przejdź dalej” na dole wraca do rachunku stolika.
class MenuPickerScreen extends ConsumerStatefulWidget {
  const MenuPickerScreen({super.key, required this.job, required this.table});

  final Job job;
  final WTable table;

  @override
  ConsumerState<MenuPickerScreen> createState() => _MenuPickerScreenState();
}

class _MenuPickerScreenState extends ConsumerState<MenuPickerScreen> {
  String? _sectionId;
  String _query = '';
  int _added = 0;

  /// Kolejne dodania idą do bazy po kolei, żeby pierwsze otworzyło rachunek tylko raz.
  Future<void> _queue = Future.value();
  bool _leaving = false;

  /// Liczba gości przy nowym rachunku: zapytana raz, przed pierwszym daniem (null: pominięta).
  bool _askedGuests = false;
  int? _guests;

  /// Do szczegółów rachunku, gdy wszystkie stuknięte dania są już zapisane.
  Future<void> _next() async {
    setState(() => _leaving = true);
    await _queue;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _add(WMenuItem item, {bool withOptions = false}) async {
    if (!item.available) {
      showMessage(context, '„${item.name}” jest chwilowo niedostępne.');
      return;
    }
    _Choice choice = const _Choice();
    if (item.hasOptions || withOptions) {
      final picked = await showModalBottomSheet<_Choice>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _OptionsSheet(item: item),
      );
      if (picked == null || !mounted) return;
      choice = picked;
    }
    // Nowy rachunek stolika: najpierw liczba gości (można pominąć, pominięcie widać w statystykach).
    if (!_askedGuests) {
      final open = (ref.read(openOrdersProvider(widget.job.restaurantId)).value ?? const <WOrder>[])
          .any((o) => o.tableId == widget.table.id);
      if (!open) {
        final answer = await showModalBottomSheet<({int? guests})>(
          context: context,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => _GuestsSheet(title: widget.table.title),
        );
        if (answer == null || !mounted) return;
        _guests = answer.guests;
      }
      _askedGuests = true;
    }
    HapticFeedback.selectionClick();
    final repo = ref.read(waiterRepositoryProvider);
    final job = widget.job;
    _queue = _queue.then((_) async {
      try {
        WOrder? order;
        for (final o in await ref.read(openOrdersProvider(job.restaurantId).future)) {
          if (o.tableId == widget.table.id) order = o;
        }
        // Otwarcie zwraca istniejący rachunek, więc szybkie stuknięcia nie otworzą dwóch.
        final orderId = order?.id ??
            await repo.openOrder(
              job.restaurantId,
              widget.table.id,
              job.memberId,
              guests: _guests,
              skipGuests: _guests == null,
            );
        await repo.addItem(
          orderId: orderId,
          menuItemId: item.id,
          memberId: job.memberId,
          variant: choice.variant,
          addons: choice.addons,
          quantity: choice.quantity,
          note: choice.note,
          changes: choice.changes,
        );
        ref.invalidate(openOrdersProvider(job.restaurantId));
        if (mounted) {
          setState(() => _added += choice.quantity);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text('Dodano: ${item.name}'), duration: const Duration(seconds: 1)));
        }
      } catch (e) {
        if (mounted) showError(context, e);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(menuProvider(widget.job.restaurantId));
    return Scaffold(
      appBar: AppBar(
        title: Text('Menu · ${widget.table.title}'),
        actions: [
          // Ile dań dodano z tego ekranu: słowo z ikoną, czytnik ekranu ogłasza zmianę.
          if (_added > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Semantics(
                  liveRegion: true,
                  child: StatusChip(label: 'Dodano: $_added', icon: AppIcons.check, color: AppColors.accent),
                ),
              ),
            ),
        ],
      ),
      body: menu.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(menuProvider(widget.job.restaurantId))),
        data: (sections) {
          final withItems = sections.where((s) => s.items.isNotEmpty).toList();
          if (withItems.isEmpty) {
            return const MessageView(
              icon: AppIcons.bookOpen,
              title: 'Menu jest puste',
              message: 'Kierownik dodaje dania w panelu, w zakładce „Menu”.',
            );
          }
          final current = withItems.firstWhere((s) => s.id == _sectionId, orElse: () => withItems.first);
          final items = _query.isEmpty
              ? current.items
              : [
                  for (final s in withItems)
                    for (final i in s.items)
                      if (i.name.toLowerCase().contains(_query)) i,
                ];
          return ContentWidth(
            child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Szukaj w menu',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: Glyph(AppIcons.search, size: 18, color: AppColors.textMuted),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  ),
                ),
              ),
              if (_query.isEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final s in withItems)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(s.name),
                            selected: s.id == current.id,
                            onSelected: (_) => setState(() => _sectionId = s.id),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _MenuRow(
                    item: items[i],
                    onAdd: () => _add(items[i]),
                    onOptions: () => _add(items[i], withOptions: true),
                  ),
                ),
              ),
            ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _leaving ? null : _next,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Przejdź dalej'),
                SizedBox(width: 8),
                Glyph(AppIcons.caretRight, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Danie w menu do nabijania: nazwa, cena albo „Niedostępne” z ikoną, zmiana składników i dodanie.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item, required this.onAdd, required this.onOptions});

  final WMenuItem item;
  final VoidCallback onAdd;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final price = item.priceVaries ? 'od ${Fmt.price(item.fromPrice)}' : Fmt.price(item.fromPrice);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.ring)),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: item.available ? '${item.name}, $price. Dodaj do rachunku' : '${item.name}, niedostępne',
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: text.titleSmall?.copyWith(color: item.available ? AppColors.text : AppColors.textMuted),
                        ),
                        const SizedBox(height: 2),
                        // Niedostępne: słowo z ikoną zamiast przygaszenia całego wiersza (kontrast zostaje czytelny).
                        if (item.available)
                          Text(price, style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular))
                        else
                          StatusChip(label: 'Niedostępne', icon: AppIcons.prohibit, color: AppColors.error),
                      ],
                    ),
                  ),
                ),
                // Zmiana składników („bez cebuli”, „więcej sera”) i uwaga dla kuchni.
                if (item.available) ...[
                  IconButton(
                    tooltip: 'Zmień składniki: ${item.name}',
                    onPressed: onOptions,
                    icon: Glyph(AppIcons.notePencil, size: 20, color: AppColors.textMuted),
                  ),
                  ExcludeSemantics(
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.accentTint, shape: BoxShape.circle),
                      child: Glyph(item.hasOptions ? AppIcons.sliders : AppIcons.plus, size: 18, color: AppColors.accent),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Choice {
  const _Choice({this.variant, this.addons = const [], this.quantity = 1, this.note, this.changes = const []});

  final String? variant;
  final List<String> addons;
  final int quantity;
  final String? note;

  /// Zmiany składników: „bez cebuli”, „więcej sera”.
  final List<WChange> changes;
}

/// Wybór wariantu, dodatków, zmian składników, ilości i uwagi dla kuchni.
class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({required this.item});

  final WMenuItem item;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late String? _variant = widget.item.variants.length == 1 ? widget.item.variants.first.name : null;
  final _addons = <String>{};
  int _quantity = 1;
  final _note = TextEditingController();

  /// Składniki z receptury: false = bez, true = więcej (brak w mapie: normalnie).
  final _recipe = <String, bool>{};

  /// Inne składniki wpisane ręcznie.
  final _custom = <WChange>[];
  final _customName = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    _customName.dispose();
    super.dispose();
  }

  void _addCustom(bool extra) {
    final name = _customName.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _custom.removeWhere((c) => c.name.toLowerCase() == name.toLowerCase());
      _custom.add(WChange(name, extra: extra));
      _customName.clear();
    });
  }

  int get _price {
    var price = widget.item.priceGrosze;
    for (final v in widget.item.variants) {
      if (v.name == _variant) price = v.priceGrosze;
    }
    for (final a in widget.item.addons) {
      if (_addons.contains(a.name)) price += a.priceGrosze;
    }
    return price * _quantity;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final needsVariant = item.variants.isNotEmpty && _variant == null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + _bottomInset(context)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.name, style: text.titleLarge),
            if (item.variants.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Wariant', style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in item.variants)
                    ChoiceChip(
                      label: Text('${v.name} · ${Fmt.price(v.priceGrosze)}'),
                      selected: _variant == v.name,
                      onSelected: (_) => setState(() => _variant = v.name),
                    ),
                ],
              ),
            ],
            if (item.addons.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Dodatki', style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in item.addons)
                    FilterChip(
                      label: Text('${a.name} +${Fmt.price(a.priceGrosze)}'),
                      selected: _addons.contains(a.name),
                      onSelected: (on) => setState(() => on ? _addons.add(a.name) : _addons.remove(a.name)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('Składniki', style: text.titleSmall),
            const SizedBox(height: 8),
            for (final r in item.ingredients)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(r.name, style: text.bodyMedium)),
                    ChoiceChip(
                      label: const Text('Bez'),
                      selected: _recipe[r.id] == false,
                      onSelected: (on) => setState(() => on ? _recipe[r.id] = false : _recipe.remove(r.id)),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('Więcej'),
                      selected: _recipe[r.id] == true,
                      onSelected: (on) => setState(() => on ? _recipe[r.id] = true : _recipe.remove(r.id)),
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
                      hintText: item.ingredients.isEmpty ? 'Składnik, np. cebula' : 'Inny składnik',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _addCustom(false),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: const Text('Bez'),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: () => _addCustom(true),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: const Text('Więcej'),
                ),
              ],
            ),
            if (_custom.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
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
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Ilość', style: text.titleSmall),
                const Spacer(),
                IconButton(
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Glyph(AppIcons.minus, size: 18),
                ),
                Text('$_quantity', style: text.titleMedium?.copyWith(fontFeatures: _tabular)),
                IconButton(
                  onPressed: _quantity < 99 ? () => setState(() => _quantity++) : null,
                  icon: const Glyph(AppIcons.plus, size: 18),
                ),
              ],
            ),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Uwaga dla kuchni', hintText: 'np. bez cebuli', counterText: ''),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: needsVariant
                  ? null
                  : () => Navigator.pop(
                      context,
                      _Choice(
                        variant: _variant,
                        addons: [
                          for (final a in item.addons)
                            if (_addons.contains(a.name)) a.name,
                        ],
                        quantity: _quantity,
                        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                        changes: [
                          for (final r in item.ingredients)
                            if (_recipe[r.id] case final extra?) WChange(r.name, extra: extra, itemId: r.id),
                          ..._custom,
                        ],
                      ),
                    ),
              child: Text(needsVariant ? 'Wybierz wariant' : 'Dodaj · ${Fmt.price(_price)}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ilu gości przy stoliku. „Pomiń” jest dozwolone, ale liczy się w statystykach zespołu.
class _GuestsSheet extends StatelessWidget {
  const _GuestsSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + _bottomInset(context)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$title · ilu gości?', style: text.titleLarge),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var n = 1; n <= 12; n++)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: Size.zero, padding: EdgeInsets.zero),
                  onPressed: () => Navigator.pop<({int? guests})>(context, (guests: n)),
                  child: Text('$n', style: const TextStyle(fontSize: 20, fontFeatures: _tabular)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop<({int? guests})>(context, (guests: null)),
            child: const Text('Pomiń'),
          ),
          Text(
            'Pominięcie liczy się w statystykach zespołu.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Wpisanie kodu rabatowego z podpowiedziami kodów lokalu, które działają dziś. Zwraca kod.
class _DiscountSheet extends ConsumerStatefulWidget {
  const _DiscountSheet({required this.restaurantId});

  final String restaurantId;

  @override
  ConsumerState<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends ConsumerState<_DiscountSheet> {
  final _code = TextEditingController();
  Timer? _debounce;
  List<WDiscountHint> _hints = const [];
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    final request = ++_request;
    try {
      final hints = await ref.read(waiterRepositoryProvider).discountHints(widget.restaurantId, query);
      if (mounted && request == _request) setState(() => _hints = hints);
    } catch (_) {
      // Bez podpowiedzi kod i tak można wpisać.
    }
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _load(value));
  }

  void _submit(String value) {
    final code = value.trim().toUpperCase();
    if (code.isNotEmpty) Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + _bottomInset(context)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Kod rabatowy', style: text.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  onChanged: _changed,
                  onSubmitted: _submit,
                  decoration: const InputDecoration(hintText: 'Wpisz albo wybierz z listy'),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () => _submit(_code.text),
                style: _compact,
                child: const Text('Dodaj'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_hints.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _code.text.isEmpty ? 'Lokal nie ma teraz aktywnych kodów.' : 'Brak pasujących kodów.',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final h in _hints)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: Glyph(AppIcons.sealPercent, size: 20, color: AppColors.accent),
                      title: Text(h.code, style: text.titleSmall),
                      subtitle: h.note == null ? null : Text(h.note!, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text(h.valueText, style: text.titleSmall?.copyWith(color: AppColors.accent)),
                      onTap: () => Navigator.pop(context, h.code),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Odstęp od dołu ekranu dla okien wysuwanych z dołu: klawiatura albo przyciski systemu
/// Androida (aplikacja rysuje się pod nimi), zależnie od tego, co jest wyżej.
double _bottomInset(BuildContext context) {
  final keyboard = MediaQuery.viewInsetsOf(context).bottom;
  final system = MediaQuery.viewPaddingOf(context).bottom;
  return keyboard > system ? keyboard : system;
}
