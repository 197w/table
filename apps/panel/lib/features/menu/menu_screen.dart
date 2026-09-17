import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  String? _sectionId;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String restaurantId, [String? done]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(menuProvider(restaurantId));
      if (done != null && mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSection(String restaurantId, int count) async {
    final name = await _askName(context, title: 'Nowa sekcja menu', action: 'Dodaj');
    if (name == null) return;
    await _run(
      () => ref.read(repositoryProvider).addSection(restaurantId, name, count),
      restaurantId,
      'Sekcja dodana.',
    );
  }

  Future<void> _renameSection(String restaurantId, MenuSection section) async {
    final name = await _askName(
      context,
      title: 'Zmień nazwę sekcji',
      action: 'Zapisz',
      initial: section.name,
    );
    if (name == null || name == section.name) return;
    await _run(
      () => ref.read(repositoryProvider).renameSection(section.id, name),
      restaurantId,
    );
  }

  Future<void> _deleteSection(String restaurantId, MenuSection section) async {
    final ok = await confirm(
      context,
      title: 'Usunąć sekcję „${section.name}”?',
      message: section.items.isEmpty
          ? 'Sekcja jest pusta.'
          : 'Razem z nią zniknie z menu: ${_positions(section.items.length)}.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    if (_sectionId == section.id) _sectionId = null;
    await _run(
      () => ref.read(repositoryProvider).deleteSection(section.id),
      restaurantId,
      'Sekcja usunięta.',
    );
  }

  Future<void> _moveSection(String restaurantId, List<MenuSection> sections, int index, int delta) {
    final ids = [for (final s in sections) s.id];
    final moved = ids.removeAt(index);
    ids.insert(index + delta, moved);
    return _run(() => ref.read(repositoryProvider).reorder('menu_sections', ids), restaurantId);
  }

  Future<void> _editItem(String restaurantId, MenuSection section, [MenuItem? item]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ItemDialog(section: section, item: item),
    );
    if (saved == true) {
      ref.invalidate(menuProvider(restaurantId));
      if (mounted) showMessage(context, item == null ? 'Pozycja dodana.' : 'Pozycja zapisana.');
    }
  }

  Future<void> _deleteItem(String restaurantId, MenuItem item) async {
    final ok = await confirm(
      context,
      title: 'Usunąć „${item.name}”?',
      message: 'Pozycja zniknie z menu w aplikacji.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    await _run(() => ref.read(repositoryProvider).deleteItem(item.id), restaurantId, 'Pozycja usunięta.');
  }

  Future<void> _moveItem(String restaurantId, MenuSection section, int index, int delta) {
    final ids = [for (final i in section.items) i.id];
    final moved = ids.removeAt(index);
    ids.insert(index + delta, moved);
    return _run(() => ref.read(repositoryProvider).reorder('menu_items', ids), restaurantId);
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final async = ref.watch(menuProvider(restaurant.id));
    final editable = restaurant.canManage;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Menu',
          subtitle: 'Ceny i alergeny widoczne dla gości na stronie lokalu.',
          actions: [
            if (editable && async.hasValue)
              FilledButton.icon(
                onPressed: _busy ? null : () => _addSection(restaurant.id, async.value!.length),
                icon: const Glyph(AppIcons.plus, size: 18),
                label: const Text('Nowa sekcja'),
              ),
          ],
        ),
        if (!editable)
          const ReadOnlyBanner(message: 'Menu zmienia kierownik albo właściciel lokalu.'),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(menuProvider(restaurant.id)),
            ),
            data: (sections) {
              if (sections.isEmpty) {
                return MessageView(
                  icon: AppIcons.bookOpen,
                  title: 'Menu jest puste',
                  message: 'Zacznij od sekcji, na przykład „Przystawki” albo „Dania główne”.',
                  actionLabel: editable ? 'Dodaj sekcję' : null,
                  onAction: editable ? () => _addSection(restaurant.id, 0) : null,
                );
              }
              final current = sections.firstWhere(
                (s) => s.id == _sectionId,
                orElse: () => sections.first,
              );
              return Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 300,
                      child: Card(
                        child: ListView(
                          padding: const EdgeInsets.all(8),
                          children: [
                            for (var i = 0; i < sections.length; i++)
                              _SectionTile(
                                section: sections[i],
                                selected: sections[i].id == current.id,
                                editable: editable,
                                onTap: () => setState(() => _sectionId = sections[i].id),
                                onRename: () => _renameSection(restaurant.id, sections[i]),
                                onDelete: () => _deleteSection(restaurant.id, sections[i]),
                                onUp: i == 0 ? null : () => _moveSection(restaurant.id, sections, i, -1),
                                onDown: i == sections.length - 1
                                    ? null
                                    : () => _moveSection(restaurant.id, sections, i, 1),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                              child: Row(
                                children: [
                                  Expanded(child: Text(current.name, style: text.titleLarge)),
                                  if (editable)
                                    OutlinedButton.icon(
                                      onPressed: () => _editItem(restaurant.id, current),
                                      icon: const Glyph(AppIcons.plus, size: 16),
                                      label: const Text('Dodaj pozycję'),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: current.items.isEmpty
                                  ? MessageView(
                                      icon: AppIcons.forkKnife,
                                      title: 'Brak pozycji',
                                      message: editable
                                          ? 'Dodaj pierwsze danie w tej sekcji.'
                                          : 'W tej sekcji nie ma jeszcze dań.',
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(20, 4, 12, 16),
                                      itemCount: current.items.length,
                                      separatorBuilder: (_, _) => const Divider(height: 1),
                                      itemBuilder: (context, i) => _ItemRow(
                                        item: current.items[i],
                                        editable: editable,
                                        onEdit: () => _editItem(restaurant.id, current, current.items[i]),
                                        onDelete: () => _deleteItem(restaurant.id, current.items[i]),
                                        onUp: i == 0 ? null : () => _moveItem(restaurant.id, current, i, -1),
                                        onDown: i == current.items.length - 1
                                            ? null
                                            : () => _moveItem(restaurant.id, current, i, 1),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.selected,
    required this.editable,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onUp,
    required this.onDown,
  });

  final MenuSection section;
  final bool selected;
  final bool editable;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: selected ? AppColors.surfaceRaised : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        splashColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(section.name, style: text.labelLarge),
                    Text(
                      _positions(section.items.length),
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (editable)
                PopupMenuButton<String>(
                  tooltip: 'Więcej',
                  icon: Glyph(AppIcons.dotsVertical, size: 16, color: AppColors.textMuted),
                  onSelected: (v) => switch (v) {
                    'up' => onUp?.call(),
                    'down' => onDown?.call(),
                    'rename' => onRename(),
                    _ => onDelete(),
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Zmień nazwę')),
                    PopupMenuItem(value: 'up', enabled: onUp != null, child: const Text('Przesuń wyżej')),
                    PopupMenuItem(value: 'down', enabled: onDown != null, child: const Text('Przesuń niżej')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Usuń', style: TextStyle(color: AppColors.error)),
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

String _positions(int n) {
  if (n == 1) return '1 pozycja';
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n pozycje';
  return '$n pozycji';
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.editable,
    required this.onEdit,
    required this.onDelete,
    required this.onUp,
    required this.onDown,
  });

  final MenuItem item;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                if (item.description != null)
                  Text(
                    item.description!,
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                if (item.allergens.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final a in item.allergens)
                        Tag((allergenLabels[a] ?? a).toUpperCase()),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            Fmt.price(item.priceGrosze),
            style: text.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (editable) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Przesuń wyżej',
              icon: const Glyph(AppIcons.caretUp, size: 14),
              onPressed: onUp,
            ),
            IconButton(
              tooltip: 'Przesuń niżej',
              icon: const Glyph(AppIcons.caretDown, size: 14),
              onPressed: onDown,
            ),
            IconButton(
              tooltip: 'Edytuj',
              icon: const Glyph(AppIcons.pencil, size: 16),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Usuń',
              icon: Glyph(AppIcons.trash, size: 16, color: AppColors.error),
              onPressed: onDelete,
            ),
          ],
        ],
      ),
    );
  }
}

Future<String?> _askName(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Nazwa'),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isNotEmpty) Navigator.pop(context, v);
          },
          child: Text(action),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

class _ItemDialog extends ConsumerStatefulWidget {
  const _ItemDialog({required this.section, this.item});

  final MenuSection section;
  final MenuItem? item;

  @override
  ConsumerState<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends ConsumerState<_ItemDialog> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _description = TextEditingController(text: widget.item?.description ?? '');
  late final _price = TextEditingController(
    text: widget.item == null ? '' : groszeToText(widget.item!.priceGrosze),
  );
  late final Set<String> _allergens = {...?widget.item?.allergens};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = parseGrosze(_price.text);
    if (_name.text.trim().isEmpty) {
      showMessage(context, 'Wpisz nazwę dania.');
      return;
    }
    if (price == null) {
      showMessage(context, 'Wpisz cenę, na przykład 32 albo 32,50.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveItem(
        id: widget.item?.id,
        sectionId: widget.section.id,
        name: _name.text,
        description: _description.text,
        priceGrosze: price,
        allergens: _allergens.toList(),
        position: widget.item?.position ?? widget.section.items.length,
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
    return AlertDialog(
      title: Text(widget.item == null ? 'Nowa pozycja: ${widget.section.name}' : 'Edytuj pozycję'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      autofocus: true,
                      maxLength: 80,
                      decoration: const InputDecoration(labelText: 'Nazwa', counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                      decoration: const InputDecoration(labelText: 'Cena', suffixText: 'zł'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _description,
                maxLength: 200,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Opis (opcjonalnie)'),
              ),
              const SizedBox(height: 8),
              Text('Alergeny', style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in allergenLabels.entries)
                    FilterChip(
                      selected: _allergens.contains(e.key),
                      onSelected: (v) => setState(
                        () => v ? _allergens.add(e.key) : _allergens.remove(e.key),
                      ),
                      label: Text(
                        e.value,
                        style: TextStyle(
                          color: _allergens.contains(e.key) ? AppColors.onAccent : AppColors.text,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Zapisz')),
      ],
    );
  }
}
