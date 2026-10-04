import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';

/// Kolumny tabel: składnik, opakowanie, ilość, razem, poprzednio / akcje.
const _flex = [5, 2, 3, 2, 2];

/// Kolumny spisu: składnik, opakowanie, pełne opakowania, reszta, razem, poprzednio.
const _countFlex = [5, 2, 3, 3, 2, 2];

/// Inwentaryzacja: zakładki Spis (trwająca inwentaryzacja), Składniki (lista ze stanem z ostatniego spisu)
/// i Historia. Uprawnienia: `inventory_edit` (składniki i okres) i `inventory_count` (wpisywanie ilości).
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
      if (mounted) setState(() => _tab = 1);
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

  Future<void> _editItem(String restaurantId, [InventoryItem? item]) async {
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => InventoryItemDialog(restaurantId: restaurantId, item: item),
    );
    if (saved == null) return;
    ref
      ..invalidate(inventoryItemsProvider(restaurantId))
      ..invalidate(inventoryStockProvider(restaurantId));
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
    final stock = {for (final s in ref.watch(inventoryStockProvider(rid)).value ?? const <InventoryStock>[]) s.itemId: s};
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
                  (2, AppIcons.clock, 'Historia'),
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
                onPressed: _busy
                    ? null
                    : () => _finish(rid, open, items.where((i) => open.line(i.id) == null).length),
                icon: const Glyph(AppIcons.check, size: 18),
                label: const Text('Zakończ inwentaryzację'),
              ),
            ] else if (tab == 0 && open == null && canCount && items.isNotEmpty)
              FilledButton.icon(
                onPressed: _busy ? null : () => _start(rid),
                icon: const Glyph(AppIcons.clipboardText, size: 18),
                label: const Text('Zacznij inwentaryzację'),
              )
            else if (tab == 1 && canEdit)
              FilledButton.icon(
                onPressed: () => _editItem(rid),
                icon: const Glyph(AppIcons.plus, size: 18),
                label: const Text('Dodaj składnik'),
              ),
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
                    previous: last,
                    canCount: canCount,
                    onSave: (item, packages, loose) async {
                      try {
                        await ref.read(repositoryProvider).setInventoryQuantity(
                          open.id,
                          item.id,
                          packages,
                          loose: loose,
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
                    onEdit: (item) => _editItem(rid, item),
                    onAdd: () => _editItem(rid),
                  ),
                  _ => _History(counts: finished),
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
            ? 'Dodaj składniki z pojemnością opakowania, na przykład wódka 0,7 l albo mąka 25 kg. Potem zacznij inwentaryzację.'
            : 'Składniki dodaje osoba z uprawnieniem „Edytowanie składników”.',
        actionLabel: canEdit ? 'Przejdź do składników' : null,
        onAction: canEdit ? onItems : null,
      );
    }
    return MessageView(
      icon: AppIcons.clipboardText,
      title: due ? 'Czas na inwentaryzację' : 'Następna inwentaryzacja: ${Fmt.dayLong(next!)}',
      message: canCount
          ? 'Zacznij inwentaryzację i wpisz, ile opakowań każdego składnika jest w lokalu. '
                'Każda ilość zapisuje się od razu, więc spis można robić na kilku komputerach naraz.'
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

/// Trwająca inwentaryzacja: pole ilości przy każdym składniku.
class _CountSheet extends StatelessWidget {
  const _CountSheet({
    required this.count,
    required this.items,
    required this.previous,
    required this.canCount,
    required this.onSave,
  });

  final InventoryCount count;
  final List<InventoryItem> items;
  final InventoryCount? previous;
  final bool canCount;
  final Future<bool> Function(InventoryItem item, double? packages, double? loose) onSave;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = items.where((i) => count.line(i.id) != null).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Wpisano $done z ${items.length}',
                style: text.titleSmall?.copyWith(fontFeatures: _tabular),
              ),
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
                ? 'Wpisz pełne opakowania, a obok resztę w gramach, mililitrach albo sztukach '
                      '(np. mąka 50 kg: 1 op. i 2500 g = 52 500 g). Enter przechodzi dalej. '
                      'Puste pola: składnik nie jest jeszcze policzony.'
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
                    ('Opakowania', TextAlign.left),
                    ('Reszta', TextAlign.left),
                    ('Razem', TextAlign.right),
                    ('Poprzednio', TextAlign.right),
                  ],
                ),
                for (final item in items) ...[
                  Divider(height: 1, color: AppColors.ring),
                  _CountRow(
                    key: ValueKey(item.id),
                    item: item,
                    line: count.line(item.id),
                    previous: previous?.line(item.id),
                    enabled: canCount,
                    onSave: (packages, loose) => onSave(item, packages, loose),
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

class _CountRow extends StatelessWidget {
  const _CountRow({
    super.key,
    required this.item,
    required this.line,
    required this.previous,
    required this.enabled,
    required this.onSave,
  });

  final InventoryItem item;
  final InventoryLine? line;
  final InventoryLine? previous;
  final bool enabled;

  /// Zapis pełnych opakowań i reszty (w gramach, mililitrach albo sztukach). Oba null: niepoliczone.
  final Future<bool> Function(double? packages, double? loose) onSave;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final l = line;
    // Starsze spisy mają tylko liczbę opakowań (także ułamkową).
    final packages = l == null ? null : (l.packages ?? (l.loose == null ? l.quantity : null));
    final loose = l?.loose;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: _countFlex[0],
            child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
          ),
          Expanded(flex: _countFlex[1], child: Text(item.package, style: muted)),
          Expanded(
            flex: _countFlex[2],
            child: Align(
              alignment: Alignment.centerLeft,
              child: _QuantityField(
                initial: packages,
                enabled: enabled,
                suffix: 'op.',
                onSave: (v) => onSave(v, loose),
              ),
            ),
          ),
          Expanded(
            flex: _countFlex[3],
            child: Align(
              alignment: Alignment.centerLeft,
              child: _QuantityField(
                initial: loose,
                enabled: enabled,
                suffix: item.unit.portion.label,
                onSave: (v) => onSave(packages, v),
              ),
            ),
          ),
          Expanded(
            flex: _countFlex[4],
            child: Text(
              l == null ? '—' : l.portionTotalText,
              textAlign: TextAlign.right,
              style: text.titleSmall?.copyWith(fontFeatures: _tabular),
            ),
          ),
          Expanded(
            flex: _countFlex[5],
            child: Text(
              previous == null ? '—' : previous!.portionTotalText,
              textAlign: TextAlign.right,
              style: muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pole ilości. Zapisuje po Enterze albo po przejściu do innego pola.
class _QuantityField extends StatefulWidget {
  const _QuantityField({required this.initial, required this.enabled, required this.onSave, this.suffix = 'op.'});

  final double? initial;
  final bool enabled;
  final String suffix;
  final Future<bool> Function(double? quantity) onSave;

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
    if (widget.initial != old.initial && !_focus.hasFocus && !_saving) {
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

/// Składniki: ilość z ostatniej inwentaryzacji, sprzedaż od niej (z receptur dań) i stan teraz.
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
            ? 'Dodaj składnik: nazwę, jednostkę i pojemność opakowania, na przykład wódka 0,7 l, mąka 25 kg, cytryny 1 szt.'
            : 'Składniki dodaje osoba z uprawnieniem „Edytowanie składników”.',
        actionLabel: canEdit ? 'Dodaj składnik' : null,
        onAction: canEdit ? onAdd : null,
      );
    }
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
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
                ('Sprzedaż od niej', TextAlign.right),
                ('Stan teraz', TextAlign.right),
              ],
              trailing: canEdit ? 56 : 0,
            ),
            for (final item in items) ...[
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
                      Expanded(flex: _flex[1], child: Text(item.package, style: muted)),
                      Expanded(
                        flex: _flex[2],
                        child: Text(
                          switch (stock[item.id]) {
                            InventoryStock(counted: final c?, countedAt: final at?) =>
                              '${inventoryNumber(c)} ${item.unit.label} · ${Fmt.dayShort(at)}',
                            _ => 'jeszcze nie liczono',
                          },
                          style: muted,
                        ),
                      ),
                      Expanded(
                        flex: _flex[3],
                        child: Text(
                          switch (stock[item.id]?.used) {
                            final u? when u > 0.0005 => '−${inventoryNumber(u)} ${item.unit.label}',
                            _ => '—',
                          },
                          textAlign: TextAlign.right,
                          style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                        ),
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
                                '${inventoryNumber((v / item.capacity * 10).round() / 10)} op.',
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

/// Zakończone inwentaryzacje. Kliknięcie pokazuje ilości i zmianę od poprzedniej.
class _History extends StatelessWidget {
  const _History({required this.counts});

  /// Od najnowszej.
  final List<InventoryCount> counts;

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
                  builder: (_) => _CountDialog(
                    count: counts[i],
                    previous: i + 1 < counts.length ? counts[i + 1] : null,
                  ),
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
  const _CountDialog({required this.count, required this.previous});

  final InventoryCount count;
  final InventoryCount? previous;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    Widget cell(String value, {int flex = 2, TextAlign align = TextAlign.right, TextStyle? style}) => Expanded(
      flex: flex,
      child: Text(value, textAlign: align, style: style ?? text.bodyMedium?.copyWith(fontFeatures: _tabular)),
    );
    return AlertDialog(
      title: Text('Inwentaryzacja ${Fmt.dayShort(count.finishedAt!)}'),
      content: SizedBox(
        width: 780,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [
                'Od ${_hm(count.startedAt)} do ${_hm(count.finishedAt!)}',
                if (count.finishedBy != null) 'zakończył(a) ${count.finishedBy}',
              ].join(' · '),
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                cell('Składnik', flex: 4, align: TextAlign.left, style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
                cell('Ilość', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
                cell('Razem', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
                cell('Sprzedaż', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
                cell('Wg sprzedaży', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
                cell('Różnica', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final l in count.lines)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.ring))),
                        child: Row(
                          children: [
                            cell(l.name, flex: 4, align: TextAlign.left, style: text.titleSmall),
                            cell('${inventoryNumber(l.quantity)} op.', style: muted),
                            cell(l.totalText),
                            cell(
                              switch (l.used) {
                                final u? when u > 0.0005 => '−${inventoryNumber(u)} ${l.unit.label}',
                                _ => '—',
                              },
                              style: muted,
                            ),
                            cell(
                              l.expected == null ? '—' : '${inventoryNumber(l.expected!)} ${l.unit.label}',
                              style: muted,
                            ),
                            _Difference(line: l),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Wg sprzedaży: poprzednia inwentaryzacja minus składniki z wysłanych dań (receptury w Menu). '
              'Różnica na minusie to braki, na plusie na przykład dostawa.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zamknij')),
      ],
    );
  }
}

/// Różnica między policzonym a wynikającym ze sprzedaży, w jednostce składnika.
class _Difference extends StatelessWidget {
  const _Difference({required this.line});

  final InventoryLine line;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final diff = line.difference;
    if (diff == null) {
      return Expanded(
        flex: 2,
        child: Text('—', textAlign: TextAlign.right, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
      );
    }
    final color = diff.abs() < 0.0005 ? AppColors.textMuted : (diff > 0 ? AppColors.accent : AppColors.error);
    final sign = diff > 0.0005 ? '+' : (diff < -0.0005 ? '−' : '');
    return Expanded(
      flex: 2,
      child: Text(
        '$sign${inventoryNumber(diff.abs())} ${line.unit.label}',
        textAlign: TextAlign.right,
        style: text.bodyMedium?.copyWith(color: color, fontFeatures: _tabular),
      ),
    );
  }
}

/// Dodanie albo zmiana składnika: nazwa, jednostka, pojemność opakowania. Przy zmianie także usuwanie.
/// Zwraca numer zapisanego (albo usuniętego) składnika, null po anulowaniu. Używa go też okno dania w Menu.
class InventoryItemDialog extends ConsumerStatefulWidget {
  const InventoryItemDialog({super.key, required this.restaurantId, this.item, this.canDelete = true});

  final String restaurantId;
  final InventoryItem? item;
  final bool canDelete;

  @override
  ConsumerState<InventoryItemDialog> createState() => _InventoryItemDialogState();
}

class _InventoryItemDialogState extends ConsumerState<InventoryItemDialog> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _capacity = TextEditingController(
    text: widget.item == null ? '' : inventoryNumber(widget.item!.capacity),
  );
  late InventoryUnit _unit = widget.item?.unit ?? InventoryUnit.l;
  bool _busy = false;
  String? _nameError;
  String? _capacityError;

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
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
    setState(() => _busy = true);
    try {
      final id = await ref.read(repositoryProvider).saveInventoryItem(
        widget.restaurantId,
        id: widget.item?.id,
        name: name,
        unit: _unit,
        capacity: capacity!,
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
    return AlertDialog(
      title: Text(widget.item == null ? 'Nowy składnik' : 'Składnik'),
      content: SizedBox(
        width: 460,
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
            const SizedBox(height: 16),
            TextField(
              controller: _capacity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: pieces ? 'Sztuk w opakowaniu' : 'Pojemność opakowania',
                hintText: pieces ? 'Na przykład: 1 albo 24 (zgrzewka)' : 'Na przykład: 0,7',
                suffixText: _unit.label,
                errorText: _capacityError,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'W inwentaryzacji wpisuje się liczbę opakowań, a panel liczy razem, np. 2,5 × 0,7 l = 1,75 l.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
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
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(widget.item == null ? 'Dodaj' : 'Zapisz'),
        ),
      ],
    );
  }
}
