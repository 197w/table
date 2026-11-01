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

/// Dzień i godzina wpisu: „Dziś, 14:05” albo „pt 24 paź, 07:30”.
String docWhen(DateTime t) {
  final local = t.toLocal();
  final today = dateOnly(DateTime.now());
  final day = dateOnly(local);
  final label = day == today
      ? 'Dziś'
      : day == today.subtract(const Duration(days: 1))
      ? 'Wczoraj'
      : Fmt.dayShort(local);
  return '$label, ${_hm(local)}';
}

void _refresh(WidgetRef ref, String restaurantId) => ref
  ..invalidate(inventoryDocsProvider(restaurantId))
  ..invalidate(inventoryStockProvider(restaurantId))
  ..invalidate(inventoryCountsProvider(restaurantId));

/// Inwentaryzacja → Dostawy i usunięcia: dostawy (kiedy przyjechały, co przyjechało) i usunięcia (powód,
/// wyjaśnienie) z ostatnich 60 dni. Każdy wpis od razu zmienia stan składników; pomyłkę usuwa się w całości.
class InventoryDocsTab extends ConsumerWidget {
  const InventoryDocsTab({
    super.key,
    required this.restaurantId,
    required this.canAdd,
    required this.canDelete,
    required this.memberId,
    required this.onAdd,
  });

  final String restaurantId;
  final bool canAdd;
  final bool canDelete;
  final String? memberId;
  final ValueChanged<bool> onAdd;

  Future<void> _delete(BuildContext context, WidgetRef ref, InventoryDoc doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Usunąć wpis „${doc.title}”?'),
        content: const Text('Stan składników wróci do tego sprzed wpisu. Użyj tego tylko przy pomyłce.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Wróć')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Usuń wpis'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repositoryProvider).deleteInventoryDoc(doc.id, memberId: memberId);
      _refresh(ref, restaurantId);
      if (context.mounted) showMessage(context, 'Wpis usunięty.');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(inventoryDocsProvider(restaurantId));
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(inventoryDocsProvider(restaurantId))),
      data: (docs) {
        if (docs.isEmpty) {
          return MessageView(
            icon: AppIcons.truck.duotone,
            title: 'Brak dostaw i usunięć',
            message:
                'Wpisz dostawę, gdy towar przyjedzie: stan składników zwiększy się sam. Usunięcie (np. przekazanie '
                'do drugiego lokalu) zmniejsza stan i wymaga powodu.',
            actionLabel: canAdd ? 'Wpisz dostawę' : null,
            onAction: canAdd ? () => onAdd(true) : null,
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
          children: [
            for (final d in docs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InventoryDocTile(doc: d, onDelete: canDelete ? () => _delete(context, ref, d) : null),
              ),
          ],
        );
      },
    );
  }
}

/// Wpis dostawy albo usunięcia: rodzaj, kiedy, kto, składniki z ilościami i wyjaśnienie.
class InventoryDocTile extends StatelessWidget {
  const InventoryDocTile({super.key, required this.doc, this.onDelete});

  final InventoryDoc doc;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = doc.delivery ? TileColors.green : TileColors.rose;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ring),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(doc.delivery ? AppIcons.truck : AppIcons.minusCircle, color: color, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.title, style: text.titleSmall),
                Text(
                  [docWhen(doc.happenedAt), if (doc.createdBy != null) 'wpisał(a) ${doc.createdBy}'].join(' · '),
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
                const SizedBox(height: 6),
                for (final l in doc.lines)
                  Text(
                    '${doc.delivery ? '+' : '−'} ${l.name}: ${l.text}',
                    style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                  ),
                if (doc.note != null) ...[
                  const SizedBox(height: 4),
                  Text(doc.note!, style: text.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
          if (onDelete != null)
            DeleteButton(
              tooltip: 'Usuń wpis (pomyłka)',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _DocLine {
  String? itemId;
  final packages = TextEditingController();
  final loose = TextEditingController();

  void dispose() {
    packages.dispose();
    loose.dispose();
  }
}

/// Nowa dostawa albo usunięcie: kiedy, składniki (pełne opakowania i reszta, razem liczy się samo),
/// przy dostawie dostawca i numer dokumentu, przy usunięciu powód i wyjaśnienie (wymagane).
class InventoryDocDialog extends ConsumerStatefulWidget {
  const InventoryDocDialog({
    super.key,
    required this.restaurantId,
    required this.delivery,
    required this.items,
    required this.memberId,
  });

  final String restaurantId;
  final bool delivery;
  final List<InventoryItem> items;
  final String? memberId;

  @override
  ConsumerState<InventoryDocDialog> createState() => _InventoryDocDialogState();
}

class _InventoryDocDialogState extends ConsumerState<InventoryDocDialog> {
  final _lines = [_DocLine()];
  final _supplier = TextEditingController();
  final _documentNo = TextEditingController();
  final _note = TextEditingController();
  DateTime _when = DateTime.now();
  bool _whenChanged = false;
  RemovalReason? _reason;
  bool _busy = false;

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _supplier.dispose();
    _documentNo.dispose();
    _note.dispose();
    super.dispose();
  }

  InventoryItem? _item(String? id) => widget.items.where((i) => i.id == id).firstOrNull;

  double? _amount(_DocLine l) {
    final item = _item(l.itemId);
    if (item == null) return null;
    final p = parseInventoryNumber(l.packages.text) ?? 0;
    final lo = parseInventoryNumber(l.loose.text) ?? 0;
    final total = p * item.capacity + lo / item.unit.portionFactor;
    return total > 0 ? total : null;
  }

  Future<void> _pickWhen() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now(),
    );
    if (day == null || !mounted) return;
    final time = await pickTime(
      context,
      initial: TimeOfDay.fromDateTime(_when),
      minuteStep: 5,
      title: widget.delivery ? 'Godzina dostawy' : 'Godzina usunięcia',
    );
    if (!mounted) return;
    final t = time ?? TimeOfDay.fromDateTime(_when);
    var picked = DateTime(day.year, day.month, day.day, t.hour, t.minute);
    if (picked.isAfter(DateTime.now())) picked = DateTime.now();
    setState(() {
      _when = picked;
      _whenChanged = true;
    });
  }

  Future<void> _save() async {
    final lines = [
      for (final l in _lines)
        if (l.itemId != null)
          (
            itemId: l.itemId!,
            packages: parseInventoryNumber(l.packages.text),
            loose: parseInventoryNumber(l.loose.text),
          ),
    ];
    String? problem;
    if (lines.isEmpty) {
      problem = 'Wybierz co najmniej jeden składnik.';
    } else if (_lines.any((l) => l.itemId != null && _amount(l) == null)) {
      problem = 'Wpisz ilość przy każdym składniku.';
    } else if (lines.map((l) => l.itemId).toSet().length != lines.length) {
      problem = 'Każdy składnik tylko raz.';
    } else if (!widget.delivery && _reason == null) {
      problem = 'Wybierz powód usunięcia.';
    } else if (!widget.delivery && _note.text.trim().isEmpty) {
      problem = 'Wpisz wyjaśnienie: dlaczego i dokąd składniki zniknęły z lokalu.';
    }
    if (problem != null) {
      showMessage(context, problem, tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .saveInventoryDoc(
            widget.restaurantId,
            delivery: widget.delivery,
            happenedAt: _whenChanged ? _when : DateTime.now(),
            lines: lines,
            reason: _reason,
            supplier: _supplier.text.trim(),
            documentNo: _documentNo.text.trim(),
            note: _note.text.trim(),
            memberId: widget.memberId,
          );
      _refresh(ref, widget.restaurantId);
      if (!mounted) return;
      Navigator.pop(context, true);
      showMessage(
        context,
        widget.delivery ? 'Dostawa zapisana. Stan składników się zwiększył.' : 'Usunięcie zapisane.',
        tone: ToastTone.success,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sorted = [...widget.items]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final numberFormatter = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return AlertDialog(
      title: Text(widget.delivery ? 'Dostawa' : 'Usunięcie składników'),
      content: SizedBox(
        width: 820,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.delivery
                    ? 'Wpisz, co przyjechało. Stan składników zwiększy się od chwili dostawy.'
                    : 'Składnik fizycznie zniknął z lokalu, ale nie został sprzedany (np. przekazany do drugiego '
                          'lokalu). Powód i wyjaśnienie będą widoczne na końcu inwentaryzacji.',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Glyph(AppIcons.calendar, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    widget.delivery ? 'Przyjechała: ${docWhen(_when)}' : 'Kiedy: ${docWhen(_when)}',
                    style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _busy ? null : _pickWhen, child: const Text('Zmień')),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.delivery)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _supplier,
                        maxLength: 120,
                        decoration: const InputDecoration(labelText: 'Dostawca (opcjonalnie)', counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _documentNo,
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: 'Numer faktury albo WZ (opcjonalnie)',
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                )
              else
                DropdownButtonFormField<RemovalReason>(
                  initialValue: _reason,
                  decoration: const InputDecoration(labelText: 'Powód'),
                  icon: const Glyph(AppIcons.caretDown, size: 16),
                  items: [for (final r in RemovalReason.values) DropdownMenuItem(value: r, child: Text(r.label))],
                  onChanged: (r) => setState(() => _reason = r),
                ),
              const SizedBox(height: 16),
              Text('Składniki', style: text.titleSmall),
              const SizedBox(height: 8),
              for (final (i, l) in _lines.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 5,
                        child: DropdownMenu<String>(
                          key: ValueKey('skladnik-$i-${l.itemId}'),
                          initialSelection: l.itemId,
                          expandedInsets: EdgeInsets.zero,
                          enableFilter: true,
                          requestFocusOnTap: true,
                          hintText: 'Składnik',
                          menuHeight: 320,
                          trailingIcon: const Glyph(AppIcons.caretDown, size: 16),
                          selectedTrailingIcon: const Glyph(AppIcons.caretUp, size: 16),
                          dropdownMenuEntries: [
                            for (final item in sorted)
                              DropdownMenuEntry(value: item.id, label: item.name, labelWidget: Text(item.name)),
                          ],
                          onSelected: (id) => setState(() => l.itemId = id),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: l.packages,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: numberFormatter,
                          textAlign: TextAlign.right,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'pełne op.',
                            suffixText: packWord(_item(l.itemId)?.packName, parseInventoryNumber(l.packages.text)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: l.loose,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: numberFormatter,
                          textAlign: TextAlign.right,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'reszta',
                            suffixText: _item(l.itemId)?.unit.portion.label ?? 'g',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 96,
                        child: Text(
                          switch ((_item(l.itemId), _amount(l))) {
                            (final item?, final a?) => '= ${inventoryNumber(a)} ${item.unit.label}',
                            _ => '',
                          },
                          textAlign: TextAlign.right,
                          style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Usuń z listy',
                        onPressed: _lines.length == 1
                            ? null
                            : () => setState(() {
                                _lines.removeAt(i).dispose();
                              }),
                        icon: const Glyph(AppIcons.close, size: 16),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _lines.add(_DocLine())),
                  icon: const Glyph(AppIcons.plus, size: 16),
                  label: const Text('Dodaj składnik'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: widget.delivery ? 'Uwagi (opcjonalnie)' : 'Wyjaśnienie (wymagane)',
                  hintText: widget.delivery ? null : 'Na przykład: przekazane do lokalu na Rynku, odebrał Marek',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(widget.delivery ? 'Zapisz dostawę' : 'Zapisz usunięcie'),
        ),
      ],
    );
  }
}

/// Pojemniki do ważenia (mały, średni, duży) z wagą pustego pojemnika. Uprawnienie „Edytowanie składników”.
class InventoryContainersDialog extends ConsumerWidget {
  const InventoryContainersDialog({super.key, required this.restaurantId});

  final String restaurantId;

  Future<void> _edit(BuildContext context, WidgetRef ref, [InventoryContainer? box]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ContainerDialog(restaurantId: restaurantId, box: box),
    );
    if (saved == true) ref.invalidate(inventoryContainersProvider(restaurantId));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, InventoryContainer box) async {
    try {
      await ref.read(repositoryProvider).deleteInventoryContainer(box.id);
      ref
        ..invalidate(inventoryContainersProvider(restaurantId))
        ..invalidate(inventoryItemsProvider(restaurantId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final boxes = ref.watch(inventoryContainersProvider(restaurantId)).value ?? const <InventoryContainer>[];
    return AlertDialog(
      title: const Text('Pojemniki do ważenia'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Wpisz wagę pustych pojemników. Gdy w spisie zaznaczysz „w pojemniku”, panel sam odejmie jego wagę '
              'od wpisanej.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (boxes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Brak pojemników.', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
              ),
            for (final b in boxes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Glyph(AppIcons.scales, size: 20, color: AppColors.textMuted),
                title: Text(b.name),
                subtitle: Text('${inventoryGrouped(b.tareG)} g', style: const TextStyle(fontFeatures: _tabular)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Zmień',
                      onPressed: () => _edit(context, ref, b),
                      icon: const Glyph(AppIcons.pencil, size: 16),
                    ),
                    DeleteButton(
                      tooltip: 'Usuń',
                      onPressed: () => _delete(context, ref, b),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _edit(context, ref),
                icon: const Glyph(AppIcons.plus, size: 16),
                label: const Text('Dodaj pojemnik'),
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zamknij'))],
    );
  }
}

class _ContainerDialog extends ConsumerStatefulWidget {
  const _ContainerDialog({required this.restaurantId, this.box});

  final String restaurantId;
  final InventoryContainer? box;

  @override
  ConsumerState<_ContainerDialog> createState() => _ContainerDialogState();
}

class _ContainerDialogState extends ConsumerState<_ContainerDialog> {
  late final _name = TextEditingController(text: widget.box?.name ?? '');
  late final _tare = TextEditingController(text: widget.box == null ? '' : inventoryNumber(widget.box!.tareG));
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _tare.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final tare = parseInventoryNumber(_tare.text);
    if (_name.text.trim().isEmpty || tare == null || tare < 0) {
      showMessage(context, 'Wpisz nazwę i wagę pojemnika w gramach.', tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .saveInventoryContainer(widget.restaurantId, id: widget.box?.id, name: _name.text.trim(), tareG: tare);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.box == null ? 'Nowy pojemnik' : 'Pojemnik'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Nazwa', hintText: 'Na przykład: Średni GN 1/2'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tare,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(labelText: 'Waga pustego pojemnika', suffixText: 'g'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(widget.box == null ? 'Dodaj' : 'Zapisz')),
      ],
    );
  }
}
