import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import 'inventory_docs.dart';
import 'inventory_pdf.dart';

const _tabular = [FontFeature.tabularFigures()];

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';

/// Kolumny Składników: składnik, opakowanie, inwentaryzacja, ruchy od niej, stan teraz.
const _flex = [5, 3, 3, 3, 2];

/// Kolumny spisu: składnik, opakowanie, pełne opakowania, reszta, razem, powinno być, różnica.
const _countFlex = [5, 3, 3, 4, 2, 2, 2];

/// „+2,5 kg”, „−300 g”, „0 kg”.
String _signed(double v, InventoryUnit unit) {
  if (v.abs() < 0.0005) return '0 ${unit.label}';
  return '${v > 0 ? '+' : '−'}${inventoryNumber(v.abs())} ${unit.label}';
}

Color _diffColor(double v) => v.abs() < 0.0005 ? AppColors.textMuted : (v > 0 ? AppColors.accent : AppColors.error);

/// Składniki pogrupowane po lokalizacji (alfabetycznie, bez lokalizacji na końcu). Bez żadnej lokalizacji: jedna
/// grupa bez nagłówka.
List<(String?, List<InventoryItem>)> _byLocation(List<InventoryItem> items) {
  final groups = <String?, List<InventoryItem>>{};
  for (final i in items) {
    final loc = i.location?.trim();
    groups.putIfAbsent(loc == null || loc.isEmpty ? null : loc, () => []).add(i);
  }
  final keys = groups.keys.whereType<String>().toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [for (final k in keys) (k, groups[k]!), if (groups.containsKey(null)) (null, groups[null]!)];
}

/// Inwentaryzacja: zakładki Spis (trwająca inwentaryzacja), Składniki (lista ze stanem), Dostawy i usunięcia
/// oraz Historia. Uprawnienia: `inventory_edit` (składniki, pojemniki, okres, usuwanie wpisów) i
/// `inventory_count` (spis, dostawy, usunięcia).
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  /// Null: zakładka wybrana sama (Spis, gdy inwentaryzacja trwa, inaczej Składniki).
  int? _tab;
  bool _busy = false;

  String? get _memberId {
    final member = ref.read(panelMemberProvider);
    return member == null || member.isAccount ? null : member.memberId;
  }

  Future<void> _run(Future<void> Function() action, [String? done]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (done != null && mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(String restaurantId) => _run(() async {
    await ref.read(repositoryProvider).startInventory(restaurantId, memberId: _memberId);
    ref.invalidate(inventoryCountsProvider(restaurantId));
    if (mounted) setState(() => _tab = 0);
  });

  Future<void> _finish(String restaurantId, InventoryCount count, int missing) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zakończyć inwentaryzację?'),
        content: Text(
          missing == 0
              ? 'Wpisane ilości staną się aktualnym stanem składników.'
              : 'Bez ilości: ${missing == 1 ? 'jeden składnik' : '$missing składników'}. '
                    'Zostaną pominięte w tej inwentaryzacji.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Wróć')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Zakończ')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(repositoryProvider).finishInventory(count.id, memberId: _memberId);
      ref
        ..invalidate(inventoryCountsProvider(restaurantId))
        ..invalidate(inventoryStockProvider(restaurantId));
      if (mounted) setState(() => _tab = 3);
    }, 'Inwentaryzacja zapisana.');
  }

  Future<void> _discard(String restaurantId, InventoryCount count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anulować inwentaryzację?'),
        content: const Text('Wpisane ilości zostaną usunięte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Wróć')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Anuluj inwentaryzację'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(repositoryProvider).discardInventory(count.id);
      ref.invalidate(inventoryCountsProvider(restaurantId));
    }, 'Inwentaryzacja anulowana.');
  }

  Future<void> _editItem(String restaurantId, List<InventoryItem> items, [InventoryItem? item]) async {
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => InventoryItemDialog(
        restaurantId: restaurantId,
        item: item,
        locations: {
          for (final i in items)
            if (i.location?.trim().isNotEmpty ?? false) i.location!.trim(),
        }.toList(),
      ),
    );
    if (saved == null) return;
    ref
      ..invalidate(inventoryItemsProvider(restaurantId))
      ..invalidate(inventoryStockProvider(restaurantId));
  }

  Future<void> _addDoc(String restaurantId, List<InventoryItem> items, bool delivery) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          InventoryDocDialog(restaurantId: restaurantId, delivery: delivery, items: items, memberId: _memberId),
    );
    if (saved == true && mounted && _tab != 2 && _tab != 0) setState(() => _tab = 2);
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final rid = restaurant.id;
    final permissions = ref.watch(memberPermissionsProvider);
    final canEdit = permissions.contains('inventory_edit');
    final canCount = permissions.contains('inventory_count');

    final itemsAsync = ref.watch(inventoryItemsProvider(rid));
    final stock = {
      for (final s in ref.watch(inventoryStockProvider(rid)).value ?? const <InventoryStock>[]) s.itemId: s,
    };
    final containers = ref.watch(inventoryContainersProvider(rid)).value ?? const <InventoryContainer>[];
    final countsAsync = ref.watch(inventoryCountsProvider(rid));
    final period = ref.watch(profileProvider(rid)).value?.inventoryPeriod ?? 'week';
    final items = itemsAsync.value ?? const <InventoryItem>[];
    final counts = countsAsync.value ?? const <InventoryCount>[];
    final open = counts.where((c) => c.open).firstOrNull;
    final finished = counts.where((c) => !c.open).toList();
    final last = finished.firstOrNull;
    final next = nextInventoryDay(period, last?.finishedAt?.toLocal());
    final today = dateOnly(DateTime.now());
    final due = last == null || !today.isBefore(next!);
    final tab = _tab ?? (open != null ? 0 : 1);

    final loading = (itemsAsync.isLoading && !itemsAsync.hasValue) || (countsAsync.isLoading && !countsAsync.hasValue);
    final error = itemsAsync.error ?? countsAsync.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          below: Row(
            children: [
              IconTabs<int>(
                options: const [
                  (0, AppIcons.clipboardText, 'Spis'),
                  (1, AppIcons.package, 'Składniki'),
                  (2, AppIcons.truck, 'Dostawy i usunięcia'),
                  (3, AppIcons.clock, 'Historia'),
                ],
                selected: tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
              const Spacer(),
              // Przypomnienie, gdy minął okres od ostatniej inwentaryzacji.
              if (open == null && due) const PanelPill('Czas na inwentaryzację', dotColor: Color(0xFFE0A21B)),
            ],
          ),
          actions: [
            if (tab == 0 && open != null && canCount) ...[
              TextButton(
                onPressed: _busy ? null : () => _discard(rid, open),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Anuluj'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _finish(rid, open, items.where((i) => open.line(i.id) == null).length),
                icon: const Glyph(AppIcons.check, size: 18),
                label: const Text('Zakończ inwentaryzację'),
              ),
            ] else if (tab == 0 && open == null && canCount && items.isNotEmpty)
              FilledButton.icon(
                onPressed: _busy ? null : () => _start(rid),
                icon: const Glyph(AppIcons.clipboardText, size: 18),
                label: const Text('Zacznij inwentaryzację'),
              )
            else if (tab == 1 && canEdit) ...[
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => InventoryContainersDialog(restaurantId: rid),
                ),
                icon: const Glyph(AppIcons.scales, size: 18),
                label: const Text('Pojemniki'),
              ),
              FilledButton.icon(
                onPressed: () => _editItem(rid, items),
                icon: const Glyph(AppIcons.plus, size: 18),
                label: const Text('Dodaj składnik'),
              ),
            ] else if (tab == 2 && canCount && items.isNotEmpty) ...[
              OutlinedButton.icon(
                onPressed: () => _addDoc(rid, items, false),
                icon: const Glyph(AppIcons.minusCircle, size: 18),
                label: const Text('Usunięcie'),
              ),
              FilledButton.icon(
                onPressed: () => _addDoc(rid, items, true),
                icon: const Glyph(AppIcons.truck, size: 18),
                label: const Text('Dostawa'),
              ),
            ],
          ],
        ),
        Expanded(
          child: TabContent(
            tab: tab,
            child: error != null
                ? ErrorView(
                    error: error,
                    onRetry: () => ref
                      ..invalidate(inventoryItemsProvider(rid))
                      ..invalidate(inventoryCountsProvider(rid)),
                  )
                : loading
                ? const LoadingView()
                : switch (tab) {
                    0 when open != null => _CountSheet(
                      count: open,
                      items: items,
                      stock: stock,
                      containers: containers,
                      canCount: canCount,
                      onSave: (item, packages, loose, containerId) async {
                        try {
                          await ref
                              .read(repositoryProvider)
                              .setInventoryQuantity(
                                open.id,
                                item.id,
                                packages,
                                loose: loose,
                                containerId: containerId,
                                memberId: _memberId,
                              );
                          ref.invalidate(inventoryCountsProvider(rid));
                          return true;
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                          return false;
                        }
                      },
                    ),
                    0 => _NoCount(
                      hasItems: items.isNotEmpty,
                      due: due,
                      next: next,
                      canCount: canCount,
                      canEdit: canEdit,
                      busy: _busy,
                      onStart: () => _start(rid),
                      onItems: () => setState(() => _tab = 1),
                    ),
                    1 => _ItemsTable(
                      items: items,
                      stock: stock,
                      canEdit: canEdit,
                      onEdit: (item) => _editItem(rid, items, item),
                      onAdd: () => _editItem(rid, items),
                    ),
                    2 => InventoryDocsTab(
                      restaurantId: rid,
                      canAdd: canCount && items.isNotEmpty,
                      canDelete: canEdit,
                      memberId: _memberId,
                      onAdd: (delivery) => _addDoc(rid, items, delivery),
                    ),
                    _ => _History(counts: finished, restaurant: restaurant.name),
                  },
          ),
        ),
      ],
    );
  }
}

/// Spis, gdy żadna inwentaryzacja nie trwa.
class _NoCount extends StatelessWidget {
  const _NoCount({
    required this.hasItems,
    required this.due,
    required this.next,
    required this.canCount,
    required this.canEdit,
    required this.busy,
    required this.onStart,
    required this.onItems,
  });

  final bool hasItems;
  final bool due;
  final DateTime? next;
  final bool canCount;
  final bool canEdit;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onItems;

  @override
  Widget build(BuildContext context) {
    if (!hasItems) {
      return MessageView(
        icon: AppIcons.package,
        title: 'Brak składników',
        message: canEdit
            ? 'Dodaj składniki z opakowaniem, na przykład wódka 0,7 l, mąka worek 25 kg, woda zgrzewka 12 szt. '
                  'Potem zacznij inwentaryzację.'
            : 'Składniki dodaje osoba z uprawnieniem „Edytowanie składników”.',
        actionLabel: canEdit ? 'Przejdź do składników' : null,
        onAction: canEdit ? onItems : null,
      );
    }
    return MessageView(
      icon: AppIcons.clipboardText,
      title: due ? 'Czas na inwentaryzację' : 'Następna inwentaryzacja: ${Fmt.dayLong(next!)}',
      message: canCount
          ? 'Zacznij inwentaryzację i wpisz, ile opakowań każdego składnika jest w lokalu. Każda ilość zapisuje '
                'się od razu, więc spis można robić na kilku komputerach i w Table for employees naraz.'
          : 'Ilości wpisuje osoba z uprawnieniem „Wpisywanie ilości składników”.',
    );
  }
}

/// Wiersz nagłówka tabeli.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.labels, this.trailing = 0, this.flex = _flex});

  final List<(String, TextAlign)> labels;
  final List<int> flex;

  /// Miejsce na przyciski na końcu wiersza.
  final double trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              flex: flex[i],
              child: Text(labels[i].$1, textAlign: labels[i].$2, style: style),
            ),
          if (trailing > 0) SizedBox(width: trailing),
        ],
      ),
    );
  }
}

/// Nagłówek grupy składników z jednej lokalizacji („Chłodnia”).
class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.name, required this.count});

  final String? name;
  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      color: AppColors.surfaceRaised,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          Glyph(AppIcons.mapPin, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(name ?? 'Bez lokalizacji', style: text.labelLarge),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: text.labelLarge?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
          ),
        ],
      ),
    );
  }
}

/// Trwająca inwentaryzacja: pola ilości przy każdym składniku (pogrupowane po lokalizacji), różnica na żywo
/// i na końcu dostawy oraz usunięcia od poprzedniej inwentaryzacji.
class _CountSheet extends StatelessWidget {
  const _CountSheet({
    required this.count,
    required this.items,
    required this.stock,
    required this.containers,
    required this.canCount,
    required this.onSave,
  });

  final InventoryCount count;
  final List<InventoryItem> items;
  final Map<String, InventoryStock> stock;
  final List<InventoryContainer> containers;
  final bool canCount;
  final Future<bool> Function(InventoryItem item, double? packages, double? loose, String? containerId) onSave;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = items.where((i) => count.line(i.id) != null).length;
    final groups = _byLocation(items);
    final showGroups = groups.length > 1 || groups.first.$1 != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Wpisano $done z ${items.length}', style: text.titleSmall?.copyWith(fontFeatures: _tabular)),
              const SizedBox(width: 14),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: items.isEmpty ? 0 : done / items.length),
                    duration: const Duration(milliseconds: 300),
                    curve: AppMotion.easeOut,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      color: AppColors.accent,
                      backgroundColor: AppColors.surfaceRaised,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            canCount
                ? 'Wpisz pełne opakowania, a obok resztę w gramach, mililitrach albo sztukach (np. woda: 11 zgrzewek '
                      'i 9 butelek). Ważysz w pojemniku? Wybierz go przy wadze: panel sam odejmie jego wagę. '
                      'Różnica od stanu „powinno być” liczy się w trakcie pisania. Enter przechodzi dalej.'
                : 'Ilości wpisuje osoba z uprawnieniem „Wpisywanie ilości składników”.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _HeaderRow(
                  flex: _countFlex,
                  labels: [
                    ('Składnik', TextAlign.left),
                    ('Opakowanie', TextAlign.left),
                    ('Pełne opakowania', TextAlign.left),
                    ('Reszta', TextAlign.left),
                    ('Razem', TextAlign.right),
                    ('Powinno być', TextAlign.right),
                    ('Różnica', TextAlign.right),
                  ],
                ),
                for (final (location, group) in groups) ...[
                  if (showGroups) _LocationRow(name: location, count: group.length),
                  for (final item in group) ...[
                    Divider(height: 1, color: AppColors.ring),
                    _CountRow(
                      key: ValueKey(item.id),
                      item: item,
                      line: count.line(item.id),
                      expected: stock[item.id]?.stock,
                      containers: containers,
                      enabled: canCount,
                      onSave: (packages, loose, containerId) => onSave(item, packages, loose, containerId),
                    ),
                  ],
                ],
              ],
            ),
          ),
          if (count.docs.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Dostawy i usunięcia od poprzedniej inwentaryzacji', style: text.titleSmall),
            const SizedBox(height: 8),
            for (final d in count.docs.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InventoryDocTile(doc: d),
              ),
          ],
        ],
      ),
    );
  }
}

/// Wiersz spisu: wpisane wartości trzymane na bieżąco, żeby „Razem” i różnica zmieniały się w trakcie pisania.
class _CountRow extends StatefulWidget {
  const _CountRow({
    super.key,
    required this.item,
    required this.line,
    required this.expected,
    required this.containers,
    required this.enabled,
    required this.onSave,
  });

  final InventoryItem item;
  final InventoryLine? line;

  /// Stan „powinno być” w jednostce składnika. Null: składnik jeszcze nie był liczony.
  final double? expected;
  final List<InventoryContainer> containers;
  final bool enabled;

  /// Zapis pełnych opakowań, reszty (z pojemnikiem: waga z pojemnikiem w g) i pojemnika. Oba null: niepoliczone.
  final Future<bool> Function(double? packages, double? loose, String? containerId) onSave;

  @override
  State<_CountRow> createState() => _CountRowState();
}

class _CountRowState extends State<_CountRow> {
  late double? _packages;
  late double? _loose;
  late String? _containerId;

  @override
  void initState() {
    super.initState();
    _fromLine();
  }

  @override
  void didUpdateWidget(_CountRow old) {
    super.didUpdateWidget(old);
    if (widget.line != old.line) setState(_fromLine);
  }

  void _fromLine() {
    final l = widget.line;
    // Starsze spisy mają tylko liczbę opakowań (także ułamkową).
    _packages = l == null ? null : (l.packages ?? (l.loose == null ? l.quantity : null));
    _loose = l == null ? null : (l.containerId != null ? l.gross : l.loose);
    _containerId = l == null ? (widget.item.weighed ? widget.item.containerId : null) : l.containerId;
  }

  InventoryContainer? get _container => widget.containers.where((c) => c.id == _containerId).firstOrNull;

  /// Razem w jednostce składnika z tego, co wpisano (bez zapisu).
  double? get _total {
    if (_packages == null && _loose == null) return null;
    final tare = _container?.tareG ?? 0;
    final net = _loose == null ? 0.0 : (_loose! - tare).clamp(0, double.infinity).toDouble();
    return (_packages ?? 0) * widget.item.capacity + net / widget.item.unit.portionFactor;
  }

  Future<bool> _save() => widget.onSave(_packages, _loose, _loose == null ? null : _container?.id);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final total = _total;
    final expected = widget.expected;
    final diff = total == null || expected == null ? null : total - expected;
    final box = _container;
    final canBox = item.weighed && widget.containers.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: _countFlex[0],
            child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
          ),
          Expanded(
            flex: _countFlex[1],
            child: Text(item.package, style: muted),
          ),
          Expanded(
            flex: _countFlex[2],
            child: Align(
              alignment: Alignment.centerLeft,
              child: _QuantityField(
                initial: _packages,
                enabled: widget.enabled,
                suffix: packWord(item.packName, _packages),
                onChanged: (v) => setState(() => _packages = v),
                onSave: (v) {
                  _packages = v;
                  return _save();
                },
              ),
            ),
          ),
          Expanded(
            flex: _countFlex[3],
            child: Row(
              children: [
                _QuantityField(
                  initial: _loose,
                  enabled: widget.enabled,
                  suffix: box == null ? item.unit.portion.label : 'g z poj.',
                  onChanged: (v) => setState(() => _loose = v),
                  onSave: (v) {
                    _loose = v;
                    return _save();
                  },
                ),
                if (canBox) ...[
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    enabled: widget.enabled,
                    tooltip: box == null ? 'Ważone bez pojemnika' : 'Ważone w pojemniku ${box.label}',
                    onSelected: (id) {
                      setState(() => _containerId = id.isEmpty ? null : id);
                      if (_loose != null) _save();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: '', child: Text('Bez pojemnika')),
                      for (final c in widget.containers)
                        PopupMenuItem(value: c.id, child: Text('W pojemniku ${c.label}')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Glyph(AppIcons.scales, size: 16, color: box == null ? AppColors.textMuted : AppColors.accent),
                          if (box != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              '−${inventoryGrouped(box.tareG)} g',
                              style: text.labelMedium?.copyWith(color: AppColors.accent, fontFeatures: _tabular),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: _countFlex[4],
            child: Text(
              total == null ? '—' : '${inventoryNumber(total)} ${item.unit.label}',
              textAlign: TextAlign.right,
              style: text.titleSmall?.copyWith(fontFeatures: _tabular),
            ),
          ),
          Expanded(
            flex: _countFlex[5],
            child: Text(
              expected == null ? '—' : '${inventoryNumber(expected)} ${item.unit.label}',
              textAlign: TextAlign.right,
              style: muted,
            ),
          ),
          Expanded(
            flex: _countFlex[6],
            child: Text(
              diff == null ? '—' : _signed(diff, item.unit),
              textAlign: TextAlign.right,
              style: text.titleSmall?.copyWith(
                color: diff == null ? AppColors.textMuted : _diffColor(diff),
                fontFeatures: _tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pole ilości. Zapisuje po Enterze albo po przejściu do innego pola; [onChanged] w trakcie pisania.
class _QuantityField extends StatefulWidget {
  const _QuantityField({
    required this.initial,
    required this.enabled,
    required this.onSave,
    this.onChanged,
    this.suffix = 'op.',
  });

  final double? initial;
  final bool enabled;
  final String suffix;
  final Future<bool> Function(double? quantity) onSave;
  final ValueChanged<double?>? onChanged;

  @override
  State<_QuantityField> createState() => _QuantityFieldState();
}

class _QuantityFieldState extends State<_QuantityField> {
  late final _controller = TextEditingController(text: _format(widget.initial));
  final _focus = FocusNode();
  late double? _saved = widget.initial;
  bool _saving = false;
  bool _justSaved = false;
  bool _invalid = false;

  static String _format(double? v) => v == null ? '' : inventoryNumber(v);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_QuantityField old) {
    super.didUpdateWidget(old);
    // Ilość wpisana na innym komputerze: pokazujemy ją, jeśli nikt nie pisze w tym polu.
    if (widget.initial != old.initial && !_focus.hasFocus && !_saving && widget.initial != _saved) {
      _saved = widget.initial;
      _controller.text = _format(widget.initial);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final raw = _controller.text.trim();
    final value = raw.isEmpty ? null : parseInventoryNumber(raw);
    if (raw.isNotEmpty && (value == null || value < 0)) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    if (value == _saved) return;
    setState(() => _saving = true);
    final ok = await widget.onSave(value);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _saved = value;
        _justSaved = true;
        _controller.text = _format(value);
      } else {
        _controller.text = _format(_saved);
        widget.onChanged?.call(_saved);
      }
    });
    if (ok) {
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _justSaved = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        textAlign: TextAlign.right,
        textInputAction: TextInputAction.next,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: const TextStyle(fontFeatures: _tabular, fontSize: 15),
        onChanged: (raw) {
          final value = raw.trim().isEmpty ? null : parseInventoryNumber(raw);
          if (raw.trim().isEmpty || value != null) widget.onChanged?.call(value);
        },
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        decoration: InputDecoration(
          isDense: true,
          hintText: '—',
          errorText: _invalid ? 'Wpisz liczbę' : null,
          suffixText: widget.suffix,
          prefixIcon: SizedBox(
            width: 32,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _saving
                    ? const SizedBox(
                        key: ValueKey('saving'),
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _justSaved
                    ? Glyph(AppIcons.check, key: const ValueKey('saved'), size: 16, color: AppColors.accent)
                    : const SizedBox(key: ValueKey('idle')),
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ),
    );
  }
}

/// Składniki: ilość z ostatniej inwentaryzacji, ruchy od niej (sprzedaż z receptur, dostawy, usunięcia) i stan teraz.
class _ItemsTable extends StatelessWidget {
  const _ItemsTable({
    required this.items,
    required this.stock,
    required this.canEdit,
    required this.onEdit,
    required this.onAdd,
  });

  final List<InventoryItem> items;

  /// Stan teraz według numeru składnika.
  final Map<String, InventoryStock> stock;
  final bool canEdit;
  final ValueChanged<InventoryItem> onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (items.isEmpty) {
      return MessageView(
        icon: AppIcons.package,
        title: 'Brak składników',
        message: canEdit
            ? 'Dodaj składnik: nazwę, jednostkę, opakowanie i lokalizację, na przykład wódka 0,7 l (Bar), '
                  'mąka worek 25 kg (Magazyn suchy).'
            : 'Składniki dodaje osoba z uprawnieniem „Edytowanie składników”.',
        actionLabel: canEdit ? 'Dodaj składnik' : null,
        onAction: canEdit ? onAdd : null,
      );
    }
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final small = text.bodySmall?.copyWith(fontFeatures: _tabular);
    final groups = _byLocation(items);
    final showGroups = groups.length > 1 || groups.first.$1 != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeaderRow(
              labels: const [
                ('Składnik', TextAlign.left),
                ('Opakowanie', TextAlign.left),
                ('Inwentaryzacja', TextAlign.left),
                ('Od inwentaryzacji', TextAlign.right),
                ('Stan teraz', TextAlign.right),
              ],
              trailing: canEdit ? 56 : 0,
            ),
            for (final (location, group) in groups) ...[
              if (showGroups) _LocationRow(name: location, count: group.length),
              for (final item in group) ...[
                Divider(height: 1, color: AppColors.ring),
                InkWell(
                  onTap: canEdit ? () => onEdit(item) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          flex: _flex[0],
                          child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                        ),
                        Expanded(
                          flex: _flex[1],
                          child: Text(item.package, style: muted),
                        ),
                        Expanded(
                          flex: _flex[2],
                          child: Text(switch (stock[item.id]) {
                            InventoryStock(counted: final c?, countedAt: final at?) =>
                              '${inventoryNumber(c)} ${item.unit.label} · ${Fmt.dayShort(at)}',
                            _ => 'jeszcze nie liczono',
                          }, style: muted),
                        ),
                        Expanded(
                          flex: _flex[3],
                          child: switch (stock[item.id]) {
                            final s? when s.used > 0.0005 || s.delivered > 0.0005 || s.removed > 0.0005 => Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (s.used > 0.0005) Text('sprzedaż ${_signed(-s.used, item.unit)}', style: small),
                                if (s.delivered > 0.0005)
                                  Text(
                                    'dostawy ${_signed(s.delivered, item.unit)}',
                                    style: small?.copyWith(color: AppColors.accent),
                                  ),
                                if (s.removed > 0.0005)
                                  Text(
                                    'usunięte ${_signed(-s.removed, item.unit)}',
                                    style: small?.copyWith(color: AppColors.error),
                                  ),
                              ],
                            ),
                            _ => Text('—', textAlign: TextAlign.right, style: muted),
                          },
                        ),
                        Expanded(
                          flex: _flex[4],
                          child: switch (stock[item.id]?.stock) {
                            final v? => Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${inventoryNumber(v)} ${item.unit.label}',
                                  style: text.titleSmall?.copyWith(
                                    fontFeatures: _tabular,
                                    color: v < 0 ? AppColors.error : null,
                                  ),
                                ),
                                Text(
                                  packCount((v / item.capacity * 10).round() / 10, item.packName),
                                  style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                                ),
                              ],
                            ),
                            _ => Text('—', textAlign: TextAlign.right, style: text.titleSmall),
                          },
                        ),
                        if (canEdit)
                          SizedBox(
                            width: 56,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: 'Zmień',
                                  onPressed: () => onEdit(item),
                                  icon: Glyph(AppIcons.pencil, size: 16, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
            if (canEdit) ...[
              Divider(height: 1, color: AppColors.ring),
              InkWell(
                onTap: onAdd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Glyph(AppIcons.plus, size: 18, color: AppColors.accent),
                      const SizedBox(width: 10),
                      Text('Dodaj składnik', style: text.titleSmall?.copyWith(color: AppColors.accent)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Zakończone inwentaryzacje. Kliknięcie pokazuje ilości, ruchy, różnice, dostawy i usunięcia z okresu.
class _History extends StatelessWidget {
  const _History({required this.counts, required this.restaurant});

  /// Od najnowszej.
  final List<InventoryCount> counts;
  final String restaurant;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (counts.isEmpty) {
      return const MessageView(
        icon: AppIcons.clock,
        title: 'Brak historii',
        message: 'Tu pojawią się zakończone inwentaryzacje.',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < counts.length; i++) ...[
              if (i > 0) Divider(height: 1, color: AppColors.ring),
              InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _CountDialog(count: counts[i], restaurant: restaurant),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      const IconBadge(AppIcons.clipboardText, color: TileColors.blue),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${Fmt.capitalize(Fmt.dayLong(counts[i].finishedAt!))}, ${_hm(counts[i].finishedAt!)}',
                              style: text.titleSmall,
                            ),
                            Text(
                              [
                                '${counts[i].lines.length} ${counts[i].lines.length == 1 ? 'składnik' : 'składników'}',
                                if (counts[i].docs.any((d) => d.delivery))
                                  'dostawy: ${counts[i].docs.where((d) => d.delivery).length}',
                                if (counts[i].docs.any((d) => !d.delivery))
                                  'usunięcia: ${counts[i].docs.where((d) => !d.delivery).length}',
                                if ((counts[i].finishedBy ?? counts[i].startedBy) != null)
                                  'spisał(a) ${counts[i].finishedBy ?? counts[i].startedBy}',
                              ].join(' · '),
                              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Glyph(AppIcons.caretRight, size: 14, color: AppColors.textDisabled),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountDialog extends StatelessWidget {
  const _CountDialog({required this.count, required this.restaurant});

  final InventoryCount count;
  final String restaurant;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final head = text.labelMedium?.copyWith(color: AppColors.textMuted);
    Widget cell(String value, {int flex = 2, TextAlign align = TextAlign.right, TextStyle? style}) => Expanded(
      flex: flex,
      child: Text(
        value,
        textAlign: align,
        style: style ?? text.bodyMedium?.copyWith(fontFeatures: _tabular),
      ),
    );
    String qty(double? v, InventoryUnit unit) => v == null ? '—' : '${inventoryNumber(v)} ${unit.label}';
    return AlertDialog(
      title: Text('Inwentaryzacja ${Fmt.dayShort(count.finishedAt!)}'),
      content: SizedBox(
        width: 1000,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [
                'Od ${_hm(count.startedAt)} do ${_hm(count.finishedAt!)}',
                if (count.finishedBy != null) 'zakończył(a) ${count.finishedBy}',
                if (count.periodFrom != null) 'okres od ${docWhen(count.periodFrom!)}',
              ].join(' · '),
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                cell('Składnik', flex: 4, align: TextAlign.left, style: head),
                cell('Policzono', style: head),
                cell('Poprzednio', style: head),
                cell('Sprzedaż', style: head),
                cell('Dostawy', style: head),
                cell('Usunięte', style: head),
                cell('Powinno być', style: head),
                cell('Różnica', style: head),
              ],
            ),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final l in count.lines)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: AppColors.ring)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.name, style: text.titleSmall),
                                  Text(
                                    [
                                      ?l.location,
                                      if ((l.packages ?? 0) > 0) packCount(l.packages!, l.packName),
                                      if (l.container != null && l.gross != null)
                                        '${inventoryGrouped(l.gross!)} g w pojemniku ${l.container} '
                                            '(−${inventoryGrouped(l.tare ?? 0)} g)'
                                      else if ((l.loose ?? 0) > 0)
                                        '${inventoryGrouped(l.loose!)} ${l.unit.portion.label}',
                                    ].join(' · '),
                                    style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                                  ),
                                ],
                              ),
                            ),
                            cell(l.totalText),
                            cell(qty(l.previous, l.unit), style: muted),
                            cell(
                              l.used == null || l.used!.abs() < 0.0005 ? '—' : _signed(-l.used!, l.unit),
                              style: muted,
                            ),
                            cell(
                              l.delivered == null || l.delivered!.abs() < 0.0005 ? '—' : _signed(l.delivered!, l.unit),
                              style: muted,
                            ),
                            cell(
                              l.removed == null || l.removed!.abs() < 0.0005 ? '—' : _signed(-l.removed!, l.unit),
                              style: muted,
                            ),
                            cell(qty(l.expected, l.unit), style: muted),
                            cell(
                              l.difference == null ? '—' : _signed(l.difference!, l.unit),
                              style: text.bodyMedium?.copyWith(
                                color: l.difference == null ? AppColors.textMuted : _diffColor(l.difference!),
                                fontFeatures: _tabular,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      'Powinno być: poprzednia inwentaryzacja minus sprzedaż (receptury w Menu), plus dostawy, minus '
                      'usunięcia. Różnica na minusie to braki.',
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    Text('Dostawy i usunięcia w okresie', style: text.titleSmall),
                    const SizedBox(height: 8),
                    if (count.docs.isEmpty)
                      Text('Brak.', style: text.bodyMedium?.copyWith(color: AppColors.textMuted))
                    else
                      for (final d in count.docs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InventoryDocTile(doc: d),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => saveInventoryPdf(context, count, restaurant: restaurant),
          icon: const Glyph(AppIcons.fileArrowDown, size: 16),
          label: const Text('Zapisz PDF'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zamknij')),
      ],
    );
  }
}

/// Dodanie albo zmiana składnika: nazwa, jednostka, opakowanie (nazwa i pojemność), lokalizacja i zwykły pojemnik
/// do ważenia. Przy zmianie także usuwanie. Zwraca numer zapisanego (albo usuniętego) składnika, null po anulowaniu.
/// Używa go też okno dania w Menu („Nowy składnik”).
class InventoryItemDialog extends ConsumerStatefulWidget {
  const InventoryItemDialog({
    super.key,
    required this.restaurantId,
    this.item,
    this.canDelete = true,
    this.locations = const [],
    this.details = true,
  });

  final String restaurantId;
  final InventoryItem? item;
  final bool canDelete;

  /// Lokalizacje innych składników (podpowiedzi).
  final List<String> locations;

  /// Pola inwentaryzacji: opakowanie, lokalizacja, pojemnik.
  final bool details;

  @override
  ConsumerState<InventoryItemDialog> createState() => _InventoryItemDialogState();
}

class _InventoryItemDialogState extends ConsumerState<InventoryItemDialog> {
  static const _packs = ['zgrzewka', 'worek', 'puszka', 'butelka', 'karton', 'skrzynka', 'opakowanie'];

  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _capacity = TextEditingController(text: widget.item == null ? '' : inventoryNumber(widget.item!.capacity));
  late final _pack = TextEditingController(text: widget.item?.packName ?? '');
  late final _location = TextEditingController(text: widget.item?.location ?? '');
  late InventoryUnit _unit = widget.item?.unit ?? InventoryUnit.l;
  late String? _containerId = widget.item?.containerId;
  bool _busy = false;
  String? _nameError;
  String? _capacityError;

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    _pack.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final capacity = parseInventoryNumber(_capacity.text);
    setState(() {
      _nameError = name.isEmpty ? 'Wpisz nazwę składnika.' : null;
      _capacityError = capacity == null || capacity <= 0
          ? (_unit == InventoryUnit.szt ? 'Wpisz, ile sztuk jest w opakowaniu.' : 'Wpisz pojemność opakowania.')
          : null;
    });
    if (_nameError != null || _capacityError != null) return;
    final weighed = _unit == InventoryUnit.g || _unit == InventoryUnit.kg;
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(repositoryProvider)
          .saveInventoryItem(
            widget.restaurantId,
            id: widget.item?.id,
            name: name,
            unit: _unit,
            capacity: capacity!,
            details: widget.details,
            packName: _pack.text,
            location: _location.text,
            containerId: weighed ? _containerId : null,
          );
      if (!mounted) return;
      Navigator.pop(context, id);
      showMessage(context, widget.item == null ? 'Dodano: $name.' : 'Zapisano: $name.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final item = widget.item!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Usunąć „${item.name}”?'),
        content: const Text('Składnik zniknie z listy i z kolejnych inwentaryzacji. W historii zostanie.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Wróć')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).deleteInventoryItem(item.id);
      if (!mounted) return;
      Navigator.pop(context, item.id);
      showMessage(context, 'Usunięto: ${item.name}.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pieces = _unit == InventoryUnit.szt;
    final weighed = _unit == InventoryUnit.g || _unit == InventoryUnit.kg;
    final containers = widget.details
        ? ref.watch(inventoryContainersProvider(widget.restaurantId)).value ?? const <InventoryContainer>[]
        : const <InventoryContainer>[];
    final packLabel = _pack.text.trim().isEmpty ? 'opakowanie' : _pack.text.trim();
    return AlertDialog(
      title: Text(widget.item == null ? 'Nowy składnik' : 'Składnik'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: widget.item == null,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Nazwa',
                  hintText: 'Na przykład: Wódka Wyborowa',
                  errorText: _nameError,
                ),
              ),
              const SizedBox(height: 8),
              Text('Jednostka', style: text.titleSmall),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedTabs<InventoryUnit>(
                  options: [for (final u in InventoryUnit.values) (u, u.label)],
                  selected: _unit,
                  onChanged: (u) => setState(() => _unit = u),
                ),
              ),
              if (widget.details) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _pack,
                  maxLength: 30,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Opakowanie',
                    hintText: 'Na przykład: zgrzewka, worek, puszka',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in _packs)
                      ChoiceChip(
                        label: Text(p),
                        selected: _pack.text.trim() == p,
                        onSelected: (_) => setState(() => _pack.text = p),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _capacity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: pieces ? 'Sztuk w: $packLabel' : 'Ile ma: $packLabel',
                  hintText: pieces ? 'Na przykład: 1 albo 12 (zgrzewka)' : 'Na przykład: 0,7 albo 25',
                  suffixText: _unit.label,
                  errorText: _capacityError,
                ),
              ),
              if (widget.details) ...[
                const SizedBox(height: 16),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _location.text),
                  optionsBuilder: (value) {
                    final q = value.text.trim().toLowerCase();
                    return widget.locations.where((l) => q.isEmpty || l.toLowerCase().contains(q));
                  },
                  onSelected: (v) => _location.text = v,
                  fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
                    controller: controller,
                    focusNode: focus,
                    maxLength: 60,
                    onChanged: (v) => _location.text = v,
                    decoration: const InputDecoration(
                      labelText: 'Lokalizacja (opcjonalnie)',
                      hintText: 'Na przykład: Chłodnia, Magazyn suchy, Bar',
                      counterText: '',
                    ),
                  ),
                ),
                if (weighed && containers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    initialValue: containers.any((c) => c.id == _containerId) ? _containerId : null,
                    decoration: const InputDecoration(labelText: 'Zwykle ważony w pojemniku'),
                    icon: const Glyph(AppIcons.caretDown, size: 16),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Bez pojemnika')),
                      for (final c in containers) DropdownMenuItem<String?>(value: c.id, child: Text(c.label)),
                    ],
                    onChanged: (v) => setState(() => _containerId = v),
                  ),
                ],
              ],
              const SizedBox(height: 8),
              Text(
                'W inwentaryzacji wpisuje się pełne opakowania i resztę, a panel liczy razem, np. 11 zgrzewek po '
                '12 szt. i 9 butelek = 141 szt.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.item != null && widget.canDelete)
          TextButton(
            onPressed: _busy ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Usuń'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(widget.item == null ? 'Dodaj' : 'Zapisz')),
      ],
    );
  }
}
