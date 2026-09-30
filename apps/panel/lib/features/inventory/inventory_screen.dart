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
      if (mounted) showMessage(context, errorText(e));
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
      ref.invalidate(inventoryCountsProvider(restaurantId));
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
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ItemDialog(restaurantId: restaurantId, item: item),
    );
    if (saved == true) ref.invalidate(inventoryItemsProvider(restaurantId));
  }

  Future<void> _setPeriod(String restaurantId, String period) => _run(() async {
    await ref.read(repositoryProvider).setInventoryPeriod(restaurantId, period);
    ref.invalidate(profileProvider(restaurantId));
  }, 'Inwentaryzacja: ${inventoryPeriodLabel(period).toLowerCase()}.');

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final rid = restaurant.id;
    final permissions = ref.watch(memberPermissionsProvider);
    final canEdit = permissions.contains('inventory_edit');
    final canCount = permissions.contains('inventory_count');

    final itemsAsync = ref.watch(inventoryItemsProvider(rid));
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

    final subtitle = open != null
        ? 'Inwentaryzacja trwa od ${Fmt.dayShort(open.startedAt)}, ${_hm(open.startedAt)}'
              '${open.startedBy == null ? '' : ' · zaczął(a) ${open.startedBy}'}'
        : last == null
        ? 'Jeszcze nie było inwentaryzacji · ${inventoryPeriodLabel(period).toLowerCase()}'
        : 'Ostatnia ${Fmt.dayShort(last.finishedAt!)} · następna ${Fmt.dayShort(next!)}'
              '${due ? ' · czas na inwentaryzację' : ''}';

    final loading = (itemsAsync.isLoading && !itemsAsync.hasValue) || (countsAsync.isLoading && !countsAsync.hasValue);
    final error = itemsAsync.error ?? countsAsync.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Inwentaryzacja',
          subtitle: subtitle,
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
              _PeriodPicker(
                period: period,
                onChanged: canEdit && !_busy ? (p) => _setPeriod(rid, p) : null,
              ),
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
                    onSave: (item, quantity) async {
                      try {
                        await ref.read(repositoryProvider).setInventoryQuantity(
                          open.id,
                          item.id,
                          quantity,
                          memberId: _memberId,
                        );
                        ref.invalidate(inventoryCountsProvider(rid));
                        return true;
                      } catch (e) {
                        if (context.mounted) showMessage(context, errorText(e));
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
                    last: last,
                    canEdit: canEdit,
                    onEdit: (item) => _editItem(rid, item),
                    onAdd: () => _editItem(rid),
                  ),
                  _ => _History(counts: finished),
                },
        ),
      ],
    );
  }
}

/// „Co tydzień” z listą okresów. Bez uprawnienia tylko napis.
class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.period, required this.onChanged});

  final String period;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pill = Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(AppIcons.calendarDots, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text('Inwentaryzacja: ', style: text.labelLarge?.copyWith(color: AppColors.textMuted)),
          Text(inventoryPeriodLabel(period).toLowerCase(), style: text.labelLarge),
          if (onChanged != null) ...[
            const SizedBox(width: 6),
            Glyph(AppIcons.caretDown, size: 14, color: AppColors.textMuted),
          ],
        ],
      ),
    );
    if (onChanged == null) return pill;
    return PopupMenuButton<String>(
      tooltip: 'Co ile robicie inwentaryzację',
      onSelected: (p) {
        if (p != period) onChanged!(p);
      },
      itemBuilder: (_) => [
        for (final (value, label) in inventoryPeriods)
          CheckedPopupMenuItem(value: value, checked: value == period, child: Text(label)),
      ],
      child: pill,
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
  const _HeaderRow({required this.labels, this.trailing = 0});

  final List<(String, TextAlign)> labels;

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
              flex: _flex[i],
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
  final Future<bool> Function(InventoryItem item, double? quantity) onSave;

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
                ? 'Wpisz liczbę opakowań, także częściową (np. 2,5). Enter przechodzi do następnego składnika. '
                      'Puste pole: składnik nie jest jeszcze policzony.'
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
                  labels: [
                    ('Składnik', TextAlign.left),
                    ('Opakowanie', TextAlign.left),
                    ('Ilość opakowań', TextAlign.left),
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
                    onSave: (q) => onSave(item, q),
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
  final Future<bool> Function(double? quantity) onSave;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: _flex[0],
            child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
          ),
          Expanded(flex: _flex[1], child: Text(item.package, style: muted)),
          Expanded(
            flex: _flex[2],
            child: Align(
              alignment: Alignment.centerLeft,
              child: _QuantityField(initial: line?.quantity, enabled: enabled, onSave: onSave),
            ),
          ),
          Expanded(
            flex: _flex[3],
            child: Text(
              line == null ? '—' : line!.totalText,
              textAlign: TextAlign.right,
              style: text.titleSmall?.copyWith(fontFeatures: _tabular),
            ),
          ),
          Expanded(
            flex: _flex[4],
            child: Text(
              previous == null ? '—' : '${inventoryNumber(previous!.quantity)} op.',
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
  const _QuantityField({required this.initial, required this.enabled, required this.onSave});

  final double? initial;
  final bool enabled;
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
          suffixText: 'op.',
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

/// Składniki ze stanem z ostatniej zakończonej inwentaryzacji.
class _ItemsTable extends StatelessWidget {
  const _ItemsTable({
    required this.items,
    required this.last,
    required this.canEdit,
    required this.onEdit,
    required this.onAdd,
  });

  final List<InventoryItem> items;
  final InventoryCount? last;
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
              labels: [
                ('Składnik', TextAlign.left),
                ('Opakowanie', TextAlign.left),
                (last == null ? 'Stan' : 'Stan z ${Fmt.dayShort(last!.finishedAt!)}', TextAlign.left),
                ('Razem', TextAlign.right),
              ],
              trailing: canEdit ? 88 : 0,
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
                          switch (last?.line(item.id)) {
                            null => '—',
                            final l => '${inventoryNumber(l.quantity)} op.',
                          },
                          style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                        ),
                      ),
                      Expanded(
                        flex: _flex[3],
                        child: Text(
                          last?.line(item.id)?.totalText ?? '—',
                          textAlign: TextAlign.right,
                          style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                        ),
                      ),
                      if (canEdit)
                        SizedBox(
                          width: 88,
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
        width: 640,
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
                cell('Zmiana', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
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
                            _Change(line: l, previous: previous?.line(l.itemId)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
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

/// Zmiana od poprzedniej inwentaryzacji w jednostce składnika.
class _Change extends StatelessWidget {
  const _Change({required this.line, required this.previous});

  final InventoryLine line;
  final InventoryLine? previous;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = previous;
    if (p == null || p.unit != line.unit) {
      return Expanded(
        flex: 2,
        child: Text('—', textAlign: TextAlign.right, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
      );
    }
    final diff = line.total - p.total;
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
class _ItemDialog extends ConsumerStatefulWidget {
  const _ItemDialog({required this.restaurantId, this.item});

  final String restaurantId;
  final InventoryItem? item;

  @override
  ConsumerState<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends ConsumerState<_ItemDialog> {
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
      await ref.read(repositoryProvider).saveInventoryItem(
        widget.restaurantId,
        id: widget.item?.id,
        name: name,
        unit: _unit,
        capacity: capacity!,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      showMessage(context, widget.item == null ? 'Dodano: $name.' : 'Zapisano: $name.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
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
      Navigator.pop(context, true);
      showMessage(context, 'Usunięto: ${item.name}.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
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
        if (widget.item != null)
          TextButton(
            onPressed: _busy ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Usuń'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
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
