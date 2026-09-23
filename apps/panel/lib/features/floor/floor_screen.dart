import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../reservations/reservations_screen.dart' show StatusPill;
import 'floor_canvas.dart';

const _tabular = [FontFeature.tabularFigures()];

enum _Mode { live, edit }

/// Czy w Edycji sali są niezapisane zmiany. Czyta to router przy wyjściu z sekcji.
bool _floorUnsaved = false;

/// Pyta o odrzucenie zmian, gdy obsługa wychodzi z Edycji sali bez zapisu.
Future<bool> confirmLeaveFloor(BuildContext context) async {
  if (!_floorUnsaved) return true;
  final ok = await confirm(
    context,
    title: 'Wyjść bez zapisu?',
    message: 'Układ sali ma niezapisane zmiany. Po wyjściu przepadną.',
    action: 'Wyjdź bez zapisu',
    destructive: true,
  );
  if (ok) _floorUnsaved = false;
  return ok;
}

class FloorScreen extends ConsumerStatefulWidget {
  const FloorScreen({super.key});

  @override
  ConsumerState<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends ConsumerState<FloorScreen> {
  _Mode _mode = _Mode.live;
  String? _zoneName;
  String? _selectedKey;

  // Podgląd na żywo: godzina, dla której pokazujemy zajętość.
  DateTime _now = DateTime.now();
  int? _minuteOfDay;
  Timer? _clock;

  // Edycja: kopia robocza układu.
  List<FloorZone> _zones = [];
  List<DiningTable> _tables = [];
  List<FloorElement> _elements = [];
  final List<String> _deletedTables = [];
  final List<String> _deletedElements = [];
  final List<String> _deletedZones = [];
  bool _dirty = false;
  bool _saving = false;

  // Schowek edytora: skopiowany stolik, miejsce albo element stały.
  Object? _clipboard;

  // Skróty kopiowania działają, gdy fokus jest na planie, a nie w polu tekstowym.
  final _canvasFocus = FocusNode(debugLabel: 'plan sali');

  // Pozycja kursora przy przeciąganiu krzesła, zanim krzesło przyciągnie się do stolika.
  Offset? _chairRaw;

  // Historia zmian do cofania (Ctrl+Z). Każdy wpis to stan układu sprzed zmiany.
  final List<_Snapshot> _history = [];
  String? _lastAction;
  DateTime _lastActionAt = DateTime(0);

  // Zmienia się po cofnięciu, żeby panele boczne wczytały pola od nowa.
  int _undoGeneration = 0;

  /// Zapamiętuje stan przed zmianą. Szybkie zmiany tego samego elementu,
  /// na przykład przeciąganie albo pisanie numeru, tworzą jeden krok.
  void _remember([String? action]) {
    final now = DateTime.now();
    final sameGesture = action != null &&
        action == _lastAction &&
        now.difference(_lastActionAt) < const Duration(milliseconds: 800);
    _lastAction = action;
    _lastActionAt = now;
    if (sameGesture) return;
    _history.add(_Snapshot(
      zones: _zones,
      tables: _tables,
      elements: _elements,
      deletedTables: [..._deletedTables],
      deletedElements: [..._deletedElements],
      deletedZones: [..._deletedZones],
      dirty: _dirty,
      zoneName: _zoneName,
    ));
    if (_history.length > 100) _history.removeAt(0);
  }

  void _undo() {
    if (_mode != _Mode.edit || _history.isEmpty) return;
    final s = _history.removeLast();
    setState(() {
      _zones = s.zones;
      _tables = s.tables;
      _elements = s.elements;
      _deletedTables
        ..clear()
        ..addAll(s.deletedTables);
      _deletedElements
        ..clear()
        ..addAll(s.deletedElements);
      _deletedZones
        ..clear()
        ..addAll(s.deletedZones);
      _dirty = s.dirty;
      _zoneName = s.zoneName;
      _lastAction = null;
      _undoGeneration++;
      final key = _selectedKey;
      if (key != null &&
          !_tables.any((t) => FloorCanvas.keyOf(t) == key) &&
          !_elements.any((e) => e.key == key)) {
        _selectedKey = null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _floorUnsaved = false;
    _clock?.cancel();
    _canvasFocus.dispose();
    super.dispose();
  }

  DateTime get _viewTime {
    final m = _minuteOfDay;
    if (m == null) return _now;
    final d = dateOnly(_now);
    return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
  }

  void _startEditing(
    List<FloorZone> zones,
    List<DiningTable> tables,
    List<FloorElement> elements,
  ) {
    final all = orderedZones(zones, tables);
    setState(() {
      _zones = all;
      _tables = [...tables];
      _elements = [...elements];
      _deletedTables.clear();
      _deletedElements.clear();
      _deletedZones.clear();
      _history.clear();
      _lastAction = null;
      _dirty = false;
      _mode = _Mode.edit;
      _selectedKey = null;
    });
  }

  Future<void> _stopEditing() async {
    if (_dirty) {
      final ok = await confirm(
        context,
        title: 'Odrzucić zmiany?',
        message: 'Niezapisane zmiany w układzie sali zostaną utracone.',
        action: 'Odrzuć',
        destructive: true,
      );
      if (!ok) return;
    }
    setState(() {
      _mode = _Mode.live;
      _dirty = false;
      _selectedKey = null;
      _history.clear();
    });
  }

  void _update(DiningTable table, DiningTable Function(DiningTable) change) {
    final key = FloorCanvas.keyOf(table);
    _remember('stolik-$key');
    setState(() {
      _tables = [
        for (final t in _tables)
          if (FloorCanvas.keyOf(t) == key) _selectAfter(change(t)) else t,
      ];
      _dirty = true;
    });
  }

  DiningTable _selectAfter(DiningTable t) {
    _selectedKey = FloorCanvas.keyOf(t);
    return t;
  }

  void _addTable(FloorZone zone, {bool seat = false}) {
    var n = seat ? 1 : _tables.length + 1;
    String label() => seat ? 'M$n' : 'S$n';
    while (_tables.any((t) => t.label == label())) {
      n++;
    }
    final table = DiningTable(
      id: null,
      draftKey: 'nowy-${DateTime.now().microsecondsSinceEpoch}',
      label: label(),
      kind: seat ? TableKind.seat : TableKind.table,
      seats: seat ? 1 : 4,
      widthCm: seat ? 45 : 120,
      heightCm: seat ? 45 : 80,
      zone: zone.name,
      priority: 0,
      active: true,
      xCm: zone.widthCm ~/ 2,
      yCm: zone.heightCm ~/ 2,
      rotation: 0,
      shape: seat ? TableShape.round : TableShape.rect,
    );
    _remember();
    setState(() {
      _tables = [..._tables, table];
      _selectedKey = FloorCanvas.keyOf(table);
      _dirty = true;
    });
  }

  void _addElement(FloorZone zone) {
    final element = FloorElement(
      id: null,
      draftKey: 'element-${DateTime.now().microsecondsSinceEpoch}',
      zone: zone.name,
      xCm: zone.widthCm ~/ 2,
      yCm: zone.heightCm ~/ 2,
      widthCm: 200,
      heightCm: 60,
      rotation: 0,
      shape: TableShape.rect,
    );
    _remember();
    setState(() {
      _elements = [..._elements, element];
      _selectedKey = element.key;
      _dirty = true;
    });
  }

  void _updateElement(FloorElement element, FloorElement Function(FloorElement) change) {
    _remember('element-${element.key}');
    setState(() {
      _elements = [
        for (final e in _elements)
          if (e.key == element.key) change(e) else e,
      ];
      _selectedKey = element.key;
      _dirty = true;
    });
  }

  void _deleteElement(FloorElement element) {
    _remember();
    setState(() {
      _elements = _elements.where((e) => e.key != element.key).toList();
      if (element.id != null) _deletedElements.add(element.id!);
      _selectedKey = null;
      _dirty = true;
    });
  }

  /// Przesuwa jedno krzesło. Przy pierwszej zmianie automatyczne rozstawienie staje się własnym.
  /// Krzesło nie odjedzie od stolika: zostaje w pasie wokół blatu.
  void _dragChair(DiningTable table, int index, Offset deltaCm) {
    _update(table, (t) {
      final chairs = [...chairsOf(t)];
      if (index >= chairs.length) return t;
      final raw = (_chairRaw ?? Offset(chairs[index].x, chairs[index].y)) + deltaCm;
      _chairRaw = raw;
      chairs[index] = attachChair(t, ChairPos(raw.dx, raw.dy));
      return t.copyWith(chairs: chairs);
    });
  }

  Object? _selectedItem() {
    for (final t in _tables) {
      if (FloorCanvas.keyOf(t) == _selectedKey) return t;
    }
    for (final e in _elements) {
      if (e.key == _selectedKey) return e;
    }
    return null;
  }

  void _copy() {
    final item = _selectedItem();
    if (item == null) return;
    _clipboard = item;
    showMessage(context, 'Skopiowano. Wklej skrótem Ctrl+V.');
  }

  /// Wstawia kopię stolika, miejsca albo elementu 50 cm obok oryginału.
  void _paste(Object? item, FloorZone zone) {
    if (item == null) return;
    _remember();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    int cx(int x) => (x + 50).clamp(0, zone.widthCm);
    int cy(int y) => (y + 50).clamp(0, zone.heightCm);

    if (item is DiningTable) {
      final prefix = item.isSeat ? 'M' : 'S';
      var n = item.isSeat ? 1 : _tables.length + 1;
      while (_tables.any((t) => t.label == '$prefix$n')) {
        n++;
      }
      final copy = DiningTable(
        id: null,
        draftKey: 'kopia-$stamp',
        label: '$prefix$n',
        kind: item.kind,
        seats: item.seats,
        widthCm: item.widthCm,
        heightCm: item.heightCm,
        zone: zone.name,
        priority: item.priority,
        active: item.active,
        xCm: cx(item.xCm),
        yCm: cy(item.yCm),
        rotation: item.rotation,
        shape: item.shape,
        chairs: item.chairs,
        joinGroup: item.joinGroup,
      );
      setState(() {
        _tables = [..._tables, copy];
        _selectedKey = FloorCanvas.keyOf(copy);
        _clipboard = copy;
        _dirty = true;
      });
    } else if (item is FloorElement) {
      final copy = FloorElement(
        id: null,
        draftKey: 'element-$stamp',
        zone: zone.name,
        xCm: cx(item.xCm),
        yCm: cy(item.yCm),
        widthCm: item.widthCm,
        heightCm: item.heightCm,
        rotation: item.rotation,
        shape: item.shape,
      );
      setState(() {
        _elements = [..._elements, copy];
        _selectedKey = copy.key;
        _clipboard = copy;
        _dirty = true;
      });
    }
  }

  Future<void> _deleteTable(DiningTable table) async {
    final ok = await confirm(
      context,
      title: 'Usunąć stolik ${table.label}?',
      message:
          'Jeśli stolik ma przyszłe rezerwacje, zapis się nie uda. Wtedy wyłącz stolik zamiast go usuwać.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    _remember();
    setState(() {
      final key = FloorCanvas.keyOf(table);
      _tables = _tables.where((t) => FloorCanvas.keyOf(t) != key).toList();
      if (table.id != null) _deletedTables.add(table.id!);
      _selectedKey = null;
      _dirty = true;
    });
  }

  Future<void> _addZone() async {
    final name = await _askText(context, title: 'Nowa strefa', label: 'Nazwa, na przykład „ogródek”');
    if (name == null) return;
    if (_zones.any((z) => z.name.toLowerCase() == name.toLowerCase())) {
      if (mounted) showMessage(context, 'Strefa o tej nazwie już istnieje.');
      return;
    }
    _remember();
    setState(() {
      _zones = [
        ..._zones,
        FloorZone(id: null, name: name, widthCm: 800, heightCm: 500, position: _zones.length),
      ];
      _zoneName = name;
      _dirty = true;
    });
  }

  void _updateZone(FloorZone zone, FloorZone updated) {
    _remember('strefa-${zone.name}');
    setState(() {
      _zones = [for (final z in _zones) if (z == zone) updated else z];
      if (updated.name != zone.name) {
        _tables = [
          for (final t in _tables) t.zone == zone.name ? t.copyWith(zone: updated.name) : t,
        ];
        _zoneName = updated.name;
      }
      _dirty = true;
    });
  }

  Future<void> _deleteZone(FloorZone zone) async {
    if (_tables.any((t) => t.zone == zone.name)) {
      showMessage(context, 'Najpierw usuń albo przenieś stoliki z tej strefy.');
      return;
    }
    final ok = await confirm(
      context,
      title: 'Usunąć strefę „${zone.name}”?',
      message: 'Strefa jest pusta.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    _remember();
    setState(() {
      _zones = _zones.where((z) => z != zone).toList();
      if (zone.id != null) _deletedZones.add(zone.id!);
      _zoneName = null;
      _dirty = true;
    });
  }

  Future<void> _save(String restaurantId) async {
    final labels = <String>{};
    for (final t in _tables) {
      if (!labels.add(t.label.trim().toLowerCase())) {
        showMessage(context, 'Numer stolika ${t.label} się powtarza. Każdy stolik potrzebuje innego numeru.');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveFloor(
        restaurantId: restaurantId,
        zones: _zones,
        deletedZoneIds: _deletedZones,
        tables: _tables,
        deletedTableIds: _deletedTables,
        elements: _elements,
        deletedElementIds: _deletedElements,
      );
      ref
        ..invalidate(zonesProvider(restaurantId))
        ..invalidate(tablesProvider(restaurantId))
        ..invalidate(elementsProvider(restaurantId));
      if (!mounted) return;
      setState(() {
        _mode = _Mode.live;
        _dirty = false;
        _selectedKey = null;
        _history.clear();
      });
      showMessage(context, 'Układ sali zapisany.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
      // Część zmian mogła się zapisać, więc odświeżamy dane z bazy.
      ref
        ..invalidate(zonesProvider(restaurantId))
        ..invalidate(tablesProvider(restaurantId));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    if (!restaurant.isPro) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Edycja sali'),
          Expanded(child: ProGate(feature: 'Edycja sali')),
        ],
      );
    }

    final zonesAsync = ref.watch(zonesProvider(restaurant.id));
    final tablesAsync = ref.watch(tablesProvider(restaurant.id));
    final elementsAsync = ref.watch(elementsProvider(restaurant.id));
    final today = dateOnly(_now);
    final reservations =
        ref.watch(reservationsProvider((restaurantId: restaurant.id, day: today))).value ??
        const <PanelReservation>[];

    if (zonesAsync.hasError || tablesAsync.hasError) {
      return ErrorView(
        error: zonesAsync.error ?? tablesAsync.error!,
        onRetry: () => ref
          ..invalidate(zonesProvider(restaurant.id))
          ..invalidate(tablesProvider(restaurant.id)),
      );
    }
    if (!zonesAsync.hasValue || !tablesAsync.hasValue) return const LoadingView();

    final editing = _mode == _Mode.edit;
    _floorUnsaved = editing && _dirty;
    final zones = editing ? _zones : zonesAsync.value!;
    final tables = editing ? _tables : tablesAsync.value!;
    final elements = editing ? _elements : (elementsAsync.value ?? const <FloorElement>[]);
    void startEditing() => _startEditing(
      zonesAsync.value!,
      tablesAsync.value!,
      elementsAsync.value ?? const [],
    );

    // Stoliki ze strefą, której nie ma w tabeli stref, pokazujemy w strefie o domyślnych wymiarach.
    final zoneList = orderedZones(zones, tables);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Edycja sali',
          subtitle: editing
              ? 'Przeciągaj stoliki, krzesła i stałe elementy. Ctrl+C i Ctrl+V kopiują, Ctrl+Z cofa (na Macu Cmd).'
              : 'Zajętość stolików ${_minuteOfDay == null ? 'teraz' : 'dziś o ${Fmt.time(_viewTime)}'}. Odświeża się sama.',
          actions: [
            if (!editing && restaurant.canManage)
              OutlinedButton.icon(
                onPressed: startEditing,
                icon: const Glyph(AppIcons.pencil, size: 16),
                label: const Text('Edytuj układ'),
              ),
            if (editing) ...[
              IconButton(
                tooltip: 'Cofnij (Ctrl+Z)',
                onPressed: _saving || _history.isEmpty ? null : _undo,
                icon: const Glyph(AppIcons.undo, size: 18),
              ),
              TextButton(
                onPressed: _saving ? null : _stopEditing,
                style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                child: const Text('Anuluj'),
              ),
              FilledButton(
                onPressed: _saving || !_dirty ? null : () => _save(restaurant.id),
                child: const Text('Zapisz układ'),
              ),
            ],
          ],
          below: Row(
            children: [
              if (zoneList.isNotEmpty)
                SegmentedTabs<String>(
                  options: [for (final z in zoneList) (z.name, Fmt.capitalize(z.name))],
                  selected: _currentZone(zoneList).name,
                  onChanged: (n) => setState(() {
                    _zoneName = n;
                    _selectedKey = null;
                  }),
                ),
              if (editing) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _addZone,
                  icon: const Glyph(AppIcons.plus, size: 16),
                  label: const Text('Strefa'),
                ),
              ],
              const Spacer(),
              if (!editing) _TimeControl(
                minuteOfDay: _minuteOfDay,
                onChanged: (m) => setState(() => _minuteOfDay = m),
              ),
              if (editing && zoneList.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: () => _addElement(_currentZone(zoneList)),
                  icon: const Glyph(AppIcons.rectangle, size: 16),
                  label: const Text('Element stały'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _addTable(_currentZone(zoneList), seat: true),
                  icon: const Glyph(AppIcons.circle, size: 16),
                  label: const Text('Miejsce'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _addTable(_currentZone(zoneList)),
                  icon: const Glyph(AppIcons.plus, size: 16),
                  label: const Text('Stolik'),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: zoneList.isEmpty
              ? MessageView(
                  icon: AppIcons.squaresFour,
                  title: 'Sala jest pusta',
                  message: restaurant.canManage
                      ? 'Dodaj strefę, na przykład „sala”, a potem rozstaw w niej stoliki.'
                      : 'Kierownik lokalu jeszcze nie narysował sali.',
                  actionLabel: restaurant.canManage ? 'Edytuj układ' : null,
                  onAction: restaurant.canManage
                      ? startEditing
                      : null,
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _canvas(zoneList, tables, elements, reservations, editing)),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: 340,
                        child: editing
                            ? _inspector(_currentZone(zoneList), tables, elements)
                            : _livePanel(tables, reservations),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  FloorZone _currentZone(List<FloorZone> zones) =>
      zones.firstWhere((z) => z.name == _zoneName, orElse: () => zones.first);

  Widget _canvas(
    List<FloorZone> zones,
    List<DiningTable> tables,
    List<FloorElement> elements,
    List<PanelReservation> reservations,
    bool editing,
  ) {
    final zone = _currentZone(zones);
    final inZone = tables.where((t) => t.zone == zone.name).toList();
    final zoneElements = elements.where((e) => e.zone == zone.name).toList();
    final overlapping = <String>{};
    if (editing) {
      for (var i = 0; i < inZone.length; i++) {
        for (var j = i + 1; j < inZone.length; j++) {
          if (tablesOverlap(inZone[i], inZone[j])) {
            overlapping
              ..add(FloorCanvas.keyOf(inZone[i]))
              ..add(FloorCanvas.keyOf(inZone[j]));
          }
        }
      }
    }

    void focusPlan() {
      if (editing) _canvasFocus.requestFocus();
    }

    return CallbackShortcuts(
      bindings: editing
          ? {
              const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
              const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
              const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copy,
              const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copy,
              const SingleActivator(LogicalKeyboardKey.keyV, control: true): () => _paste(_clipboard, zone),
              const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () => _paste(_clipboard, zone),
              const SingleActivator(LogicalKeyboardKey.keyD, control: true): () => _paste(_selectedItem(), zone),
              const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () => _paste(_selectedItem(), zone),
            }
          : const <ShortcutActivator, VoidCallback>{},
      child: Focus(
        focusNode: _canvasFocus,
        child: Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FloorCanvas(
          zone: zone,
          tables: inZone,
          elements: zoneElements,
          selectedId: _selectedKey,
          chairEditKey: editing ? _selectedKey : null,
          onDragChair: editing ? _dragChair : null,
          onDragChairEnd: editing ? (_) => _chairRaw = null : null,
          onTapElement: editing
              ? (e) {
                  focusPlan();
                  setState(() => _selectedKey = e.key);
                }
              : null,
          onDragElement: editing
              ? (e, d) => _updateElement(e, (x) => x.copyWith(
                    xCm: (x.xCm + d.dx).round().clamp(0, zone.widthCm),
                    yCm: (x.yCm + d.dy).round().clamp(0, zone.heightCm),
                  ))
              : null,
          onDragElementEnd: editing
              ? (e) => _updateElement(e, (x) => x.copyWith(
                    xCm: ((x.xCm / 10).round() * 10).clamp(0, zone.widthCm),
                    yCm: ((x.yCm / 10).round() * 10).clamp(0, zone.heightCm),
                  ))
              : null,
          onTapTable: (t) {
            focusPlan();
            setState(() => _selectedKey = FloorCanvas.keyOf(t));
          },
          onTapEmpty: () {
            focusPlan();
            setState(() => _selectedKey = null);
          },
          lookOf: (t) => editing
              ? _editLook(t, overlapping.contains(FloorCanvas.keyOf(t)))
              : _liveLook(t, reservations),
          onDragTable: editing
              ? (t, d) => _update(t, (x) => x.copyWith(
                    xCm: (x.xCm + d.dx).round().clamp(0, zone.widthCm),
                    yCm: (x.yCm + d.dy).round().clamp(0, zone.heightCm),
                  ))
              : null,
          onDragEnd: editing
              ? (t) => _update(t, (x) => x.copyWith(
                    xCm: ((x.xCm / 10).round() * 10).clamp(0, zone.widthCm),
                    yCm: ((x.yCm / 10).round() * 10).clamp(0, zone.heightCm),
                  ))
              : null,
        ),
      ),
        ),
      ),
    );
  }

  TableLook _editLook(DiningTable t, bool overlaps) {
    return TableLook(
      fill: overlaps ? AppColors.error.withValues(alpha: 0.12) : AppColors.surfaceRaised,
      stroke: overlaps ? AppColors.error : planLine,
      // Bez podpisu pod blatem: liczbę miejsc widać po krzesłach i w panelu obok.
      captionColor: overlaps ? AppColors.error : null,
      dimmed: !t.active,
    );
  }

  TableLook _liveLook(DiningTable t, List<PanelReservation> reservations) =>
      liveTableLook(t, reservations, _viewTime, seatedCountsNow: _minuteOfDay == null);

  Widget _livePanel(List<DiningTable> tables, List<PanelReservation> reservations) {
    final text = Theme.of(context).textTheme;
    DiningTable? table;
    for (final t in tables) {
      if (FloorCanvas.keyOf(t) == _selectedKey) table = t;
    }

    if (table == null) {
      final active = tables.where((t) => t.active).toList();
      final tableCount = active.where((t) => !t.isSeat).length;
      final seats = active.fold(0, (sum, t) => sum + t.seats);
      return PanelCard(
        title: 'Sala ${_minuteOfDay == null ? 'teraz' : 'o ${Fmt.time(_viewTime)}'}',
        icon: AppIcons.squaresFour,
        iconColor: TileColors.blue,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Stoliki',
                    value: '$tableCount',
                    icon: AppIcons.squaresFour,
                    color: TileColors.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Miejsca siedzące',
                    value: '$seats',
                    icon: AppIcons.users,
                    color: TileColors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _Legend(),
            const SizedBox(height: 18),
            Text(
              'Kliknij stolik, żeby zobaczyć jego rezerwacje na dziś.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    final forTable = reservations.where((r) => r.tableIds.contains(table!.id)).toList();
    return PanelCard(
      title: 'Stolik ${table.label}',
      trailing: IconButton(
        tooltip: 'Zamknij',
        icon: const Glyph(AppIcons.close, size: 16),
        onPressed: () => setState(() => _selectedKey = null),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${table.seats} miejsc · ${table.widthCm}×${table.heightCm} cm · ${table.zone}'
            '${table.joinGroup == null ? '' : ' · łączenie: ${table.joinGroup}'}',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
          ),
          const SizedBox(height: 16),
          Text('Dziś', style: text.titleSmall),
          const SizedBox(height: 8),
          if (forTable.isEmpty)
            Text('Brak rezerwacji na ten stolik.', style: text.bodyMedium?.copyWith(color: AppColors.textMuted))
          else
            for (final r in forTable)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        '${Fmt.time(r.startsAt)}–${Fmt.time(r.endsAt)}',
                        style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.guestName, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelLarge),
                          Text(
                            [Fmt.people(r.partySize), if (r.occasion != null) r.occasion!.label].join(' · '),
                            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(status: r.status),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _inspector(FloorZone zone, List<DiningTable> tables, List<FloorElement> elements) {
    DiningTable? table;
    for (final t in tables) {
      if (FloorCanvas.keyOf(t) == _selectedKey) table = t;
    }
    FloorElement? element;
    for (final e in elements) {
      if (e.key == _selectedKey) element = e;
    }
    if (element != null) {
      return _ElementInspector(
        key: ValueKey('element-${element.key}-$_undoGeneration'),
        element: element,
        onChanged: (change) => _updateElement(element!, change),
        onDuplicate: () => _paste(element, zone),
        onDelete: () => _deleteElement(element!),
        onClose: () => setState(() => _selectedKey = null),
      );
    }
    if (table == null) {
      return _ZoneInspector(
        key: ValueKey('strefa-${zone.name}-$_undoGeneration'),
        zone: zone,
        tableCount: tables.where((t) => t.zone == zone.name).length,
        onChanged: (updated) => _updateZone(zone, updated),
        onDelete: () => _deleteZone(zone),
      );
    }
    return _TableInspector(
      key: ValueKey('stolik-${FloorCanvas.keyOf(table)}-$_undoGeneration'),
      table: table,
      zones: _zones.map((z) => z.name).toList(),
      onChanged: (change) => _update(table!, change),
      onDuplicate: () => _paste(table, zone),
      onDelete: () => _deleteTable(table!),
      onClose: () => setState(() => _selectedKey = null),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget item(Color fill, Color stroke, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 12,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: stroke, width: 1.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: text.bodySmall),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item(AppColors.accentTint, AppColors.accent, 'Goście przy stoliku'),
        item(AppColors.warning.withValues(alpha: 0.14), AppColors.warning, 'Zarezerwowany na tę godzinę'),
        item(AppColors.surface, AppColors.warning, 'Wolny, rezerwacja w ciągu 90 minut'),
        item(AppColors.surface, planLine, 'Wolny'),
      ],
    );
  }
}

class _TimeControl extends StatelessWidget {
  const _TimeControl({required this.minuteOfDay, required this.onChanged});

  final int? minuteOfDay;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final value = (minuteOfDay ?? (DateTime.now().hour * 60 + DateTime.now().minute)).clamp(600, 1425);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedTabs<bool>(
          options: const [(true, 'Teraz'), (false, 'Inna godzina')],
          selected: minuteOfDay == null,
          onChanged: (now) => onChanged(now ? null : value),
        ),
        if (minuteOfDay != null) ...[
          SizedBox(
            width: 240,
            child: Slider(
              value: value.toDouble(),
              min: 600,
              max: 1425,
              divisions: (1425 - 600) ~/ 15,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          Text(
            '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}',
            style: text.titleSmall?.copyWith(fontFeatures: _tabular),
          ),
        ],
      ],
    );
  }
}

class _ZoneInspector extends StatefulWidget {
  const _ZoneInspector({
    super.key,
    required this.zone,
    required this.tableCount,
    required this.onChanged,
    required this.onDelete,
  });

  final FloorZone zone;
  final int tableCount;
  final ValueChanged<FloorZone> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ZoneInspector> createState() => _ZoneInspectorState();
}

class _ZoneInspectorState extends State<_ZoneInspector> {
  late final _name = TextEditingController(text: widget.zone.name);
  late final _width = TextEditingController(text: '${widget.zone.widthCm}');
  late final _height = TextEditingController(text: '${widget.zone.heightCm}');

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _apply() {
    final w = parseInt(_width.text);
    final h = parseInt(_height.text);
    final name = _name.text.trim();
    if (name.isEmpty || w == null || h == null || w < 200 || h < 200 || w > 10000 || h > 10000) {
      showMessage(context, 'Podaj nazwę i wymiary strefy od 200 do 10 000 cm.');
      return;
    }
    widget.onChanged(widget.zone.copyWith(name: name, widthCm: w, heightCm: h));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PanelCard(
      title: 'Strefa',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nazwa strefy'),
            onSubmitted: (_) => _apply(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _NumberField(controller: _width, label: 'Szerokość', suffix: 'cm', onSubmitted: _apply)),
              const SizedBox(width: 10),
              Expanded(child: _NumberField(controller: _height, label: 'Głębokość', suffix: 'cm', onSubmitted: _apply)),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _apply, child: const Text('Zastosuj')),
          const SizedBox(height: 18),
          Text(
            'Stolików w strefie: ${widget.tableCount}. Kliknij stolik na planie, żeby zmienić jego wymiary, liczbę miejsc i obrót.',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: widget.onDelete,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Usuń strefę'),
          ),
        ],
      ),
    );
  }
}

class _TableInspector extends StatefulWidget {
  const _TableInspector({
    super.key,
    required this.table,
    required this.zones,
    required this.onChanged,
    required this.onDuplicate,
    required this.onDelete,
    required this.onClose,
  });

  final DiningTable table;
  final List<String> zones;
  final ValueChanged<DiningTable Function(DiningTable)> onChanged;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  State<_TableInspector> createState() => _TableInspectorState();
}

class _TableInspectorState extends State<_TableInspector> {
  late final _label = TextEditingController(text: widget.table.label);
  late final _width = TextEditingController(text: '${widget.table.widthCm}');
  late final _height = TextEditingController(text: '${widget.table.heightCm}');
  late final _group = TextEditingController(text: widget.table.joinGroup ?? '');

  @override
  void didUpdateWidget(covariant _TableInspector old) {
    super.didUpdateWidget(old);
    // Po przeciągnięciu albo obrocie wymiary się nie zmieniają, ale po zamianie
    // szerokości z głębokością pola muszą pokazać nowe wartości.
    if (old.table.widthCm != widget.table.widthCm) _width.text = '${widget.table.widthCm}';
    if (old.table.heightCm != widget.table.heightCm) _height.text = '${widget.table.heightCm}';
  }

  @override
  void dispose() {
    _label.dispose();
    _width.dispose();
    _height.dispose();
    _group.dispose();
    super.dispose();
  }

  void _applySize() {
    final w = parseInt(_width.text);
    final h = parseInt(_height.text);
    if (w == null || h == null || w < 30 || h < 30 || w > 1000 || h > 1000) {
      showMessage(context, 'Wymiary blatu od 30 do 1000 cm.');
      return;
    }
    widget.onChanged((t) {
      final resized = t.copyWith(
        widthCm: w,
        heightCm: t.shape == TableShape.round ? w : h,
      );
      final chairs = t.chairs;
      if (chairs == null) return resized;
      // Własne krzesła przesuwają się razem z krawędziami blatu.
      return resized.copyWith(chairs: [
        for (final c in chairs)
          attachChair(
            resized,
            ChairPos(c.x * resized.widthCm / t.widthCm, c.y * resized.heightCm / t.heightCm),
          ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.table;
    final text = Theme.of(context).textTheme;

    return Card(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.isSeat ? 'Miejsce do rezerwacji' : 'Stolik',
                  style: text.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Zamknij',
                icon: const Glyph(AppIcons.close, size: 16),
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _label,
                  maxLength: 8,
                  decoration: const InputDecoration(labelText: 'Numer', counterText: ''),
                  onChanged: (v) {
                    if (v.trim().isNotEmpty) widget.onChanged((x) => x.copyWith(label: v.trim()));
                  },
                ),
              ),
              if (!t.isSeat) ...[
                const SizedBox(width: 10),
                _Stepper(
                  label: 'Miejsca',
                  value: t.seats,
                  min: 1,
                  max: 30,
                  // Nowa liczba miejsc rozstawia krzesła od nowa.
                  onChanged: (v) => widget.onChanged((x) => x.copyWith(seats: v, resetChairs: true)),
                ),
              ],
            ],
          ),
          if (t.isSeat) ...[
            const SizedBox(height: 12),
            Text(
              'Pojedyncze krzesło albo hoker, który gość rezerwuje dla jednej osoby, na przykład przy barze. '
              'Sąsiednie miejsca z tą samą grupą łączenia system zestawi dla większej grupy.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
          if (!t.isSeat) ...[
          const SizedBox(height: 14),
          SegmentedTabs<TableShape>(
            options: [for (final s in TableShape.values) (s, s.label)],
            selected: t.shape,
            onChanged: (s) {
              widget.onChanged(
                (x) => x.copyWith(
                  shape: s,
                  heightCm: s == TableShape.round ? x.widthCm : x.heightCm,
                  resetChairs: true,
                ),
              );
              if (s == TableShape.round) _height.text = _width.text;
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: _width,
                  label: t.shape == TableShape.round ? 'Średnica' : 'Szerokość',
                  suffix: 'cm',
                  onSubmitted: _applySize,
                ),
              ),
              if (t.shape == TableShape.rect) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _NumberField(controller: _height, label: 'Głębokość', suffix: 'cm', onSubmitted: _applySize),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _applySize, child: const Text('Zastosuj wymiary')),
          ),
          const SizedBox(height: 6),
          if (t.shape == TableShape.rect)
            _RotationField(
              value: t.rotation,
              onChanged: (v) => widget.onChanged((x) => x.copyWith(rotation: v)),
            ),
          const SizedBox(height: 12),
          Text('Krzesła', style: text.titleSmall),
          const SizedBox(height: 4),
          Text(
            t.chairs == null
                ? 'Rozstawione automatycznie wzdłuż szerokości. Przeciągnij krzesło, żeby ustawić je po swojemu.'
                : 'Ustawione ręcznie. Krzesła przesuwają się tylko wokół blatu.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          if (t.chairs != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => widget.onChanged((x) => x.copyWith(resetChairs: true)),
                child: const Text('Rozstaw automatycznie'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: widget.zones.contains(t.zone) ? t.zone : null,
            decoration: const InputDecoration(labelText: 'Strefa'),
            items: [for (final z in widget.zones) DropdownMenuItem(value: z, child: Text(Fmt.capitalize(z)))],
            onChanged: (z) {
              if (z != null) widget.onChanged((x) => x.copyWith(zone: z));
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _group,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: 'Grupa łączenia (opcjonalnie)',
              helperText: 'Stoliki z tą samą grupą system może zestawić dla większej rezerwacji.',
              helperMaxLines: 2,
              counterText: '',
            ),
            onChanged: (v) => widget.onChanged(
              (x) => v.trim().isEmpty ? x.copyWith(clearJoinGroup: true) : x.copyWith(joinGroup: v.trim()),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pierwszeństwo przy doborze', style: text.bodyMedium),
                    Text(
                      'Wyższe wybierane wcześniej przy tej samej liczbie miejsc',
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              _Stepper(
                value: t.priority,
                min: 0,
                max: 9,
                onChanged: (v) => widget.onChanged((x) => x.copyWith(priority: v)),
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
                    Text('Przyjmuje rezerwacje', style: text.bodyMedium),
                    Text(
                      'Wyłączony stolik zostaje na planie, ale system go nie dobiera',
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Switch(
                value: t.active,
                onChanged: (v) => widget.onChanged((x) => x.copyWith(active: v)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: widget.onDuplicate,
                icon: const Glyph(AppIcons.copy, size: 16),
                label: const Text('Duplikuj'),
              ),
              const Spacer(),
              TextButton(
                onPressed: widget.onDelete,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: Text(t.isSeat ? 'Usuń miejsce' : 'Usuń stolik'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
      style: const TextStyle(fontFeatures: _tabular),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.label,
  });

  final String? label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Text(label!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Mniej',
              icon: const Glyph(AppIcons.minus, size: 14),
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 28,
              child: Text('$value', textAlign: TextAlign.center, style: text.titleSmall?.copyWith(fontFeatures: _tabular)),
            ),
            IconButton(
              tooltip: 'Więcej',
              icon: const Glyph(AppIcons.plus, size: 14),
              onPressed: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextDialog(title: title, label: label),
  );
}

/// Okno z jednym polem tekstowym. Kontroler żyje tak długo jak okno.
class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.label});

  final String title;
  final String label;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _controller = TextEditingController();

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
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 40,
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
        FilledButton(onPressed: _submit, child: const Text('Dodaj')),
      ],
    );
  }
}

class _ElementInspector extends StatefulWidget {
  const _ElementInspector({
    super.key,
    required this.element,
    required this.onChanged,
    required this.onDuplicate,
    required this.onDelete,
    required this.onClose,
  });

  final FloorElement element;
  final ValueChanged<FloorElement Function(FloorElement)> onChanged;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  State<_ElementInspector> createState() => _ElementInspectorState();
}

class _ElementInspectorState extends State<_ElementInspector> {
  late final _width = TextEditingController(text: '${widget.element.widthCm}');
  late final _height = TextEditingController(text: '${widget.element.heightCm}');

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _applySize() {
    final w = parseInt(_width.text);
    final h = parseInt(_height.text);
    if (w == null || h == null || w < 5 || h < 5 || w > 5000 || h > 5000) {
      showMessage(context, 'Wymiary elementu od 5 do 5000 cm.');
      return;
    }
    widget.onChanged((e) => e.copyWith(
      widthCm: w,
      heightCm: widget.element.shape == TableShape.round ? w : h,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.element;
    final text = Theme.of(context).textTheme;
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(child: Text('Element stały', style: text.titleMedium)),
              IconButton(
                tooltip: 'Zamknij',
                icon: const Glyph(AppIcons.close, size: 16),
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ściana, bar, filar albo donica. Na planie jest jasnoszary, bez napisu, i nie da się go zarezerwować.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          SegmentedTabs<TableShape>(
            options: const [(TableShape.rect, 'Prostokąt'), (TableShape.round, 'Koło')],
            selected: e.shape,
            onChanged: (shape) {
              widget.onChanged((x) => x.copyWith(
                shape: shape,
                heightCm: shape == TableShape.round ? x.widthCm : x.heightCm,
              ));
              if (shape == TableShape.round) _height.text = _width.text;
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: _width,
                  label: e.shape == TableShape.round ? 'Średnica' : 'Szerokość',
                  suffix: 'cm',
                  onSubmitted: _applySize,
                ),
              ),
              if (e.shape == TableShape.rect) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _NumberField(controller: _height, label: 'Głębokość', suffix: 'cm', onSubmitted: _applySize),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _applySize, child: const Text('Zastosuj wymiary')),
          ),
          if (e.shape == TableShape.rect)
            _RotationField(
              value: e.rotation,
              onChanged: (v) => widget.onChanged((x) => x.copyWith(rotation: v)),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: widget.onDuplicate,
                icon: const Glyph(AppIcons.copy, size: 16),
                label: const Text('Duplikuj'),
              ),
              const Spacer(),
              TextButton(
                onPressed: widget.onDelete,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Usuń element'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Obrót w stopniach: pole do wpisania kąta i przyciski co 15°.
class _RotationField extends StatefulWidget {
  const _RotationField({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_RotationField> createState() => _RotationFieldState();
}

class _RotationFieldState extends State<_RotationField> {
  late final _controller = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(covariant _RotationField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && parseInt(_controller.text) != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(int degrees) => widget.onChanged(degrees % 360);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Text('Obrót', style: text.bodyMedium),
        const Spacer(),
        IconButton(
          tooltip: 'Obróć o 15° w lewo',
          icon: const Glyph(AppIcons.undo, size: 16),
          onPressed: () => _set(widget.value - 15),
        ),
        const SizedBox(width: 6),
        // Liczba stoi na środku pola, a stopnie przy prawej krawędzi,
        // tak samo jak „cm” w polach wymiarów.
        SizedBox(
          width: 84,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                style: const TextStyle(fontFeatures: _tabular),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (v) {
                  final degrees = parseInt(v);
                  if (degrees != null) _set(degrees);
                },
              ),
              Positioned(
                right: 10,
                child: IgnorePointer(
                  child: Text(
                    '°',
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Obróć o 15° w prawo',
          icon: const Glyph(AppIcons.refresh, size: 16),
          onPressed: () => _set(widget.value + 15),
        ),
      ],
    );
  }
}

/// Stan układu sali zapamiętany przed zmianą.
class _Snapshot {
  const _Snapshot({
    required this.zones,
    required this.tables,
    required this.elements,
    required this.deletedTables,
    required this.deletedElements,
    required this.deletedZones,
    required this.dirty,
    required this.zoneName,
  });

  final List<FloorZone> zones;
  final List<DiningTable> tables;
  final List<FloorElement> elements;
  final List<String> deletedTables;
  final List<String> deletedElements;
  final List<String> deletedZones;
  final bool dirty;
  final String? zoneName;
}
