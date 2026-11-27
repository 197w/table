import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/menu_photo.dart';
import '../../shared/panel_select.dart';
import '../../shared/panel_widgets.dart';
import '../../shared/side_panel.dart';
import '../inventory/inventory_screen.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Stałe szerokości wąskich kolumn tabeli dań; pozycja i opcje dzielą resztę.
const _priceWidth = 104.0;
const _stateWidth = 140.0;
const _actionsWidth = 48.0;

/// Kiedy dział jest w menu: zawsze, w okresie (sezon, 0088) albo tylko na wydarzenie z Kalendarza (0080).
enum MenuWhen { always, season, event }

MenuWhen menuWhenOf(MenuSection s) => s.eventId != null ? MenuWhen.event : (s.season != null ? MenuWhen.season : MenuWhen.always);

/// Okno obok panelu: dodawanie i zmiana dania albo działu.
sealed class _MenuSheet {
  const _MenuSheet();
}

class _ItemSheetOpen extends _MenuSheet {
  const _ItemSheetOpen({required this.sectionId, this.itemId});

  final String sectionId;
  final String? itemId;
}

class _SectionSheetOpen extends _MenuSheet {
  const _SectionSheetOpen([this.sectionId]);

  /// Null: nowy dział.
  final String? sectionId;
}

/// Dział z daniami po filtrach i jego miejsce na liście wszystkich działów (do zmiany kolejności).
class _Group {
  const _Group(this.section, this.items, this.index);

  final MenuSection section;
  final List<MenuItem> items;
  final int index;
}

/// Menu w układzie jak Pracownicy (16.11.2026, prośba użytkownika: „zmień wygląd Menu na nowy”): po lewej zwijany
/// panel z wyszukiwaniem, „Dodaj pozycję”, „Nowa sekcja” i filtrami z liczbą dań (sekcja, kiedy w menu,
/// dostępność), po prawej tabela dań pogrupowana w sekcje. Dodawanie i zmiana dania albo sekcji otwierają okno
/// obok panelu (`SideSheetFrame`). Sekcja jest w menu zawsze, w okresie od dnia do dnia (sezonowa, co roku albo
/// jednorazowo, 0088) albo tylko na wydarzenie z Kalendarza (0080).
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final _search = TextEditingController();
  final _sectionIds = <String>{};
  final _whens = <MenuWhen>{};
  final _states = <String>{};
  final _closed = <String>{};
  bool _panelOpen = true;
  bool _busy = false;
  _MenuSheet? _sheet;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle<T>(Set<T> set, T value) => setState(() => set.contains(value) ? set.remove(value) : set.add(value));

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

  void _afterSave(String restaurantId, String message) {
    ref
      ..invalidate(menuProvider(restaurantId))
      ..invalidate(inventoryItemsProvider(restaurantId));
    setState(() => _sheet = null);
    showMessage(context, message);
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
    if (mounted) {
      setState(() {
        if (_sheet case _SectionSheetOpen(:final sectionId) when sectionId == section.id) _sheet = null;
        _sectionIds.remove(section.id);
      });
    }
    await _run(() => ref.read(repositoryProvider).deleteSection(section.id), restaurantId, 'Sekcja usunięta.');
  }

  Future<void> _moveSection(String restaurantId, List<MenuSection> sections, int index, int delta) {
    final ids = [for (final s in sections) s.id];
    final moved = ids.removeAt(index);
    ids.insert(index + delta, moved);
    return _run(() => ref.read(repositoryProvider).reorder('menu_sections', ids), restaurantId);
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
    if (!mounted) return;
    if (_sheet case _ItemSheetOpen(:final itemId) when itemId == item.id) setState(() => _sheet = null);
    await _run(() => ref.read(repositoryProvider).deleteItem(item.id), restaurantId, 'Pozycja usunięta.');
  }

  Future<void> _photo(String restaurantId, MenuItem item) async {
    try {
      final picked = await pickImage(ImageSpec.dish);
      if (picked == null) return;
      final note = imageNote(picked, ImageSpec.dish);
      await _run(
        () => ref
            .read(repositoryProvider)
            .uploadMenuPhoto(restaurantId: restaurantId, itemId: item.id, jpeg: picked.jpeg),
        restaurantId,
        ['Zdjęcie „${item.name}” zapisane. Goście zobaczą je w aplikacji.', ?note].join(' '),
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

  static bool _matches(MenuItem item, String query) {
    final texts = [
      item.name,
      ?item.description,
      for (final v in item.variants) v.name,
      for (final a in item.addons) a.name,
      for (final a in item.allergens) allergenLabels[a] ?? a,
    ];
    return texts.any((t) => t.toLowerCase().contains(query));
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
    final sections = async.value ?? const <MenuSection>[];
    final now = DateTime.now();
    final query = _search.text.trim().toLowerCase();

    // Dania po filtrach i wyszukiwaniu, w działach po filtrach. Sama nazwa działu też trafia w wyszukiwanie.
    final groups = <_Group>[
      for (var i = 0; i < sections.length; i++)
        if ((_sectionIds.isEmpty || _sectionIds.contains(sections[i].id)) &&
            (_whens.isEmpty || _whens.contains(menuWhenOf(sections[i]))))
          if (_visibleItems(sections[i], query) case final items
              when items.isNotEmpty || (query.isEmpty && _states.isEmpty))
            _Group(sections[i], items, i),
    ];

    int items(bool Function(MenuSection s, MenuItem i) test) => [
      for (final s in sections)
        for (final i in s.items)
          if (test(s, i)) i,
    ].length;

    final panel = SidePanel(
      header: const PanelTitle(icon: AppIcons.bookOpen, title: 'Menu'),
      search: _search,
      searchHint: 'Szukaj dania',
      onSearch: () => setState(() {}),
      actions: [
        if (editable && sections.isNotEmpty)
          PanelAction(
            label: 'Dodaj pozycję',
            active: _sheet is _ItemSheetOpen && (_sheet! as _ItemSheetOpen).itemId == null,
            onTap: () => setState(
              () => _sheet = _ItemSheetOpen(sectionId: groups.isNotEmpty ? groups.first.section.id : sections.first.id),
            ),
          ),
        if (editable)
          PanelAction(
            label: 'Nowa sekcja',
            active: _sheet is _SectionSheetOpen && (_sheet! as _SectionSheetOpen).sectionId == null,
            onTap: () => setState(() => _sheet = const _SectionSheetOpen()),
          ),
      ],
      children: [
        if (sections.isNotEmpty) ...[
          FilterSection(
            title: 'Sekcja',
            first: true,
            open: !_closed.contains('section'),
            onToggle: () => _toggle(_closed, 'section'),
            options: [
              for (final s in sections)
                (
                  label: s.name,
                  count: s.items.length,
                  checked: _sectionIds.contains(s.id),
                  onChanged: (_) => _toggle(_sectionIds, s.id),
                  dot: null,
                ),
            ],
          ),
          FilterSection(
            title: 'Kiedy w menu',
            open: !_closed.contains('when'),
            onToggle: () => _toggle(_closed, 'when'),
            options: [
              for (final (w, label) in const [
                (MenuWhen.always, 'Zawsze'),
                (MenuWhen.season, 'Sezonowe'),
                (MenuWhen.event, 'Na wydarzenie'),
              ])
                (
                  label: label,
                  count: items((s, _) => menuWhenOf(s) == w),
                  checked: _whens.contains(w),
                  onChanged: (_) => _toggle(_whens, w),
                  dot: null,
                ),
            ],
          ),
          FilterSection(
            title: 'Dostępność',
            open: !_closed.contains('state'),
            onToggle: () => _toggle(_closed, 'state'),
            options: [
              for (final (key, label) in const [('on', 'Dostępne'), ('off', 'Niedostępne')])
                (
                  label: label,
                  count: items((_, i) => i.available == (key == 'on')),
                  checked: _states.contains(key),
                  onChanged: (_) => _toggle(_states, key),
                  dot: key == 'off' ? AppColors.error : null,
                ),
            ],
          ),
        ],
      ],
    );

    final content = async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(menuProvider(restaurant.id))),
      data: (_) => sections.isEmpty
          ? MessageView(
              icon: AppIcons.bookOpen,
              title: 'Menu jest puste',
              message: 'Zacznij od sekcji, na przykład „Przystawki” albo „Dania główne”.',
              actionLabel: editable ? 'Dodaj sekcję' : null,
              onAction: editable ? () => setState(() => _sheet = const _SectionSheetOpen()) : null,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!editable) const ReadOnlyBanner(message: 'Menu zmienia kierownik albo właściciel lokalu.'),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 32, 16),
                    child: _MenuTable(
                      groups: groups,
                      now: now,
                      editable: editable,
                      canToggle: canToggle,
                      selectedItem: _sheet is _ItemSheetOpen ? (_sheet! as _ItemSheetOpen).itemId : null,
                      selectedSection: _sheet is _SectionSheetOpen ? (_sheet! as _SectionSheetOpen).sectionId : null,
                      sectionCount: sections.length,
                      onOpenItem: (s, i) => setState(() => _sheet = _ItemSheetOpen(sectionId: s.id, itemId: i?.id)),
                      onOpenSection: (s) => setState(() => _sheet = _SectionSheetOpen(s.id)),
                      onMoveSection: (g, d) => _moveSection(restaurant.id, sections, g.index, d),
                      onMoveItem: (g, i, d) => _moveItem(restaurant.id, g.section, i, d),
                      onToggleAvailable: (i) => _toggleAvailable(restaurant.id, i),
                      onDeleteItem: (i) => _deleteItem(restaurant.id, i),
                    ),
                  ),
                ),
              ],
            ),
    );

    return SidePanelLayout(
      open: _panelOpen,
      onToggle: () => setState(() => _panelOpen = !_panelOpen),
      panel: panel,
      content: content,
      sheet: _buildSheet(restaurant.id, sections),
    );
  }

  /// Dania działu po filtrach: bez wyszukiwania wszystkie z dostępnością, z wyszukiwaniem te z trafieniem (albo
  /// wszystkie, gdy trafiła nazwa działu).
  List<MenuItem> _visibleItems(MenuSection s, String query) {
    final sectionHit = query.isNotEmpty && s.name.toLowerCase().contains(query);
    return [
      for (final i in s.items)
        if ((_states.isEmpty || _states.contains(i.available ? 'on' : 'off')) &&
            (query.isEmpty || sectionHit || _matches(i, query)))
          i,
    ];
  }

  Widget? _buildSheet(String restaurantId, List<MenuSection> sections) {
    final open = _sheet;
    if (open == null || sections.isEmpty && open is _ItemSheetOpen) return null;
    switch (open) {
      case _ItemSheetOpen(:final sectionId, :final itemId):
        MenuItem? item;
        if (itemId != null) {
          for (final s in sections) {
            for (final i in s.items) {
              if (i.id == itemId) item = i;
            }
          }
          if (item == null) return null;
        }
        return SizedBox(
          key: ValueKey('pozycja ${itemId ?? 'nowa'}'),
          width: sideSheetWidth,
          child: _ItemSheet(
            key: ValueKey('pozycja-okno ${itemId ?? 'nowa'}'),
            restaurantId: restaurantId,
            sections: sections,
            sectionId: sectionId,
            item: item,
            onClose: () => setState(() => _sheet = null),
            onSaved: (message) => _afterSave(restaurantId, message),
            onDelete: item == null ? null : () => _deleteItem(restaurantId, item!),
            onPhoto: item == null || _busy ? null : () => _photo(restaurantId, item!),
            onRemovePhoto: item == null || _busy ? null : () => _removePhoto(restaurantId, item!),
          ),
        );
      case _SectionSheetOpen(:final sectionId):
        MenuSection? section;
        if (sectionId != null) {
          section = sections.where((s) => s.id == sectionId).firstOrNull;
          if (section == null) return null;
        }
        return SizedBox(
          key: ValueKey('sekcja ${sectionId ?? 'nowa'}'),
          width: sideSheetWidth,
          child: _SectionSheet(
            key: ValueKey('sekcja-okno ${sectionId ?? 'nowa'}'),
            restaurantId: restaurantId,
            section: section,
            position: sections.length,
            onClose: () => setState(() => _sheet = null),
            onSaved: (message) => _afterSave(restaurantId, message),
            onDelete: section == null ? null : () => _deleteSection(restaurantId, section!),
          ),
        );
    }
  }
}

/// „4 lis 18:00 – 6 lis 23:00” dla działu na wydarzenie.
String sectionEventRange(DateTime start, DateTime end) {
  const months = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];
  String two(int n) => n.toString().padLeft(2, '0');
  String at(DateTime t) => '${t.toLocal().day} ${months[t.toLocal().month - 1]} ${two(t.toLocal().hour)}:${two(t.toLocal().minute)}';
  return '${at(start)} – ${at(end)}';
}

String _positions(int n) {
  if (n == 1) return '1 pozycja';
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n pozycje';
  return '$n pozycji';
}

/// Kiedy dział jest w menu, do pokazania przy nim: okres sezonu ze stanem albo wydarzenie. Null przy zwykłym dziale.
Widget? _whenChip(MenuSection s, DateTime now) {
  if (s.season case final season?) {
    final active = season.contains(now);
    return StatusChip(
      label: '${season.statusAt(now)} · ${season.label}',
      icon: active ? AppIcons.calendarCheck : AppIcons.calendarX,
      color: active ? AppColors.accent : AppColors.textMuted,
    );
  }
  if (s.eventId != null) {
    final starts = s.eventStarts;
    final ends = s.eventEnds;
    final active = starts != null && ends != null && !now.isBefore(starts) && now.isBefore(ends);
    return StatusChip(
      label: 'Tylko na: ${s.eventTitle ?? 'wydarzenie'}'
          '${starts == null || ends == null ? '' : ' · ${sectionEventRange(starts, ends)}'}',
      icon: AppIcons.confetti,
      color: active ? AppColors.accent : AppColors.textMuted,
    );
  }
  return null;
}

/// Dania jako tabela pogrupowana w sekcje, jak Zespół w Pracownikach.
class _MenuTable extends StatelessWidget {
  const _MenuTable({
    required this.groups,
    required this.now,
    required this.editable,
    required this.canToggle,
    required this.selectedItem,
    required this.selectedSection,
    required this.sectionCount,
    required this.onOpenItem,
    required this.onOpenSection,
    required this.onMoveSection,
    required this.onMoveItem,
    required this.onToggleAvailable,
    required this.onDeleteItem,
  });

  final List<_Group> groups;
  final DateTime now;
  final bool editable;
  final bool canToggle;
  final String? selectedItem;
  final String? selectedSection;
  final int sectionCount;

  /// Dział i danie (null: nowe danie w tym dziale).
  final void Function(MenuSection section, MenuItem? item) onOpenItem;
  final ValueChanged<MenuSection> onOpenSection;
  final void Function(_Group group, int delta) onMoveSection;
  final void Function(_Group group, int index, int delta) onMoveItem;
  final ValueChanged<MenuItem> onToggleAvailable;
  final ValueChanged<MenuItem> onDeleteItem;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                tableHead(context, 'Pozycja', 4),
                tableHead(context, 'Opcje i alergeny', 4),
                tableHead(context, 'Cena', 0, width: _priceWidth, align: TextAlign.right),
                const SizedBox(width: 16),
                tableHead(context, 'Stan', 0, width: _stateWidth),
                if (editable) const SizedBox(width: _actionsWidth),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.ring),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Text(
                    'Nic nie znaleziono. Zmień wyszukiwanie albo filtry po lewej.',
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                )
              : ListView(
                  children: [
                    for (final g in groups) ...[
                      _GroupHeader(
                        group: g,
                        now: now,
                        editable: editable,
                        selected: selectedSection == g.section.id,
                        isFirst: g.index == 0,
                        isLast: g.index == sectionCount - 1,
                        onEdit: () => onOpenSection(g.section),
                        onAdd: () => onOpenItem(g.section, null),
                        onMove: (d) => onMoveSection(g, d),
                      ),
                      if (g.items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                          child: Text(
                            editable ? 'Brak pozycji. Dodaj pierwsze danie w tej sekcji.' : 'W tej sekcji nie ma jeszcze dań.',
                            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                          ),
                        ),
                      for (var i = 0; i < g.items.length; i++) ...[
                        _ItemRow(
                          item: g.items[i],
                          editable: editable,
                          canToggle: canToggle,
                          selected: selectedItem == g.items[i].id,
                          // Zmiana kolejności liczy się w całym dziale, nie w widoku po filtrach.
                          onUp: g.section.items.indexOf(g.items[i]) <= 0
                              ? null
                              : () => onMoveItem(g, g.section.items.indexOf(g.items[i]), -1),
                          onDown: g.section.items.indexOf(g.items[i]) >= g.section.items.length - 1
                              ? null
                              : () => onMoveItem(g, g.section.items.indexOf(g.items[i]), 1),
                          onTap: editable ? () => onOpenItem(g.section, g.items[i]) : null,
                          onToggleAvailable: () => onToggleAvailable(g.items[i]),
                          onDelete: () => onDeleteItem(g.items[i]),
                        ),
                        Divider(height: 1, color: AppColors.ring),
                      ],
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// Nagłówek sekcji w tabeli: nazwa, liczba dań, kiedy jest w menu i przyciski (dodaj danie, zmień, wyżej, niżej).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.now,
    required this.editable,
    required this.selected,
    required this.isFirst,
    required this.isLast,
    required this.onEdit,
    required this.onAdd,
    required this.onMove,
  });

  final _Group group;
  final DateTime now;
  final bool editable;
  final bool selected;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback onAdd;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final chip = _whenChip(group.section, now);
    return Container(
      color: selected ? AppColors.accentTint : AppColors.surfaceRaised,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(group.section.name, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  _positions(group.section.items.length),
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
                ?chip,
              ],
            ),
          ),
          if (editable) ...[
            IconButton(
              tooltip: 'Dodaj pozycję w tej sekcji',
              icon: const Glyph(AppIcons.plus, size: 16),
              onPressed: onAdd,
            ),
            IconButton(
              tooltip: 'Zmień sekcję',
              icon: const Glyph(AppIcons.pencil, size: 16),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Przesuń sekcję wyżej',
              icon: const Glyph(AppIcons.caretUp, size: 14),
              onPressed: isFirst ? null : () => onMove(-1),
            ),
            IconButton(
              tooltip: 'Przesuń sekcję niżej',
              icon: const Glyph(AppIcons.caretDown, size: 14),
              onPressed: isLast ? null : () => onMove(1),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  const _ItemRow({
    required this.item,
    required this.editable,
    required this.canToggle,
    required this.selected,
    required this.onUp,
    required this.onDown,
    required this.onTap,
    required this.onToggleAvailable,
    required this.onDelete,
  });

  final MenuItem item;
  final bool editable;

  /// Brak uprawnienia „Dostępność dań”: stan tylko do odczytu.
  final bool canToggle;
  final bool selected;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onTap;
  final VoidCallback onToggleAvailable;
  final VoidCallback onDelete;

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
    final options = [
      for (final v in item.variants) '${v.name} ${Fmt.price(v.priceGrosze)}',
      if (item.addons.isNotEmpty) 'dodatki: ${item.addons.map((a) => a.name.toLowerCase()).join(', ')}',
    ].join(' · ');
    final state = StatusChip(
      label: item.available ? 'Dostępne' : 'Niedostępne',
      icon: item.available ? AppIcons.checkCircle : AppIcons.eyeSlash,
      color: item.available ? AppColors.accent : AppColors.error,
    );

    return Material(
      color: selected ? AppColors.accentTint : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.surfaceRaised,
        splashColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Thumb(url: item.photoUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: item.available ? null : AppColors.textMuted,
                            ),
                          ),
                          if (item.description != null)
                            Text(
                              item.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (options.isNotEmpty)
                        Text(
                          options,
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                      if (recipe.isNotEmpty) ...[
                        if (options.isNotEmpty) const SizedBox(height: 4),
                        Row(
                          children: [
                            Glyph(AppIcons.package, size: 13, color: AppColors.textMuted),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                recipe.join(', '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (item.allergens.isNotEmpty) ...[
                        if (options.isNotEmpty || recipe.isNotEmpty) const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [for (final a in item.allergens) Tag((allergenLabels[a] ?? a).toUpperCase())],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: _priceWidth,
                child: Text(
                  item.priceVaries ? 'od ${Fmt.price(item.fromPrice)}' : Fmt.price(item.fromPrice),
                  textAlign: TextAlign.right,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontFeatures: _tabular),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: _stateWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: canToggle
                      ? Tooltip(
                          message: item.available ? 'Skończyło się: oznacz jako niedostępne' : 'Znowu dostępne',
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(onTap: onToggleAvailable, child: state),
                          ),
                        )
                      : state,
                ),
              ),
              if (editable)
                SizedBox(
                  width: _actionsWidth,
                  child: PopupMenuButton<String>(
                    tooltip: 'Więcej',
                    padding: EdgeInsets.zero,
                    icon: Glyph(AppIcons.dotsVertical, size: 16, color: AppColors.textMuted),
                    onSelected: (v) => switch (v) {
                      'edit' => onTap?.call(),
                      'up' => onUp?.call(),
                      'down' => onDown?.call(),
                      _ => onDelete(),
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edytuj')),
                      PopupMenuItem(value: 'up', enabled: onUp != null, child: const Text('Przesuń wyżej')),
                      PopupMenuItem(value: 'down', enabled: onDown != null, child: const Text('Przesuń niżej')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Usuń', style: TextStyle(color: AppColors.error)),
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

/// Miniatura zdjęcia dania w wierszu tabeli. Bez zdjęcia: ikona dania.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 44,
        color: AppColors.surfaceRaised,
        child: url == null
            ? Center(child: Glyph(AppIcons.forkKnife, size: 18, color: AppColors.textMuted))
            : Image.network(
                url!,
                fit: BoxFit.cover,
                cacheWidth: 96,
                errorBuilder: (_, _, _) => Center(child: Glyph(AppIcons.warning, size: 16, color: AppColors.textMuted)),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Okno sekcji
// ---------------------------------------------------------------------------------------------------------------

/// Okno nowej albo zmienianej sekcji: nazwa i to, kiedy sekcja jest w menu (zawsze, w okresie albo tylko na
/// wydarzenie).
class _SectionSheet extends ConsumerStatefulWidget {
  const _SectionSheet({
    super.key,
    required this.restaurantId,
    required this.section,
    required this.position,
    required this.onClose,
    required this.onSaved,
    required this.onDelete,
  });

  final String restaurantId;

  /// Null: nowa sekcja.
  final MenuSection? section;

  /// Miejsce nowej sekcji (na końcu).
  final int position;
  final VoidCallback onClose;
  final ValueChanged<String> onSaved;
  final VoidCallback? onDelete;

  @override
  ConsumerState<_SectionSheet> createState() => _SectionSheetState();
}

class _SectionSheetState extends ConsumerState<_SectionSheet> {
  late final _name = TextEditingController(text: widget.section?.name ?? '');
  late MenuWhen _when = widget.section == null ? MenuWhen.always : menuWhenOf(widget.section!);
  late DateTime _from = widget.section?.season?.from ?? _today();
  late DateTime _to = widget.section?.season?.to ?? _today().add(const Duration(days: 90));
  late bool _yearly = widget.section?.season?.yearly ?? false;
  late String? _eventId = widget.section?.eventId;
  late final DateTime _eventsFrom = _today().subtract(const Duration(days: 1));
  bool _busy = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  MenuSeason get _season => MenuSeason(from: _from, to: _to, yearly: _yearly);

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final day = DateTime(picked.year, picked.month, picked.day);
      if (start) {
        // Przesunięcie początku przesuwa koniec o tyle samo, żeby okres się nie odwracał.
        final length = _to.difference(_from);
        _from = day;
        if (!_yearly) _to = _from.add(length.isNegative ? Duration.zero : length);
      } else {
        _to = day;
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, 'Wpisz nazwę sekcji.', tone: ToastTone.warning);
      return;
    }
    if (_when == MenuWhen.season && !_yearly && _to.isBefore(_from)) {
      showMessage(context, 'Koniec okresu jest przed jego początkiem.', tone: ToastTone.warning);
      return;
    }
    if (_when == MenuWhen.event && _eventId == null) {
      showMessage(context, 'Wybierz wydarzenie z Kalendarza.', tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .saveSection(
            id: widget.section?.id,
            restaurantId: widget.restaurantId,
            name: name,
            position: widget.position,
            eventId: _when == MenuWhen.event ? _eventId : null,
            season: _when == MenuWhen.season ? _season : null,
          );
      widget.onSaved(widget.section == null ? 'Sekcja dodana.' : 'Sekcja zapisana.');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isNew = widget.section == null;
    final events = _when == MenuWhen.event
        ? ref
                  .watch(
                    calendarEventsProvider((
                      restaurantId: widget.restaurantId,
                      from: _eventsFrom,
                      to: _eventsFrom.add(const Duration(days: 400)),
                    )),
                  )
                  .value ??
              const <CalendarEvent>[]
        : const <CalendarEvent>[];
    final specials = [for (final e in events) if (e.kind == CalendarKind.special) e];

    Widget dateRow(String label, DateTime value, {required bool start}) {
      return Row(
        children: [
          SizedBox(width: 48, child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.textMuted))),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _pickDate(start: start),
              child: Text(
                _yearly ? '${value.day} ${_monthName(value.month)}' : '${value.day} ${_monthName(value.month)} ${value.year}',
                style: const TextStyle(fontFeatures: _tabular),
              ),
            ),
          ),
        ],
      );
    }

    return SideSheetFrame(
      title: isNew ? 'Nowa sekcja' : 'Sekcja: ${widget.section!.name}',
      onClose: widget.onClose,
      footer: Row(
        children: [
          if (widget.onDelete != null) ...[
            TextButton(
              onPressed: _busy ? null : widget.onDelete,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Usuń'),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              child: Text(isNew ? 'Dodaj sekcję' : 'Zapisz'),
            ),
          ),
        ],
      ),
      children: [
        SheetField(
          label: 'Nazwa',
          child: TextField(
            controller: _name,
            autofocus: isNew,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: sheetInput(hint: 'Na przykład: Menu letnie'),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(height: 24),
        const SheetHeading('Kiedy w menu'),
        const SizedBox(height: 10),
        CardGrid(
          children: [
            ChoiceCard(
              icon: AppIcons.bookOpen,
              title: 'Zawsze',
              selected: _when == MenuWhen.always,
              onTap: () => setState(() => _when = MenuWhen.always),
            ),
            ChoiceCard(
              icon: AppIcons.calendarDots,
              title: 'Sezon',
              selected: _when == MenuWhen.season,
              onTap: () => setState(() => _when = MenuWhen.season),
            ),
            ChoiceCard(
              icon: AppIcons.confetti,
              title: 'Wydarzenie',
              selected: _when == MenuWhen.event,
              onTap: () => setState(() => _when = MenuWhen.event),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          switch (_when) {
            MenuWhen.always => 'Sekcja jest w menu cały czas.',
            MenuWhen.season =>
              'Sekcja jest w menu tylko w wybranym okresie. Poza nim znika u gości, w Zamówieniach i u kelnera.',
            MenuWhen.event => 'Sekcja jest w menu tylko w czasie wybranego wydarzenia z Kalendarza.',
          },
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        if (_when == MenuWhen.season) ...[
          const SizedBox(height: 24),
          const SheetHeading('Okres'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in menuSeasonPresets)
                ChoiceChip(
                  label: Text(
                    p.name,
                    style: TextStyle(color: _season == p.season() ? AppColors.onAccent : AppColors.text),
                  ),
                  selected: _season == p.season(),
                  onSelected: (_) => setState(() {
                    final s = p.season();
                    _from = s.from;
                    _to = s.to;
                    _yearly = true;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          dateRow('Od', _from, start: true),
          const SizedBox(height: 8),
          dateRow('Do', _to, start: false),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('Powtarzaj co roku', style: text.bodyMedium)),
              Switch(value: _yearly, onChanged: (v) => setState(() => _yearly = v)),
            ],
          ),
          Text(
            _yearly
                ? 'Liczy się miesiąc i dzień, rok nie ma znaczenia. Okres może przechodzić przez Nowy Rok.'
                : 'Jednorazowo: od pierwszego do ostatniego dnia włącznie.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          Text(
            '${_season.label} · ${_season.statusAt(DateTime.now())}',
            style: text.labelLarge?.copyWith(color: AppColors.accent),
          ),
        ],
        if (_when == MenuWhen.event) ...[
          const SizedBox(height: 24),
          const SheetHeading('Wydarzenie'),
          const SizedBox(height: 8),
          if (specials.isEmpty && widget.section?.eventId == null)
            Text(
              'Nie ma jeszcze wydarzeń dla gości. Dodaj je w Management → Kalendarz.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          // Wydarzenie przypięte do sekcji, które wypadło z listy (minęło dawno), zostaje do wyboru.
          if (widget.section?.eventId case final current? when !specials.any((e) => e.id == current))
            _EventChoice(
              title: widget.section!.eventTitle ?? 'Wydarzenie',
              range: widget.section!.eventStarts == null || widget.section!.eventEnds == null
                  ? ''
                  : sectionEventRange(widget.section!.eventStarts!, widget.section!.eventEnds!),
              color: AppColors.textMuted,
              selected: _eventId == current,
              onTap: () => setState(() => _eventId = current),
            ),
          for (final e in specials)
            _EventChoice(
              title: e.title,
              range: sectionEventRange(e.startsAt, e.endsAt),
              color: e.color.color,
              selected: _eventId == e.id,
              onTap: () => setState(() => _eventId = e.id),
            ),
        ],
      ],
    );
  }
}

const _monthNames = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];

String _monthName(int month) => _monthNames[month - 1];

/// Jedno wydarzenie do wyboru w oknie sekcji: kolor, nazwa, termin i zaznaczenie.
class _EventChoice extends StatelessWidget {
  const _EventChoice({
    required this.title,
    required this.range,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String range;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Glyph(selected ? AppIcons.checkCircle : AppIcons.circle, size: 18, color: selected ? AppColors.accent : color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.bodyMedium),
                  if (range.isNotEmpty) Text(range, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Okno dania
// ---------------------------------------------------------------------------------------------------------------

/// Okno nowego albo zmienianego dania: nazwa, sekcja, cena, opis, warianty, dodatki, receptura, VAT, dostępność,
/// alergeny i zdjęcie.
class _ItemSheet extends ConsumerStatefulWidget {
  const _ItemSheet({
    super.key,
    required this.restaurantId,
    required this.sections,
    required this.sectionId,
    required this.item,
    required this.onClose,
    required this.onSaved,
    required this.onDelete,
    required this.onPhoto,
    required this.onRemovePhoto,
  });

  final String restaurantId;
  final List<MenuSection> sections;
  final String sectionId;

  /// Null: nowe danie.
  final MenuItem? item;
  final VoidCallback onClose;
  final ValueChanged<String> onSaved;
  final VoidCallback? onDelete;
  final VoidCallback? onPhoto;
  final VoidCallback? onRemovePhoto;

  @override
  ConsumerState<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<_ItemSheet> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _description = TextEditingController(text: widget.item?.description ?? '');
  late final _price = TextEditingController(
    text: widget.item == null ? '' : groszeToText(widget.item!.priceGrosze),
  );
  late final Set<String> _allergens = {...?widget.item?.allergens};
  late final _variants = [for (final v in widget.item?.variants ?? const <MenuOption>[]) _OptionRow(v)];
  late final _addons = [for (final a in widget.item?.addons ?? const <MenuOption>[]) _OptionRow(a)];
  late final _recipe = [for (final r in widget.item?.ingredients ?? const <RecipeLine>[]) _RecipeRow(r)];
  late String _sectionId = widget.sectionId;
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
    final section = widget.sections.firstWhere((s) => s.id == _sectionId, orElse: () => widget.sections.first);
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      final moved = widget.item != null && widget.item!.sectionId != section.id;
      final id = await repo.saveItem(
        id: widget.item?.id,
        sectionId: section.id,
        name: _name.text,
        description: _description.text,
        priceGrosze: price,
        allergens: _allergens.toList(),
        // Danie przeniesione do innej sekcji trafia na jej koniec.
        position: widget.item == null || moved ? section.items.length : widget.item!.position,
        variants: variants,
        addons: addons,
        vatRate: _vat,
        available: _available,
        showInKitchen: _showInKitchen,
      );
      if (!_sameRecipe(recipe)) await repo.setMenuItemIngredients(id, recipe);
      widget.onSaved(widget.item == null ? 'Pozycja dodana.' : 'Pozycja zapisana.');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  Widget _switchRow(String title, String hint, bool value, ValueChanged<bool> onChanged) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleSmall),
              Text(hint, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isNew = widget.item == null;
    final sectionName = widget.sections.where((s) => s.id == _sectionId).firstOrNull?.name ?? '';
    return SideSheetFrame(
      title: isNew ? 'Nowa pozycja' : 'Edytuj pozycję',
      onClose: widget.onClose,
      footer: Row(
        children: [
          if (widget.onDelete != null) ...[
            TextButton(
              onPressed: _busy ? null : widget.onDelete,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Usuń'),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              child: Text(isNew ? 'Dodaj pozycję' : 'Zapisz'),
            ),
          ),
        ],
      ),
      children: [
        SheetField(
          label: 'Nazwa',
          child: TextField(
            controller: _name,
            autofocus: isNew,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: sheetInput(hint: 'Na przykład: Pierogi ruskie'),
          ),
        ),
        const SizedBox(height: 16),
        SheetField(
          label: 'Sekcja',
          child: PanelSelect<String>(
            key: ValueKey('sekcja-$sectionName'),
            initialValue: widget.sections.any((s) => s.id == _sectionId) ? _sectionId : null,
            decoration: sheetInput(),
            items: [
              for (final s in widget.sections)
                DropdownMenuItem(value: s.id, child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (id) => setState(() => _sectionId = id ?? _sectionId),
          ),
        ),
        const SizedBox(height: 16),
        SheetField(
          label: 'Cena',
          child: _variants.isEmpty
              ? TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  decoration: sheetInput(hint: '0', suffix: 'zł'),
                )
              // Przy wariantach cenę ma każdy wariant osobno.
              : TextField(enabled: false, decoration: sheetInput(hint: 'z wariantów')),
        ),
        const SizedBox(height: 16),
        SheetField(
          label: 'Opis (opcjonalnie)',
          child: TextField(
            controller: _description,
            maxLength: 200,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: sheetInput(),
          ),
        ),
        const SizedBox(height: 24),
        _OptionsEditor(
          title: 'Warianty',
          hint: 'Np. rozmiary: Mała 25 zł, Duża 39 zł. Gość i kelner wybierają jeden.',
          addLabel: 'Dodaj',
          namePlaceholder: 'Duża',
          rows: _variants,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 20),
        _OptionsEditor(
          title: 'Dodatki',
          hint: 'Płatne dodatki doliczane do ceny, np. „Ser +4 zł”. Można wybrać kilka.',
          addLabel: 'Dodaj',
          namePlaceholder: 'Ser',
          rows: _addons,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 20),
        _RecipeEditor(
          items: ref.watch(inventoryItemsProvider(widget.restaurantId)).value ?? const [],
          rows: _recipe,
          onChanged: () => setState(() {}),
          onNew: _newIngredient,
        ),
        const SizedBox(height: 24),
        const SheetHeading('Stawka VAT'),
        const SizedBox(height: 4),
        Text('8% jedzenie na miejscu, 23% alkohol', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedTabs<int>(
            options: [for (final r in vatRates) (r, '$r%')],
            selected: _vat,
            onChanged: (v) => setState(() => _vat = v),
          ),
        ),
        const SizedBox(height: 20),
        _switchRow(
          'Dostępne teraz',
          'Wyłącz, gdy danie się skończy. Goście zobaczą je jako niedostępne.',
          _available,
          (v) => setState(() => _available = v),
        ),
        const SizedBox(height: 14),
        _switchRow(
          'Pokazuj na kuchni',
          'Wyłącz dla pozycji, których kuchnia nie robi, np. napojów z baru.',
          _showInKitchen,
          (v) => setState(() => _showInKitchen = v),
        ),
        const SizedBox(height: 24),
        const SheetHeading('Alergeny'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in allergenLabels.entries)
              FilterChip(
                selected: _allergens.contains(e.key),
                onSelected: (v) => setState(() => v ? _allergens.add(e.key) : _allergens.remove(e.key)),
                label: Text(
                  e.value,
                  style: TextStyle(color: _allergens.contains(e.key) ? AppColors.onAccent : AppColors.text),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const SheetHeading('Zdjęcie', optional: true),
        const SizedBox(height: 6),
        // Dokładny rozmiar (27.11.2026, prośba użytkownika): jeden plik na wszystkie urządzenia.
        Text(
          'Wymiary: ${ImageSpec.dish.label}, JPG, PNG albo WEBP. Tak duże jest zdjęcie po powiększeniu w menu, '
          'w miniaturach aplikacja tylko je zmniejsza. Plik o innych wymiarach panel przytnie od środka do kwadratu '
          'i dopasuje rozmiar.',
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        if (isNew)
          Text(
            'Zdjęcie dodasz po zapisaniu dania. Goście zobaczą je w aplikacji.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          )
        else
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 72,
                  height: 72,
                  color: AppColors.surfaceRaised,
                  child: widget.item!.photoUrl == null
                      ? Center(child: Glyph(AppIcons.image, size: 22, color: AppColors.textMuted))
                      : Image.network(
                          widget.item!.photoUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: 144,
                          errorBuilder: (_, _, _) =>
                              Center(child: Glyph(AppIcons.warning, size: 18, color: AppColors.textMuted)),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton(
                      onPressed: widget.onPhoto,
                      child: Text(widget.item!.photoUrl == null ? 'Dodaj zdjęcie' : 'Zmień zdjęcie'),
                    ),
                    if (widget.item!.photoUrl != null)
                      TextButton(
                        onPressed: widget.onRemovePhoto,
                        style: TextButton.styleFrom(foregroundColor: AppColors.error),
                        child: const Text('Usuń zdjęcie'),
                      ),
                  ],
                ),
              ),
            ],
          ),
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
/// w Inwentaryzacji. Goście w aplikacji tego nie widzą. W wąskim oknie każdy wiersz ma dwie linie:
/// składnik, a pod nim ilość i jednostka.
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
          const SizedBox(height: 10),
          Column(
            key: ObjectKey(row),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: PanelSelect<String>(
                      // Klucz ze składnikiem: wybór wstawiony z „Nowy składnik” odświeża pole.
                      key: ValueKey('${identityHashCode(row)}-${row.itemId}'),
                      initialValue: byId.containsKey(row.itemId) ? row.itemId : null,
                      hint: const Text('Wybierz składnik'),
                      decoration: sheetInput(),
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
                  IconButton(
                    tooltip: 'Usuń',
                    icon: const Glyph(AppIcons.close, size: 16),
                    onPressed: () {
                      rows.remove(row);
                      onChanged();
                      WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: row.amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                      decoration: sheetInput(hint: 'Ilość na porcję'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 104,
                    child: switch (byId[row.itemId]) {
                      final item? when item.unit.compatible.length > 1 => PanelSelect<InventoryUnit>(
                        key: ValueKey('${row.itemId}-unit'),
                        initialValue: row.unit ?? item.unit.portion,
                        decoration: sheetInput(),
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
                  const SizedBox(width: 40),
                ],
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
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onNew,
            icon: const Glyph(AppIcons.package, size: 14),
            label: const Text('Nowy składnik'),
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
                  decoration: sheetInput(hint: namePlaceholder),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 104,
                child: TextField(
                  controller: row.price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  decoration: sheetInput(hint: '0', suffix: 'zł'),
                ),
              ),
              IconButton(
                tooltip: 'Usuń',
                icon: const Glyph(AppIcons.close, size: 16),
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
