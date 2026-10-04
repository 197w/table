import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'orders_data.dart';

const _tabular = [FontFeature.tabularFigures()];
const _amber = Color(0xFFD99A15);

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

/// Kelner wybiera stolik. Kafel pokazuje kwotę otwartego rachunku, dania do wydania (zielone)
/// i niewysłane na kuchnię (żółte).
class WaiterTablesScreen extends ConsumerWidget {
  const WaiterTablesScreen({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final tables = ref.watch(tablesProvider(job.restaurantId));
    final orders = ref.watch(openOrdersProvider(job.restaurantId)).value ?? const <WOrder>[];
    final byTable = {for (final o in orders) ?o.tableId: o};

    return Scaffold(
      appBar: AppBar(title: Text('Zamówienia · ${job.restaurantName}')),
      body: tables.when(
        loading: () => const LoadingView(),
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
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(openOrdersProvider(job.restaurantId));
              await ref.read(openOrdersProvider(job.restaurantId).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                for (final zone in zones) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    child: Text(
                      zone.toUpperCase(),
                      style: text.labelMedium?.copyWith(color: AppColors.textMuted, letterSpacing: 1.1),
                    ),
                  ),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.05,
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
          );
        },
      ),
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, required this.order, required this.onTap});

  final WTable table;
  final WOrder? order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final open = order != null;
    return PressScale(
      child: Material(
        color: open ? AppColors.accentTint : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: open ? AppColors.accent : AppColors.ring),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        table.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.headlineSmall?.copyWith(color: open ? AppColors.accent : null),
                      ),
                    ),
                    if ((order?.ready ?? 0) > 0) _Badge('${order!.ready}', AppColors.accentFill, AppColors.onAccent),
                    if ((order?.unsent ?? 0) > 0) ...[
                      const SizedBox(width: 4),
                      _Badge('${order!.unsent}', _amber, Colors.black),
                    ],
                  ],
                ),
                const Spacer(),
                Text(
                  open ? Fmt.price(order!.total) : '${table.seats} os.',
                  style: text.bodyMedium?.copyWith(
                    color: open ? AppColors.text : AppColors.textMuted,
                    fontFeatures: _tabular,
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

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color, this.textColor);

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor, fontWeight: FontWeight.w600),
    ),
  );
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
    final groups = [
      (LineStatus.ready, 'DO WYDANIA'),
      (LineStatus.fresh, 'DO WYSŁANIA'),
      (LineStatus.sent, 'NA KUCHNI'),
      (LineStatus.served, 'WYDANE'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.table.title),
        actions: [
          if (order != null && order.total > 0)
            TextButton(onPressed: _busy ? null : () => _close(order!), child: const Text('Rachunek')),
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                for (final (status, title) in groups)
                  if (lines.any((l) => l.status == status)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: text.labelMedium?.copyWith(
                                letterSpacing: 1.1,
                                color: status == LineStatus.ready ? AppColors.accent : AppColors.textMuted,
                              ),
                            ),
                          ),
                          if (status == LineStatus.ready)
                            TextButton(
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
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.ring)),
          ),
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: _compactOutlined,
                      onPressed: _busy ? null : _addFromMenu,
                      icon: const Glyph(AppIcons.plus, size: 18),
                      label: const Text('Dodaj z menu'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: _compact,
                      onPressed: _busy || (order?.unsent ?? 0) == 0
                          ? null
                          : () => _run(() async {
                              final n = await repo.send(_order()!.id);
                              if (mounted) HapticFeedback.mediumImpact();
                              if (n == 0) return;
                            }, 'Wysłano na kuchnię.'),
                      child: Text((order?.unsent ?? 0) > 0 ? 'Wyślij (${order!.unsent})' : 'Wyślij'),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: ready ? AppColors.accentTint : (fresh ? AppColors.surfaceRaised : AppColors.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ready ? AppColors.accent : AppColors.ring),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${line.quantity}× ${line.name}', style: text.titleSmall),
                if (line.details != null)
                  Text(line.details!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                if (line.note != null)
                  Text(line.note!, style: text.bodySmall?.copyWith(color: _amber, fontStyle: FontStyle.italic)),
                const SizedBox(height: 2),
                Text(Fmt.price(line.total), style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
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
            Text('${line.quantity}', style: text.titleMedium?.copyWith(fontFeatures: _tabular)),
            IconButton(
              tooltip: 'Więcej',
              onPressed: busy || line.quantity >= 99 ? null : () => onQuantity(line.quantity + 1),
              icon: const Glyph(AppIcons.plus, size: 18),
            ),
          ],
          if (ready)
            IconButton(
              tooltip: 'Wydane',
              onPressed: busy ? null : onServed,
              icon: Glyph(AppIcons.check, size: 22, color: AppColors.accent),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Usuń',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Glyph(AppIcons.trash, size: 20, color: Colors.white),
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

/// Zamknięcie rachunku: rabat z kodu rezerwacji, napiwek i płatność całości, równy podział na osoby
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
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 10)),
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
                      visualDensity: VisualDensity.compact,
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
                      visualDensity: VisualDensity.compact,
                      onPressed: (_picked[l.id] ?? 0) >= l.quantity
                          ? null
                          : () => setState(() => _picked[l.id] = (_picked[l.id] ?? 0) + 1),
                      icon: const Glyph(AppIcons.plus, size: 18),
                    ),
                  ],
                ),
            if (_mode == _SettleMode.items) const SizedBox(height: 8),
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
                    onPressed: _people <= 2 ? null : () => setState(() => _people--),
                    icon: const Glyph(AppIcons.minus, size: 18),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text('$_people', textAlign: TextAlign.center, style: text.titleMedium?.copyWith(fontFeatures: _tabular)),
                  ),
                  IconButton(
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
                  Text(
                    change >= 0 ? 'Reszta ${Fmt.price(change)}' : 'Brakuje ${Fmt.price(-change)}',
                    style: text.titleMedium?.copyWith(
                      color: change >= 0 ? AppColors.accent : AppColors.error,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ],
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || due == null || (_mode == _SettleMode.items && part == 0) ? null : () => _pay(order!, due),
              child: Text(_mode == _SettleMode.items ? 'Zapłać za wybrane' : 'Zamknij rachunek'),
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

  /// Do szczegółów rachunku, gdy wszystkie stuknięte dania są już zapisane.
  Future<void> _next() async {
    setState(() => _leaving = true);
    await _queue;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _add(WMenuItem item) async {
    if (!item.available) {
      showMessage(context, '„${item.name}” jest chwilowo niedostępne.');
      return;
    }
    _Choice choice = const _Choice();
    if (item.hasOptions) {
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
        final orderId = order?.id ?? await repo.openOrder(job.restaurantId, widget.table.id, job.memberId);
        await repo.addItem(
          orderId: orderId,
          menuItemId: item.id,
          memberId: job.memberId,
          variant: choice.variant,
          addons: choice.addons,
          quantity: choice.quantity,
          note: choice.note,
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
    final text = Theme.of(context).textTheme;
    final menu = ref.watch(menuProvider(widget.job.restaurantId));
    return Scaffold(
      appBar: AppBar(
        title: Text('Menu · ${widget.table.title}'),
        actions: [
          if (_added > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: Text('+$_added', style: text.titleMedium?.copyWith(color: AppColors.accent))),
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
          return Column(
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
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return Opacity(
                      opacity: item.available ? 1 : 0.45,
                      child: Material(
                        color: AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: AppColors.ring),
                        ),
                        child: InkWell(
                          onTap: () => _add(item),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.name, style: text.titleSmall),
                                      Text(
                                        !item.available
                                            ? 'Niedostępne'
                                            : item.priceVaries
                                            ? 'od ${Fmt.price(item.fromPrice)}'
                                            : Fmt.price(item.fromPrice),
                                        style: text.bodyMedium?.copyWith(
                                          color: item.available ? AppColors.textMuted : AppColors.error,
                                          fontFeatures: _tabular,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Glyph(
                                  item.hasOptions ? AppIcons.sliders : AppIcons.plus,
                                  size: 20,
                                  color: AppColors.accent,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
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

class _Choice {
  const _Choice({this.variant, this.addons = const [], this.quantity = 1, this.note});

  final String? variant;
  final List<String> addons;
  final int quantity;
  final String? note;
}

/// Wybór wariantu, dodatków, ilości i uwagi dla kuchni.
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

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
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

/// Odstęp od dołu ekranu dla okien wysuwanych z dołu: klawiatura albo przyciski systemu
/// Androida (aplikacja rysuje się pod nimi), zależnie od tego, co jest wyżej.
double _bottomInset(BuildContext context) {
  final keyboard = MediaQuery.viewInsetsOf(context).bottom;
  final system = MediaQuery.viewPaddingOf(context).bottom;
  return keyboard > system ? keyboard : system;
}
