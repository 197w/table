import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/menu_photo.dart';
import '../../shared/panel_widgets.dart';
import '../inventory/inventory_screen.dart';

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
      if (mounted) showError(context, e);
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
      builder: (_) => _ItemDialog(restaurantId: restaurantId, section: section, item: item),
    );
    if (saved == true) {
      ref
        ..invalidate(menuProvider(restaurantId))
        ..invalidate(inventoryItemsProvider(restaurantId));
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

  Future<void> _photo(String restaurantId, MenuItem item) async {
    try {
      final jpeg = await pickMenuPhoto();
      if (jpeg == null) return;
      await _run(
        () => ref.read(repositoryProvider).uploadMenuPhoto(restaurantId: restaurantId, itemId: item.id, jpeg: jpeg),
        restaurantId,
        'Zdjęcie „${item.name}” zapisane. Goście zobaczą je w aplikacji.',
      );
    } on FormatException {
      if (mounted) showMessage(context, 'Nie udało się odczytać zdjęcia. Wybierz plik JPG, PNG albo WEBP.');
    }
  }

  Future<void> _removePhoto(String restaurantId, MenuItem item) {
    return _run(() => ref.read(repositoryProvider).removeMenuPhoto(item.id), restaurantId, 'Zdjęcie usunięte.');
  }

  Future<void> _toggleAvailable(String restaurantId, MenuItem item) {
    return _run(
      () => ref.read(repositoryProvider).setItemAvailable(item.id, !item.available),
      restaurantId,
      item.available ? '„${item.name}” oznaczone jako niedostępne.' : '„${item.name}” znowu dostępne.',
    );
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
    // Zmiany w menu według uprawnień pracownika zalogowanego w panelu.
    final permissions = ref.watch(memberPermissionsProvider);
    final editable = restaurant.canManage && permissions.contains('menu_edit');
    final canToggle = permissions.contains('menu_availability') || permissions.contains('menu_edit');
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
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
                                        onPhoto: () => _photo(restaurant.id, current.items[i]),
                                        onRemovePhoto: () => _removePhoto(restaurant.id, current.items[i]),
                                        onToggleAvailable: canToggle
                                            ? () => _toggleAvailable(restaurant.id, current.items[i])
                                            : null,
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

class _ItemRow extends ConsumerWidget {
  const _ItemRow({
    required this.item,
    required this.editable,
    required this.onEdit,
    required this.onPhoto,
    required this.onRemovePhoto,
    required this.onToggleAvailable,
    required this.onDelete,
    required this.onUp,
    required this.onDown,
  });

  final MenuItem item;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onPhoto;
  final VoidCallback onRemovePhoto;

  /// Null: brak uprawnienia „Dostępność dań”.
  final VoidCallback? onToggleAvailable;
  final VoidCallback onDelete;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    // Receptura: nazwy składników z inwentaryzacji. Goście w aplikacji jej nie widzą.
    final restaurant = ref.watch(currentRestaurantProvider);
    final stock = item.ingredients.isEmpty || restaurant == null
        ? const <String, InventoryItem>{}
        : {
            for (final i in ref.watch(inventoryItemsProvider(restaurant.id)).value ?? const <InventoryItem>[])
              i.id: i,
          };
    final recipe = [
      for (final r in item.ingredients)
        if (stock[r.itemId] case final i?) '${i.name.toLowerCase()} ${inventoryNumber(r.amount)} ${r.unit.label}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Zdjęcie dania: kliknięcie dodaje albo zmienia (z uprawnieniem „Edycja menu”).
          if (item.photoUrl != null || editable) ...[
            _PhotoThumb(
              url: item.photoUrl,
              onPick: editable ? onPhoto : null,
              onRemove: editable && item.photoUrl != null ? onRemovePhoto : null,
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: item.available ? null : AppColors.textMuted,
                        ),
                      ),
                    ),
                    if (!item.available) ...[
                      const SizedBox(width: 8),
                      Tag('NIEDOSTĘPNE', color: AppColors.error),
                    ],
                  ],
                ),
                if (item.description != null)
                  Text(
                    item.description!,
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                if (item.variants.isNotEmpty || item.addons.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      for (final v in item.variants) '${v.name} ${Fmt.price(v.priceGrosze)}',
                      if (item.addons.isNotEmpty)
                        'dodatki: ${item.addons.map((a) => a.name.toLowerCase()).join(', ')}',
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                if (recipe.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Glyph(AppIcons.package, size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          recipe.join(', '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
            item.priceVaries ? 'od ${Fmt.price(item.fromPrice)}' : Fmt.price(item.fromPrice),
            style: text.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          if (onToggleAvailable != null)
            IconButton(
              tooltip: item.available ? 'Skończyło się: oznacz jako niedostępne' : 'Znowu dostępne',
              icon: Glyph(
                item.available ? AppIcons.eye : AppIcons.eyeSlash,
                size: 16,
                color: item.available ? AppColors.textMuted : AppColors.error,
              ),
              onPressed: onToggleAvailable,
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
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(
      title: title,
      action: action,
      label: 'Nazwa',
      initial: initial,
    ),
  );
}

/// Okno z jednym polem tekstowym. Kontroler żyje tak długo jak okno.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.action,
    required this.label,
    this.initial = '',
  });

  final String title;
  final String action;
  final String label;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(labelText: widget.label, counterText: ''),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

class _ItemDialog extends ConsumerStatefulWidget {
  const _ItemDialog({required this.restaurantId, required this.section, this.item});

  final String restaurantId;
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
  late final _variants = [for (final v in widget.item?.variants ?? const <MenuOption>[]) _OptionRow(v)];
  late final _addons = [for (final a in widget.item?.addons ?? const <MenuOption>[]) _OptionRow(a)];
  late final _recipe = [for (final r in widget.item?.ingredients ?? const <RecipeLine>[]) _RecipeRow(r)];
  late int _vat = widget.item?.vatRate ?? 8;
  late bool _available = widget.item?.available ?? true;
  late bool _showInKitchen = widget.item?.showInKitchen ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    for (final r in [..._variants, ..._addons]) {
      r.dispose();
    }
    for (final r in _recipe) {
      r.dispose();
    }
    super.dispose();
  }

  /// Receptura z wierszy. Null i komunikat, gdy któryś wiersz jest źle wpisany.
  List<RecipeLine>? _readRecipe(Map<String, InventoryItem> items) {
    final lines = <RecipeLine>[];
    final seen = <String>{};
    for (final r in _recipe) {
      final amount = parseInventoryNumber(r.amount.text);
      if (r.itemId == null && r.amount.text.trim().isEmpty) continue;
      final item = items[r.itemId];
      if (item == null) {
        showMessage(context, 'Wybierz składnik w każdym wierszu receptury.');
        return null;
      }
      if (amount == null || amount <= 0) {
        showMessage(context, 'Wpisz, ile „${item.name}” zużywa jedna porcja.');
        return null;
      }
      if (!seen.add(item.id)) {
        showMessage(context, 'Składnik „${item.name}” jest w recepturze dwa razy.');
        return null;
      }
      lines.add(RecipeLine(itemId: item.id, amount: amount, unit: r.unit ?? item.unit.portion));
    }
    return lines;
  }

  bool _sameRecipe(List<RecipeLine> lines) {
    final before = widget.item?.ingredients ?? const <RecipeLine>[];
    if (before.length != lines.length) return false;
    for (var i = 0; i < lines.length; i++) {
      final a = before[i];
      final b = lines[i];
      if (a.itemId != b.itemId || a.unit != b.unit || (a.amount - b.amount).abs() > 0.0005) return false;
    }
    return true;
  }

  /// Nowy składnik prosto z okna dania. Trafia do „Inwentaryzacja” → „Składniki”.
  Future<void> _newIngredient() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => InventoryItemDialog(restaurantId: widget.restaurantId, canDelete: false),
    );
    if (id == null || !mounted) return;
    ref.invalidate(inventoryItemsProvider(widget.restaurantId));
    final items = await ref.read(inventoryItemsProvider(widget.restaurantId).future);
    final item = items.where((i) => i.id == id).firstOrNull;
    if (!mounted) return;
    setState(() {
      // Pusty wiersz dostaje nowy składnik, inaczej dochodzi nowy wiersz.
      final empty = _recipe.where((r) => r.itemId == null).firstOrNull;
      final row = empty ?? _RecipeRow();
      row.itemId = id;
      row.unit = item?.unit.portion;
      if (empty == null) _recipe.add(row);
    });
  }

  /// Wiersze z opcjami zamienione na listę. Null i komunikat, gdy któryś jest źle wpisany.
  List<MenuOption>? _read(List<_OptionRow> rows, String what) {
    final list = <MenuOption>[];
    final names = <String>{};
    for (final r in rows) {
      final name = r.name.text.trim();
      final price = parseGrosze(r.price.text);
      if (name.isEmpty && r.price.text.trim().isEmpty) continue;
      if (name.isEmpty) {
        showMessage(context, 'Wpisz nazwę każdej opcji w sekcji „$what”.');
        return null;
      }
      if (price == null) {
        showMessage(context, 'Wpisz cenę opcji „$name”, na przykład 32 albo 32,50.');
        return null;
      }
      if (!names.add(name.toLowerCase())) {
        showMessage(context, 'Opcja „$name” powtarza się w sekcji „$what”.');
        return null;
      }
      list.add(MenuOption(name, price));
    }
    return list;
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showMessage(context, 'Wpisz nazwę dania.');
      return;
    }
    final variants = _read(_variants, 'Warianty');
    if (variants == null) return;
    final addons = _read(_addons, 'Dodatki');
    if (addons == null) return;
    final List<InventoryItem> stock;
    try {
      stock = _recipe.isEmpty ? const [] : await ref.read(inventoryItemsProvider(widget.restaurantId).future);
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    final recipe = _readRecipe({for (final i in stock) i.id: i});
    if (recipe == null) return;
    // Przy wariantach cena pozycji to najniższa z nich: tak gość widzi „od 25 zł”.
    final price = variants.isEmpty
        ? parseGrosze(_price.text)
        : variants.map((v) => v.priceGrosze).reduce((a, b) => a < b ? a : b);
    if (price == null) {
      showMessage(context, 'Wpisz cenę, na przykład 32 albo 32,50.');
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      final id = await repo.saveItem(
        id: widget.item?.id,
        sectionId: widget.section.id,
        name: _name.text,
        description: _description.text,
        priceGrosze: price,
        allergens: _allergens.toList(),
        position: widget.item?.position ?? widget.section.items.length,
        variants: variants,
        addons: addons,
        vatRate: _vat,
        available: _available,
        showInKitchen: _showInKitchen,
      );
      if (!_sameRecipe(recipe)) await repo.setMenuItemIngredients(id, recipe);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
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
          // Odstęp u góry, żeby etykiety pól nie chowały się pod tytułem okna.
          padding: const EdgeInsets.only(top: 8),
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
                    // Przy wariantach cenę ma każdy wariant osobno.
                    child: _variants.isEmpty
                        ? TextField(
                            controller: _price,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                            decoration: const InputDecoration(labelText: 'Cena', suffixText: 'zł'),
                          )
                        : const TextField(
                            enabled: false,
                            decoration: InputDecoration(
                              labelText: 'Cena',
                              hintText: 'z wariantów',
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                            ),
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
              _OptionsEditor(
                title: 'Warianty',
                hint: 'Np. rozmiary: Mała 25 zł, Duża 39 zł. Gość i kelner wybierają jeden.',
                addLabel: 'Dodaj wariant',
                namePlaceholder: 'Duża',
                rows: _variants,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 16),
              _OptionsEditor(
                title: 'Dodatki',
                hint: 'Płatne dodatki doliczane do ceny, np. „Ser +4 zł”. Można wybrać kilka.',
                addLabel: 'Dodaj dodatek',
                namePlaceholder: 'Ser',
                rows: _addons,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 16),
              _RecipeEditor(
                items: ref.watch(inventoryItemsProvider(widget.restaurantId)).value ?? const [],
                rows: _recipe,
                onChanged: () => setState(() {}),
                onNew: _newIngredient,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Stawka VAT', style: text.titleSmall),
                        Text(
                          '8% jedzenie na miejscu, 23% alkohol',
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  SegmentedTabs<int>(
                    options: [for (final r in vatRates) (r, '$r%')],
                    selected: _vat,
                    onChanged: (v) => setState(() => _vat = v),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dostępne teraz', style: text.titleSmall),
                        Text(
                          'Wyłącz, gdy danie się skończy. Goście zobaczą je jako niedostępne.',
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Switch(value: _available, onChanged: (v) => setState(() => _available = v)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pokazuj na kuchni', style: text.titleSmall),
                        Text(
                          'Wyłącz dla pozycji, których kuchnia nie robi, np. napojów z baru.',
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Switch(value: _showInKitchen, onChanged: (v) => setState(() => _showInKitchen = v)),
                ],
              ),
              const SizedBox(height: 18),
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

/// Jeden wiersz receptury: składnik, ilość na porcję i jednostka.
class _RecipeRow {
  _RecipeRow([RecipeLine? line])
    : itemId = line?.itemId,
      unit = line?.unit,
      amount = TextEditingController(text: line == null ? '' : inventoryNumber(line.amount));

  String? itemId;

  /// Null: jednostka porcji składnika (ml dla litrów, g dla kilogramów).
  InventoryUnit? unit;
  final TextEditingController amount;

  void dispose() => amount.dispose();
}

/// Receptura dania: ile czego zużywa jedna porcja. Po wysłaniu dania panel odejmuje to ze stanu
/// w Inwentaryzacji. Goście w aplikacji tego nie widzą.
class _RecipeEditor extends StatelessWidget {
  const _RecipeEditor({required this.items, required this.rows, required this.onChanged, required this.onNew});

  final List<InventoryItem> items;
  final List<_RecipeRow> rows;
  final VoidCallback onChanged;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final byId = {for (final i in items) i.id: i};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Składniki', style: text.titleSmall),
            const SizedBox(width: 8),
            Tag('TYLKO W PANELU', color: AppColors.textMuted),
            const Spacer(),
            TextButton.icon(
              onPressed: onNew,
              icon: const Glyph(AppIcons.package, size: 14),
              label: const Text('Nowy składnik'),
            ),
            if (items.isNotEmpty && rows.length < 50)
              TextButton.icon(
                onPressed: () {
                  rows.add(_RecipeRow());
                  onChanged();
                },
                icon: const Glyph(AppIcons.plus, size: 14),
                label: const Text('Dodaj'),
              ),
          ],
        ),
        Text(
          'Ile czego zużywa jedna porcja, np. wódka 50 ml. Po wysłaniu dania panel odejmuje to ze stanu '
          'w „Inwentaryzacja” → „Składniki”. Goście tego nie widzą.',
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        for (final row in rows) ...[
          const SizedBox(height: 8),
          Row(
            key: ObjectKey(row),
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  // Klucz ze składnikiem: wybór wstawiony z „Nowy składnik” odświeża pole.
                  key: ValueKey('${identityHashCode(row)}-${row.itemId}'),
                  initialValue: byId.containsKey(row.itemId) ? row.itemId : null,
                  isExpanded: true,
                  isDense: true,
                  icon: Glyph(AppIcons.caretDown, size: 14, color: AppColors.textMuted),
                  hint: const Text('Wybierz składnik'),
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (final i in items)
                      DropdownMenuItem(
                        value: i.id,
                        child: Text('${i.name} · ${i.package}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) {
                    row.itemId = id;
                    // Po zmianie składnika jednostka wraca do jego jednostki porcji.
                    row.unit = byId[id]?.unit.portion;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 88,
                child: TextField(
                  controller: row.amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(hintText: '0', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: switch (byId[row.itemId]) {
                  final item? when item.unit.compatible.length > 1 => DropdownButtonFormField<InventoryUnit>(
                    key: ValueKey('${row.itemId}-unit'),
                    initialValue: row.unit ?? item.unit.portion,
                    isDense: true,
                    isExpanded: true,
                    icon: Glyph(AppIcons.caretDown, size: 14, color: AppColors.textMuted),
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      for (final u in item.unit.compatible) DropdownMenuItem(value: u, child: Text(u.label)),
                    ],
                    onChanged: (u) {
                      row.unit = u;
                      onChanged();
                    },
                  ),
                  final item? => Text(item.unit.label, style: text.bodyMedium),
                  null => const SizedBox.shrink(),
                },
              ),
              IconButton(
                tooltip: 'Usuń',
                icon: Glyph(AppIcons.close, size: 16, color: AppColors.textMuted),
                onPressed: () {
                  rows.remove(row);
                  onChanged();
                  WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
                },
              ),
            ],
          ),
        ],
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Nie ma jeszcze składników. Kliknij „Nowy składnik”, np. mąka 25 kg albo wódka 0,7 l.',
              style: text.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Jeden wiersz wariantu albo dodatku w oknie pozycji.
class _OptionRow {
  _OptionRow([MenuOption? option])
    : name = TextEditingController(text: option?.name ?? ''),
      price = TextEditingController(text: option == null ? '' : groszeToText(option.priceGrosze));

  final TextEditingController name;
  final TextEditingController price;

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

/// Lista wariantów albo dodatków: nazwa i cena w każdym wierszu.
class _OptionsEditor extends StatelessWidget {
  const _OptionsEditor({
    required this.title,
    required this.hint,
    required this.addLabel,
    required this.namePlaceholder,
    required this.rows,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final String addLabel;
  final String namePlaceholder;
  final List<_OptionRow> rows;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: text.titleSmall)),
            if (rows.length < 20)
              TextButton.icon(
                onPressed: () {
                  rows.add(_OptionRow());
                  onChanged();
                },
                icon: const Glyph(AppIcons.plus, size: 14),
                label: Text(addLabel),
              ),
          ],
        ),
        Text(hint, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        for (final row in rows) ...[
          const SizedBox(height: 8),
          Row(
            key: ObjectKey(row),
            children: [
              Expanded(
                child: TextField(
                  controller: row.name,
                  maxLength: 40,
                  decoration: InputDecoration(
                    hintText: namePlaceholder,
                    isDense: true,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: row.price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  decoration: const InputDecoration(hintText: '0', suffixText: 'zł', isDense: true),
                ),
              ),
              IconButton(
                tooltip: 'Usuń',
                icon: Glyph(AppIcons.close, size: 16, color: AppColors.textMuted),
                onPressed: () {
                  rows.remove(row);
                  onChanged();
                  // Pola znikną dopiero po przebudowie, więc kontrolery zwalniamy po klatce.
                  WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Miniatura zdjęcia dania. Bez zdjęcia: pole „Dodaj zdjęcie”. Menu: zmiana albo usunięcie.
class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.url, required this.onPick, required this.onRemove});

  final String? url;
  final VoidCallback? onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final box = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 72,
        height: 72,
        color: AppColors.surfaceRaised,
        child: url == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Glyph(AppIcons.plus, size: 18, color: AppColors.textMuted),
                  const SizedBox(height: 2),
                  Text(
                    'Zdjęcie',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                cacheWidth: 144,
                errorBuilder: (_, _, _) => Center(child: Glyph(AppIcons.warning, size: 18, color: AppColors.textMuted)),
              ),
      ),
    );
    if (onPick == null) return box;
    if (url == null) {
      return Tooltip(
        message: 'Dodaj zdjęcie dania',
        child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onPick, child: box),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Zdjęcie dania',
      onSelected: (v) => v == 'remove' ? onRemove?.call() : onPick!(),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'change', child: Text('Zmień zdjęcie')),
        if (onRemove != null)
          PopupMenuItem(value: 'remove', child: Text('Usuń zdjęcie', style: TextStyle(color: AppColors.error))),
      ],
      child: box,
    );
  }
}
