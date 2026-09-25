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
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
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
    final method = await showModalBottomSheet<WPayment>(
      context: context,
      showDragHandle: true,
      builder: (context) => _CloseSheet(total: order.total),
    );
    if (method == null) return;
    await _run(
      () => ref.read(waiterRepositoryProvider).close(order.id, method, widget.job.memberId),
      'Rachunek zamknięty: ${Fmt.price(order.total)}, ${method.label.toLowerCase()}.',
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final orders = ref.watch(openOrdersProvider(_rid));
    WOrder? order;
    for (final o in orders.value ?? const <WOrder>[]) {
      if (o.tableId == widget.table.id) order = o;
    }
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
      body: order == null || order.lines.isEmpty
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
                  if (order.lines.any((l) => l.status == status)) ...[
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
                    for (final line in order.lines.where((l) => l.status == status))
                      _LineTile(
                        line: line,
                        busy: _busy,
                        onQuantity: (q) => _run(
                          () => q < 1
                              ? repo.updateItem(line.id, status: 'cancelled')
                              : repo.updateItem(line.id, quantity: q),
                        ),
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
            IconButton(
              tooltip: line.quantity == 1 ? 'Usuń' : 'Mniej',
              onPressed: busy ? null : () => onQuantity(line.quantity - 1),
              icon: Glyph(line.quantity == 1 ? AppIcons.trash : AppIcons.minus, size: 18),
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

/// Zamknięcie rachunku: forma płatności, a przy gotówce wyliczenie reszty.
class _CloseSheet extends StatefulWidget {
  const _CloseSheet({required this.total});

  final int total;

  @override
  State<_CloseSheet> createState() => _CloseSheetState();
}

class _CloseSheetState extends State<_CloseSheet> {
  WPayment? _method;
  final _received = TextEditingController();

  @override
  void dispose() {
    _received.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final digits = _received.text.replaceAll(',', '.');
    final received = double.tryParse(digits);
    final change = received == null ? null : (received * 100).round() - widget.total;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Do zapłaty', style: text.titleMedium),
              const Spacer(),
              Text(Fmt.price(widget.total), style: text.headlineSmall?.copyWith(fontFeatures: _tabular)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final m in WPayment.values) ...[
                if (m != WPayment.values.first) const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: SizedBox(width: double.infinity, child: Text(m.label, textAlign: TextAlign.center)),
                    selected: _method == m,
                    onSelected: (_) => setState(() => _method = m),
                  ),
                ),
              ],
            ],
          ),
          if (_method == WPayment.cash) ...[
            const SizedBox(height: 14),
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
          const SizedBox(height: 12),
          Text(
            'Kartę podarunkową przyjmiesz w panelu. Paragon wydrukuj na kasie.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _method == null ? null : () => Navigator.pop(context, _method),
            child: const Text('Zamknij rachunek'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// Menu do nabijania
// ---------------------------------------------------------------

/// Menu lokalu: stuknięcie dodaje danie do rachunku stolika. Ekran zostaje otwarty,
/// więc można nabić kilka dań po kolei.
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
        if (mounted) showMessage(context, errorText(e));
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
                                            : item.variants.isEmpty
                                            ? Fmt.price(item.priceGrosze)
                                            : 'od ${Fmt.price(item.variants.map((v) => v.priceGrosze).reduce((a, b) => a < b ? a : b))}',
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
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
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
