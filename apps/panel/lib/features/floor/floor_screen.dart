import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../reservations/reservations_screen.dart' show StatusPill;
import 'floor_canvas.dart';
import 'plan_geometry.dart';

part 'floor_plan_input.dart';

const _tabular = [FontFeature.tabularFigures()];

enum _Mode { live, edit }

/// Narzędzia edytora na pasku pod planem, jak w UniFi Design Center. Litera to skrót klawiszowy.
enum _Tool {
  select(AppIcons.cursor, 'Zaznacz', 'V'),
  pan(AppIcons.move, 'Przesuń widok', 'H'),
  wall(AppIcons.wall, 'Ściana', 'W'),
  element(AppIcons.rectangle, 'Element stały', 'R'),
  table(AppIcons.diningTable, 'Stolik', 'T'),
  seat(AppIcons.circle, 'Miejsce', 'M');

  const _Tool(this.icon, this.label, this.shortcut);

  final AppIconData icon;
  final String label;
  final String shortcut;

  /// Podpowiedź nad paskiem, gdy narzędzie jest wybrane.
  String? get hint => switch (this) {
    _Tool.select => null,
    _Tool.pan => 'Przeciągnij, żeby przesunąć widok. Kółko myszy przybliża.',
    _Tool.wall => 'Klikaj kolejne narożniki. Enter, Esc albo dwuklik kończy ścianę, Shift: dowolny kąt.',
    _Tool.element => 'Przeciągnij, żeby narysować prostokąt. Samo kliknięcie wstawia 2 × 0,6 m.',
    _Tool.table => 'Kliknij na planie, żeby postawić stolik 4-osobowy.',
    _Tool.seat => 'Kliknij na planie, żeby postawić miejsce, na przykład hoker przy barze.',
  };
}

enum _PresetKind { table, seat, element }

/// Gotowy obiekt z panelu „Dodaj na plan”. Przeciąga się go na plan jak urządzenia w UniFi Design Center
/// albo klika, żeby stanął na środku widoku.
class _Preset {
  const _Preset(
    this.label, {
    this.kind = _PresetKind.table,
    this.width = 120,
    this.height = 80,
    this.seats = 4,
    this.shape = TableShape.rect,
  });

  final String label;
  final _PresetKind kind;
  final int width;
  final int height;
  final int seats;
  final TableShape shape;

  String get size => shape == TableShape.round ? 'Ø $width cm' : '$width × $height cm';

  /// Stolik do podglądu, z krzesłami w automatycznym rozstawieniu.
  DiningTable get sample => DiningTable(
    id: null,
    label: '',
    kind: kind == _PresetKind.seat ? TableKind.seat : TableKind.table,
    seats: seats,
    widthCm: width,
    heightCm: height,
    zone: '',
    priority: 0,
    active: true,
    xCm: 0,
    yCm: 0,
    rotation: 0,
    shape: shape,
  );
}

const _presets = [
  _Preset('Stolik 2-os.', width: 70, height: 70, seats: 2),
  _Preset('Stolik 4-os.'),
  _Preset('Stolik 6-os.', width: 180, height: 80, seats: 6),
  _Preset('Okrągły 4-os.', width: 100, height: 100, shape: TableShape.round),
  _Preset('Miejsce', kind: _PresetKind.seat, width: 45, height: 45, seats: 1, shape: TableShape.round),
  _Preset('Element stały', kind: _PresetKind.element, width: 200, height: 60),
];

/// Szerokość pływającego panelu po prawej stronie planu.
const _panelWidth = 320.0;

/// Wyrównanie zaznaczonych obiektów do krawędzi albo środka ich wspólnego obrysu.
enum _Align { left, centerX, right, top, centerY, bottom }

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

  /// Zaznaczone stoliki i elementy (klucze). Na żywo najwyżej jeden stolik.
  final Set<String> _selection = {};

  /// Zaznaczony obiekt, gdy zaznaczony jest dokładnie jeden.
  String? get _selectedKey => _selection.length == 1 ? _selection.first : null;

  void _select(String? key) {
    _selection.clear();
    if (key != null) _selection.add(key);
  }

  // Podgląd na żywo: godzina, dla której pokazujemy zajętość.
  DateTime _now = DateTime.now();
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

  // Schowek edytora: skopiowane stoliki, miejsca i elementy stałe.
  List<Object> _clipboard = const [];

  // Skróty działają, gdy fokus jest na planie, a nie w polu tekstowym.
  final _canvasFocus = FocusNode(debugLabel: 'plan sali');

  // Historia zmian do cofania (Ctrl+Z) i ponawiania (Ctrl+Shift+Z). Każdy wpis to stan układu sprzed zmiany.
  final List<_Snapshot> _history = [];
  final List<_Snapshot> _future = [];
  String? _lastAction;
  DateTime _lastActionAt = DateTime(0);

  // Zmienia się po cofnięciu, żeby panele boczne wczytały pola od nowa.
  int _undoGeneration = 0;

  // Widok planu i obsługa myszy, dotyku i klawiatury na planie (floor_plan_input.dart).
  final _planKey = GlobalKey(debugLabel: 'plan sali');
  PlanView? _view;
  String? _viewZone;
  Rect _viewArea = Rect.zero;

  /// Obsługa przybliżyła albo przesunęła widok: zmiana rozmiaru okna już go nie dopasowuje.
  bool _viewTouched = false;
  _PlanFrame? _frame;
  _Tool _tool = _Tool.select;
  bool _spaceDown = false;
  String? _hoverKey;
  MouseCursor _cursor = MouseCursor.defer;
  _Gesture? _gesture;
  Offset? _pointerPx;
  Offset? _wallStart;
  DateTime _lastWallClick = DateTime(0);
  Offset _lastWallClickPx = Offset.zero;
  final Map<int, Offset> _touches = {};
  double _panZoomScale = 1;
  ({double? x, double? y}) _guides = (x: null, y: null);
  Rect? _band;
  Rect? _draft;
  String? _measure;

  /// setState dla obsługi planu w floor_plan_input.dart.
  void _set(VoidCallback fn) => setState(fn);

  _Snapshot _snapshot() => _Snapshot(
    zones: _zones,
    tables: _tables,
    elements: _elements,
    deletedTables: [..._deletedTables],
    deletedElements: [..._deletedElements],
    deletedZones: [..._deletedZones],
    dirty: _dirty,
    zoneName: _zoneName,
  );

  /// Zapamiętuje stan przed zmianą. Szybkie zmiany tego samego elementu,
  /// na przykład pisanie numeru albo strzałki, tworzą jeden krok. Nowa zmiana kasuje „Ponów”.
  void _remember([String? action]) {
    final now = DateTime.now();
    final sameGesture = action != null &&
        action == _lastAction &&
        now.difference(_lastActionAt) < const Duration(milliseconds: 800);
    _lastAction = action;
    _lastActionAt = now;
    _future.clear();
    if (sameGesture) return;
    _history.add(_snapshot());
    if (_history.length > 100) _history.removeAt(0);
  }

  void _restore(_Snapshot s) {
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
    _selection.removeWhere(
      (key) => !_tables.any((t) => FloorCanvas.keyOf(t) == key) && !_elements.any((e) => e.key == key),
    );
  }

  void _undo() {
    if (_mode != _Mode.edit || _history.isEmpty) return;
    setState(() {
      _future.add(_snapshot());
      _restore(_history.removeLast());
    });
  }

  void _redo() {
    if (_mode != _Mode.edit || _future.isEmpty) return;
    setState(() {
      _history.add(_snapshot());
      _restore(_future.removeLast());
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

  DateTime get _viewTime => _now;

  /// Powrót do zwykłego zaznaczania, bez rozpoczętej ściany i gestu.
  void _resetTools() {
    _tool = _Tool.select;
    _wallStart = null;
    _gesture = null;
    _band = null;
    _draft = null;
    _measure = null;
    _guides = (x: null, y: null);
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
      _future.clear();
      _lastAction = null;
      _dirty = false;
      _mode = _Mode.edit;
      _selection.clear();
      _resetTools();
    });
    _canvasFocus.requestFocus();
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
      _selection.clear();
      _history.clear();
      _future.clear();
      _resetTools();
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
    _select(FloorCanvas.keyOf(t));
    return t;
  }

  /// Pierwszy wolny numer z przedrostkiem, od [start]: S5, M2.
  static String _freeLabel(String prefix, Set<String> taken, int start) {
    var n = start;
    while (taken.contains('$prefix$n')) {
      n++;
    }
    return '$prefix$n';
  }

  /// Miejsce nowego obiektu: wskazane albo środek widocznej części planu, na kratce co 10 cm.
  (int, int) _placeAt(FloorZone zone, Offset? at) {
    final frame = _frame;
    final p = at ??
        (frame != null && frame.zone.name == zone.name
            ? snapPoint(frame.view.toCm(frame.area.center), 10)
            : Offset(zone.widthCm / 2, zone.heightCm / 2));
    return (p.dx.round().clamp(0, zone.widthCm), p.dy.round().clamp(0, zone.heightCm));
  }

  void _addTable(
    FloorZone zone, {
    bool seat = false,
    Offset? at,
    int? width,
    int? height,
    int? seats,
    TableShape? shape,
  }) {
    final (x, y) = _placeAt(zone, at);
    final table = DiningTable(
      id: null,
      draftKey: 'nowy-${DateTime.now().microsecondsSinceEpoch}',
      label: _freeLabel(seat ? 'M' : 'S', {for (final t in _tables) t.label}, seat ? 1 : _tables.length + 1),
      kind: seat ? TableKind.seat : TableKind.table,
      seats: seats ?? (seat ? 1 : 4),
      widthCm: width ?? (seat ? 45 : 120),
      heightCm: height ?? (seat ? 45 : 80),
      zone: zone.name,
      priority: 0,
      active: true,
      xCm: x,
      yCm: y,
      rotation: 0,
      shape: shape ?? (seat ? TableShape.round : TableShape.rect),
    );
    _remember();
    setState(() {
      _tables = [..._tables, table];
      _select(FloorCanvas.keyOf(table));
      _dirty = true;
    });
  }

  void _addElement(FloorZone zone, {Offset? at, int width = 200, int height = 60}) {
    final (x, y) = _placeAt(zone, at);
    final element = FloorElement(
      id: null,
      draftKey: 'element-${DateTime.now().microsecondsSinceEpoch}',
      zone: zone.name,
      xCm: x,
      yCm: y,
      widthCm: width,
      heightCm: height,
      rotation: 0,
      shape: TableShape.rect,
    );
    _remember();
    setState(() {
      _elements = [..._elements, element];
      _select(element.key);
      _dirty = true;
    });
  }

  /// Obiekt z panelu „Dodaj na plan” w punkcie [at] albo na środku widoku.
  void _addPreset(_Preset preset, FloorZone zone, {Offset? at}) {
    switch (preset.kind) {
      case _PresetKind.element:
        _addElement(zone, at: at, width: preset.width, height: preset.height);
      case _PresetKind.seat:
        _addTable(zone, seat: true, at: at);
      case _PresetKind.table:
        _addTable(
          zone,
          at: at,
          width: preset.width,
          height: preset.height,
          seats: preset.seats,
          shape: preset.shape,
        );
    }
    _canvasFocus.requestFocus();
  }

  void _updateElement(FloorElement element, FloorElement Function(FloorElement) change) {
    _remember('element-${element.key}');
    setState(() {
      _elements = [
        for (final e in _elements)
          if (e.key == element.key) change(e) else e,
      ];
      _select(element.key);
      _dirty = true;
    });
  }

  void _deleteElement(FloorElement element) {
    _remember();
    setState(() {
      _elements = _elements.where((e) => e.key != element.key).toList();
      if (element.id != null) _deletedElements.add(element.id!);
      _selection.clear();
      _dirty = true;
    });
  }

  /// Zaznaczone stoliki, miejsca i elementy, w kolejności rysowania.
  List<Object> _selectedItems() => [
    for (final e in _elements)
      if (_selection.contains(e.key)) e,
    for (final t in _tables)
      if (_selection.contains(FloorCanvas.keyOf(t))) t,
  ];

  void _copy() {
    final items = _selectedItems();
    if (items.isEmpty) return;
    _clipboard = items;
    showMessage(context, 'Skopiowano. Wklej skrótem Ctrl+V.');
  }

  /// Wstawia kopie stolików, miejsc i elementów 50 cm obok oryginałów, w tym samym układzie.
  void _paste(List<Object> items, FloorZone zone) {
    if (items.isEmpty) return;
    _remember();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final taken = {for (final t in _tables) t.label};
    var tableCount = _tables.length;
    int cx(int x) => (x + 50).clamp(0, zone.widthCm);
    int cy(int y) => (y + 50).clamp(0, zone.heightCm);
    final tables = <DiningTable>[];
    final elements = <FloorElement>[];
    for (final (i, item) in items.indexed) {
      if (item is DiningTable) {
        tableCount++;
        final label = _freeLabel(item.isSeat ? 'M' : 'S', taken, item.isSeat ? 1 : tableCount);
        taken.add(label);
        tables.add(DiningTable(
          id: null,
          draftKey: 'kopia-$stamp-$i',
          label: label,
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
        ));
      } else if (item is FloorElement) {
        elements.add(FloorElement(
          id: null,
          draftKey: 'element-$stamp-$i',
          zone: zone.name,
          xCm: cx(item.xCm),
          yCm: cy(item.yCm),
          widthCm: item.widthCm,
          heightCm: item.heightCm,
          rotation: item.rotation,
          shape: item.shape,
        ));
      }
    }
    setState(() {
      _tables = [..._tables, ...tables];
      _elements = [..._elements, ...elements];
      _selection
        ..clear()
        ..addAll([for (final t in tables) FloorCanvas.keyOf(t), for (final e in elements) e.key]);
      _clipboard = [...elements, ...tables];
      _dirty = true;
    });
  }

  /// Przesuwa zaznaczone obiekty: każdy o swoje [delta] w cm, w granicach strefy.
  void _shiftSelection(FloorZone zone, Offset Function(Object item) delta) {
    int x(int v, double d) => (v + d).round().clamp(0, zone.widthCm);
    int y(int v, double d) => (v + d).round().clamp(0, zone.heightCm);
    _tables = [
      for (final t in _tables)
        if (_selection.contains(FloorCanvas.keyOf(t)))
          () {
            final d = delta(t);
            return t.copyWith(xCm: x(t.xCm, d.dx), yCm: y(t.yCm, d.dy));
          }()
        else
          t,
    ];
    _elements = [
      for (final e in _elements)
        if (_selection.contains(e.key))
          () {
            final d = delta(e);
            return e.copyWith(xCm: x(e.xCm, d.dx), yCm: y(e.yCm, d.dy));
          }()
        else
          e,
    ];
    _dirty = true;
  }

  /// Strzałki: przesunięcie zaznaczenia o 10 cm (z Shift o 50 cm, z Alt o 1 cm).
  void _nudge(FloorZone zone, Offset delta) {
    if (_selection.isEmpty) return;
    _remember('strzałki');
    setState(() => _shiftSelection(zone, (_) => delta));
  }

  /// Wyrównuje zaznaczone obiekty do krawędzi albo środka ich wspólnego obrysu.
  void _align(FloorZone zone, _Align align) {
    final items = _selectedItems();
    if (items.length < 2) return;
    final bounds = {for (final item in items) item: PlanBox.of(item).bounds};
    final all = bounds.values.reduce((a, b) => a.expandToInclude(b));
    _remember();
    setState(() => _shiftSelection(zone, (item) {
      final b = bounds[item]!;
      return switch (align) {
        _Align.left => Offset(all.left - b.left, 0),
        _Align.centerX => Offset(all.center.dx - b.center.dx, 0),
        _Align.right => Offset(all.right - b.right, 0),
        _Align.top => Offset(0, all.top - b.top),
        _Align.centerY => Offset(0, all.center.dy - b.center.dy),
        _Align.bottom => Offset(0, all.bottom - b.bottom),
      };
    }));
  }

  /// Rozkłada zaznaczone obiekty z równymi odstępami między skrajnymi (co najmniej trzy).
  void _distribute(FloorZone zone, Axis axis) {
    final items = _selectedItems();
    if (items.length < 3) return;
    final horizontal = axis == Axis.horizontal;
    final bounds = {for (final item in items) item: PlanBox.of(item).bounds};
    double start(Rect r) => horizontal ? r.left : r.top;
    double length(Rect r) => horizontal ? r.width : r.height;
    final sorted = [...items]
      ..sort((a, b) => (horizontal ? bounds[a]!.center.dx : bounds[a]!.center.dy)
          .compareTo(horizontal ? bounds[b]!.center.dx : bounds[b]!.center.dy));
    final first = bounds[sorted.first]!;
    final last = bounds[sorted.last]!;
    final span = start(last) + length(last) - start(first);
    final gap = (span - sorted.fold(0.0, (s, item) => s + length(bounds[item]!))) / (sorted.length - 1);
    final shifts = <Object, Offset>{};
    var position = start(first);
    for (final item in sorted) {
      final d = position - start(bounds[item]!);
      shifts[item] = horizontal ? Offset(d, 0) : Offset(0, d);
      position += length(bounds[item]!) + gap;
    }
    _remember();
    setState(() => _shiftSelection(zone, (item) => shifts[item] ?? Offset.zero));
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
      _selection.clear();
      _dirty = true;
    });
  }

  /// Usuwa zaznaczenie (Delete). Pyta tylko o zapisane już stoliki, resztę można cofnąć.
  Future<void> _deleteSelection() async {
    final tables = [
      for (final t in _tables)
        if (_selection.contains(FloorCanvas.keyOf(t))) t,
    ];
    final elements = [
      for (final e in _elements)
        if (_selection.contains(e.key)) e,
    ];
    if (tables.isEmpty && elements.isEmpty) return;
    if (tables.any((t) => t.id != null)) {
      final single = tables.length == 1 && elements.isEmpty;
      final ok = await confirm(
        context,
        title: single
            ? 'Usunąć ${tables.first.isSeat ? 'miejsce' : 'stolik'} ${tables.first.label}?'
            : 'Usunąć zaznaczone (${tables.length + elements.length})?',
        message:
            'Jeśli stolik ma przyszłe rezerwacje, zapis się nie uda. Wtedy wyłącz stolik zamiast go usuwać.',
        action: 'Usuń',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    _remember();
    setState(() {
      final keys = {..._selection};
      _tables = _tables.where((t) => !keys.contains(FloorCanvas.keyOf(t))).toList();
      _elements = _elements.where((e) => !keys.contains(e.key)).toList();
      _deletedTables.addAll([for (final t in tables) ?t.id]);
      _deletedElements.addAll([for (final e in elements) ?e.id]);
      _selection.clear();
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
      _selection.clear();
      _wallStart = null;
      _dirty = true;
    });
  }

  void _updateZone(FloorZone zone, FloorZone updated) {
    _remember('strefa-${zone.name}');
    setState(() {
      _zones = [for (final z in _zones) if (z.name == zone.name) updated else z];
      if (updated.name != zone.name) {
        _tables = [
          for (final t in _tables) t.zone == zone.name ? t.copyWith(zone: updated.name) : t,
        ];
        _elements = [
          for (final e in _elements) e.zone == zone.name ? e.copyWith(zone: updated.name) : e,
        ];
        _zoneName = updated.name;
        _viewZone = updated.name;
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
      message: 'Strefa nie ma stolików. Jej elementy stałe i ściany też znikną.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    _remember();
    setState(() {
      _zones = _zones.where((z) => z.name != zone.name).toList();
      if (zone.id != null) _deletedZones.add(zone.id!);
      final gone = _elements.where((e) => e.zone == zone.name).toList();
      _elements = _elements.where((e) => e.zone != zone.name).toList();
      _deletedElements.addAll([for (final e in gone) ?e.id]);
      _zoneName = null;
      _selection.clear();
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
        _selection.clear();
        _history.clear();
        _future.clear();
        _resetTools();
      });
      showMessage(context, 'Układ sali zapisany.');
    } catch (e) {
      if (mounted) showError(context, e);
      // Część zmian mogła się zapisać, więc odświeżamy dane z bazy.
      ref
        ..invalidate(zonesProvider(restaurantId))
        ..invalidate(tablesProvider(restaurantId))
        ..invalidate(elementsProvider(restaurantId));
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
          actions: [
            if (editing) ...[
              TextButton(
                onPressed: _saving ? null : _stopEditing,
                style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                child: const Text('Anuluj'),
              ),
              FilledButton(
                onPressed: _saving || !_dirty ? null : () => _save(restaurant.id),
                child: const Text('Zapisz układ'),
              ),
            ] else if (restaurant.canManage && zoneList.isNotEmpty)
              OutlinedButton.icon(
                onPressed: startEditing,
                icon: const Glyph(AppIcons.pencil, size: 16),
                label: const Text('Edytuj układ'),
              ),
          ],
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
                  child: _workspace(zoneList, tables, elements, reservations, editing),
                ),
        ),
      ],
    );
  }

  FloorZone _currentZone(List<FloorZone> zones) =>
      zones.firstWhere((z) => z.name == _zoneName, orElse: () => zones.first);

  void _switchZone(String name) => setState(() {
    _zoneName = name;
    _selection.clear();
    _wallStart = null;
    _hoverKey = null;
  });

  /// Część planu, w której mieści się strefa po „Dopasuj”: bez pływających paneli wokół.
  Rect _fitArea(Size size, bool editing) => Rect.fromLTRB(
    72,
    76,
    math.max(160, size.width - _panelWidth - 40),
    math.max(140, size.height - (editing ? 88 : 32)),
  );

  /// Widok dla strefy: dopasowany przy pierwszym rysowaniu, po zmianie strefy i po zmianie
  /// rozmiaru okna, dopóki obsługa sama nie przybliżyła albo nie przesunęła planu.
  PlanView _viewFor(FloorZone zone, Rect area) {
    final fit = PlanView.fit(zone, area);
    if (_view == null || _viewZone != zone.name || (!_viewTouched && area != _viewArea)) {
      _view = fit;
      _viewZone = zone.name;
      _viewTouched = false;
    }
    _viewArea = area;
    return _view!;
  }

  /// Plan na całą kartę, a nad nim pływające panele jak w UniFi Design Center: strefy w lewym górnym
  /// rogu, właściwości po prawej, przybliżanie w lewym dolnym rogu i narzędzia na dole.
  Widget _workspace(
    List<FloorZone> zones,
    List<DiningTable> tables,
    List<FloorElement> elements,
    List<PanelReservation> reservations,
    bool editing,
  ) {
    final zone = _currentZone(zones);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // Tło wokół strefy: w ciemnym motywie między podłogą sali a kartami, w jasnym szare jak strona.
        color: dark ? Color.lerp(AppColors.background, AppColors.surface, 0.45) : AppColors.background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.ring),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          final area = _fitArea(size, editing);
          final view = _viewFor(zone, area);
          final inZone = tables.where((t) => t.zone == zone.name).toList();
          final zoneElements = elements.where((e) => e.zone == zone.name).toList();
          _frame = _PlanFrame(
            zone: zone,
            tables: inZone,
            elements: zoneElements,
            view: view,
            area: area,
            fitScale: PlanView.fit(zone, area).scale,
            editing: editing,
          );
          final hint = editing ? (_spaceDown ? _Tool.pan.hint : _tool.hint) : null;
          return Stack(
            children: [
              Positioned.fill(child: _plan(zone, inZone, zoneElements, reservations, editing, view)),
              Positioned(
                left: 16,
                top: 16,
                right: _panelWidth + 32,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _Floating(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SegmentedTabs<String>(
                              options: [for (final z in zones) (z.name, Fmt.capitalize(z.name))],
                              selected: zone.name,
                              onChanged: _switchZone,
                            ),
                          ),
                        ),
                        if (editing)
                          IconButton(
                            tooltip: 'Nowa strefa',
                            onPressed: _addZone,
                            icon: const Glyph(AppIcons.plus, size: 16),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Panel po prawej przewija się, gdy jest wyższy od planu. Margines mieści cień.
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: _panelWidth + 32,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: editing
                        ? _inspector(zone, tables, elements)
                        : _livePanel(tables, reservations),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                bottom: 16,
                child: _ViewControls(
                  onUndo: editing && _history.isNotEmpty && !_saving ? _undo : null,
                  onRedo: editing && _future.isNotEmpty && !_saving ? _redo : null,
                  showHistory: editing,
                  onFit: _fit,
                  onZoomIn: () => _zoomBy(1.25),
                  onZoomOut: () => _zoomBy(0.8),
                ),
              ),
              Positioned(
                left: 72,
                bottom: 20,
                child: IgnorePointer(child: _ScaleBar(zone: zone, scale: view.scale, showZone: !editing)),
              ),
              if (editing)
                Positioned(
                  left: 0,
                  right: _panelWidth + 32,
                  bottom: 16,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hint != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _Floating(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: Text(
                                hint,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                              ),
                            ),
                          ),
                        _Floating(
                          padding: const EdgeInsets.all(4),
                          child: IconTabs<_Tool>(
                            options: [for (final t in _Tool.values) (t, t.icon, t.label)],
                            tooltips: [for (final t in _Tool.values) '${t.label}  ${t.shortcut}'],
                            selected: _tool,
                            onChanged: (t) => setState(() {
                              _tool = t;
                              _wallStart = null;
                              _canvasFocus.requestFocus();
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Dopasowuje strefę do widoku (Ctrl+0).
  void _fit() => setState(() {
    _view = null;
    _viewTouched = false;
  });

  /// Przybliża albo oddala wokół środka widocznej części planu (Ctrl+plus, Ctrl+minus).
  void _zoomBy(double factor) {
    final frame = _frame;
    final view = _view;
    if (frame == null || view == null) return;
    setState(() {
      _view = view.zoomAt(frame.area.center, factor, min: frame.minScale, max: frame.maxScale);
      _viewTouched = true;
    });
  }

  Widget _plan(
    FloorZone zone,
    List<DiningTable> inZone,
    List<FloorElement> zoneElements,
    List<PanelReservation> reservations,
    bool editing,
    PlanView view,
  ) {
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

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.digit0, control: true): _fit,
      const SingleActivator(LogicalKeyboardKey.digit0, meta: true): _fit,
      const SingleActivator(LogicalKeyboardKey.equal, control: true): () => _zoomBy(1.25),
      const SingleActivator(LogicalKeyboardKey.equal, control: true, shift: true): () => _zoomBy(1.25),
      const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): () => _zoomBy(1.25),
      const SingleActivator(LogicalKeyboardKey.equal, meta: true): () => _zoomBy(1.25),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): () => _zoomBy(0.8),
      const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): () => _zoomBy(0.8),
      const SingleActivator(LogicalKeyboardKey.minus, meta: true): () => _zoomBy(0.8),
      if (editing) ...{
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copy,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copy,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () => _paste(_clipboard, zone),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () => _paste(_clipboard, zone),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () => _paste(_selectedItems(), zone),
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () => _paste(_selectedItems(), zone),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): _selectAll,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): _selectAll,
      },
    };

    final canvas = FloorCanvas(
      view: view,
      interactive: false,
      zone: zone,
      tables: inZone,
      elements: zoneElements,
      selectedId: null,
      selectedIds: _selection,
      hoveredId: _gesture == null ? _hoverKey : null,
      chairEditKey: editing && _tool == _Tool.select ? _selectedKey : null,
      lookOf: (t) => editing
          ? _editLook(t, overlapping.contains(FloorCanvas.keyOf(t)))
          : _liveLook(t, reservations),
      onTapTable: (_) {},
    );

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        focusNode: _canvasFocus,
        onKeyEvent: _onKey,
        child: DragTarget<_Preset>(
          onWillAcceptWithDetails: (_) => editing,
          onAcceptWithDetails: (d) => _dropPreset(d.data, d.offset),
          builder: (context, _, _) => Listener(
            key: _planKey,
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            onPointerHover: _onPointerHover,
            onPointerSignal: _onPointerSignal,
            onPointerPanZoomStart: _onPanZoomStart,
            onPointerPanZoomUpdate: _onPanZoomUpdate,
            child: MouseRegion(
              cursor: _cursor,
              onExit: (_) {
                if (_hoverKey != null || _pointerPx != null) {
                  setState(() {
                    _hoverKey = null;
                    _pointerPx = null;
                  });
                }
              },
              child: CustomPaint(
                foregroundPainter: _overlay(zone, view, editing),
                child: canvas,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectAll() {
    final frame = _frame;
    if (frame == null) return;
    setState(() {
      _selection
        ..clear()
        ..addAll([for (final e in frame.elements) e.key, for (final t in frame.tables) FloorCanvas.keyOf(t)]);
    });
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
      liveTableLook(t, reservations, _viewTime, seatedCountsNow: true);

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
      return _Floating.card(
        child: PanelCard(
          title: 'Sala teraz',
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
                'Kliknij stolik, żeby zobaczyć jego rezerwacje na dziś. Kółko myszy przybliża plan, '
                'a przeciąganie go przesuwa.',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    final forTable = reservations.where((r) => r.tableIds.contains(table!.id)).toList();
    return _Floating.card(
      child: PanelCard(
        title: 'Stolik ${table.label}',
        trailing: IconButton(
          tooltip: 'Zamknij',
          icon: const Glyph(AppIcons.close, size: 16),
          onPressed: () => setState(_selection.clear),
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
      ),
    );
  }

  Widget _inspector(FloorZone zone, List<DiningTable> tables, List<FloorElement> elements) {
    if (_selection.length > 1) {
      return _Floating.card(
        child: _SelectionInspector(
          count: _selection.length,
          onAlign: (a) => _align(zone, a),
          onDistribute: (axis) => _distribute(zone, axis),
          onDuplicate: () => _paste(_selectedItems(), zone),
          onDelete: _deleteSelection,
          onClose: () => setState(_selection.clear),
        ),
      );
    }
    DiningTable? table;
    for (final t in tables) {
      if (FloorCanvas.keyOf(t) == _selectedKey) table = t;
    }
    FloorElement? element;
    for (final e in elements) {
      if (e.key == _selectedKey) element = e;
    }
    if (element != null) {
      return _Floating.card(
        child: _ElementInspector(
          key: ValueKey('element-${element.key}-$_undoGeneration'),
          element: element,
          onChanged: (change) => _updateElement(element!, change),
          onDuplicate: () => _paste([element!], zone),
          onDelete: () => _deleteElement(element!),
          onClose: () => setState(_selection.clear),
        ),
      );
    }
    if (table == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Floating.card(
            child: _Library(
              scale: _view?.scale ?? 1,
              onAdd: (preset) => _addPreset(preset, zone),
            ),
          ),
          const SizedBox(height: 12),
          _Floating.card(
            child: _ZoneInspector(
              key: ValueKey('strefa-${zone.name}-$_undoGeneration'),
              zone: zone,
              tableCount: tables.where((t) => t.zone == zone.name).length,
              onChanged: (updated) => _updateZone(zone, updated),
              onDelete: () => _deleteZone(zone),
            ),
          ),
        ],
      );
    }
    return _Floating.card(
      child: _TableInspector(
        key: ValueKey('stolik-${FloorCanvas.keyOf(table)}-$_undoGeneration'),
        table: table,
        zones: _zones.map((z) => z.name).toList(),
        onChanged: (change) => _update(table!, change),
        onDuplicate: () => _paste([table!], zone),
        onDelete: () => _deleteTable(table!),
        onClose: () => setState(_selection.clear),
      ),
    );
  }
}

/// Pływający panel nad planem: tło karty, cienka obwódka i miękki cień, jak panele w UniFi Design Center.
class _Floating extends StatelessWidget {
  const _Floating({required this.child, this.padding = EdgeInsets.zero}) : card = false;

  /// Karta (Card, PanelCard) dostaje tylko cień, bo tło i obwódkę ma swoje.
  const _Floating.card({required this.child}) : padding = EdgeInsets.zero, card = true;

  final Widget child;
  final EdgeInsets padding;
  final bool card;

  static List<BoxShadow> shadow(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.45 : 0.08),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (card) {
      return DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: shadow(context)),
        child: child,
      );
    }
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.ring),
        boxShadow: shadow(context),
      ),
      child: child,
    );
  }
}

/// Przyciski widoku w lewym dolnym rogu: cofnij i ponów (w edycji), dopasuj, przybliż i oddal.
class _ViewControls extends StatelessWidget {
  const _ViewControls({
    required this.showHistory,
    required this.onUndo,
    required this.onRedo,
    required this.onFit,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final bool showHistory;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onFit;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    Widget button(String tooltip, AppIconData icon, VoidCallback? onPressed) => IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Glyph(icon, size: 18),
    );
    Widget divider() => Container(
      width: 24,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: AppColors.ring,
    );
    return _Floating(
      padding: const EdgeInsets.all(2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHistory) ...[
            button('Cofnij  Ctrl+Z', AppIcons.undo, onUndo),
            button('Ponów  Ctrl+Shift+Z', AppIcons.redo, onRedo),
            divider(),
          ],
          button('Dopasuj do ekranu  Ctrl+0', AppIcons.cornersOut, onFit),
          button('Przybliż  Ctrl+plus', AppIcons.plus, onZoomIn),
          button('Oddal  Ctrl+minus', AppIcons.minus, onZoomOut),
        ],
      ),
    );
  }
}

/// Podziałka w lewym dolnym rogu: odcinek o okrągłej długości w bieżącym przybliżeniu i wymiary strefy.
class _ScaleBar extends StatelessWidget {
  const _ScaleBar({required this.zone, required this.scale, required this.showZone});

  final FloorZone zone;
  final double scale;

  /// Wymiary strefy obok podziałki. W edycji stoją przy krawędziach planu, bo tu jest pasek narzędzi.
  final bool showZone;

  @override
  Widget build(BuildContext context) {
    // Najdłuższy okrągły odcinek, który zmieści się w 120 pikselach.
    const steps = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000];
    final cm = steps.lastWhere((s) => s * scale <= 120, orElse: () => steps.first);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: AppColors.textMuted,
      fontFeatures: _tabular,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cm >= 100 ? metersLabel(cm.toDouble()) : '$cm cm', style: style),
            const SizedBox(height: 3),
            Container(
              width: cm * scale,
              height: 6,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: AppColors.textMuted, width: 1.5),
                  right: BorderSide(color: AppColors.textMuted, width: 1.5),
                  bottom: BorderSide(color: AppColors.textMuted, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        if (showZone) ...[
          const SizedBox(width: 14),
          Text(
            'Strefa ${metersLabel(zone.widthCm.toDouble()).replaceAll(' m', '')} × ${metersLabel(zone.heightCm.toDouble())}',
            style: style,
          ),
        ],
      ],
    );
  }
}

/// „Dodaj na plan”: gotowe stoliki, miejsce i element stały do przeciągnięcia na plan.
class _Library extends StatelessWidget {
  const _Library({required this.scale, required this.onAdd});

  /// Bieżąca skala planu: przeciągany obiekt ma od razu swój rozmiar na planie.
  final double scale;
  final ValueChanged<_Preset> onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PanelCard(
      title: 'Dodaj na plan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Przeciągnij na plan albo kliknij, żeby dodać na środku widoku.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _presets)
                    SizedBox(width: width, child: _PresetTile(preset: p, scale: scale, onTap: () => onAdd(p))),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatefulWidget {
  const _PresetTile({required this.preset, required this.scale, required this.onTap});

  final _Preset preset;
  final double scale;
  final VoidCallback onTap;

  @override
  State<_PresetTile> createState() => _PresetTileState();
}

class _PresetTileState extends State<_PresetTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = widget.preset;
    final reach = _presetReach(p);
    // Obiekt pod kursorem w skali planu, środkiem na kursorze.
    final ghost = Transform.translate(
      offset: Offset(-reach * widget.scale, -reach * widget.scale),
      child: Opacity(
        opacity: 0.85,
        child: CustomPaint(
          size: Size.square(reach * 2 * widget.scale),
          painter: _PresetPainter(p, scale: widget.scale, line: AppColors.accent),
        ),
      ),
    );
    return Draggable<_Preset>(
      data: p,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: ghost,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            decoration: BoxDecoration(
              color: _hovered ? AppColors.surfaceRaised : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _hovered ? AppColors.accent.withValues(alpha: 0.5) : AppColors.ring),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  width: 44,
                  child: CustomPaint(
                    painter: _PresetPainter(p, scale: 44 / (reach * 2), line: planLine),
                  ),
                ),
                const SizedBox(height: 6),
                Text(p.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelMedium),
                Text(
                  p.size,
                  maxLines: 1,
                  style: text.labelSmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Promień obejmujący gotowy obiekt razem z krzesłami, w cm.
double _presetReach(_Preset p) {
  final table = p.sample;
  var reach = math.sqrt(p.width * p.width + p.height * p.height) / 2;
  if (p.kind == _PresetKind.table) {
    for (final c in autoChairs(table)) {
      reach = math.max(reach, math.sqrt(c.x * c.x + c.y * c.y) + chairDiameterCm / 2);
    }
  }
  return reach;
}

/// Gotowy obiekt narysowany w skali: blat z krzesłami albo szary element stały.
class _PresetPainter extends CustomPainter {
  _PresetPainter(this.preset, {required this.scale, required this.line});

  final _Preset preset;
  final double scale;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    final p = preset;
    final rect = Rect.fromCenter(center: Offset.zero, width: p.width * scale, height: p.height * scale);
    if (p.kind == _PresetKind.element) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = AppColors.palette.brightness == Brightness.dark ? const Color(0xFF45454C) : const Color(0xFFD6D9D7),
      );
      return;
    }
    final chair = Paint()..color = planChair;
    if (p.kind == _PresetKind.table) {
      for (final c in autoChairs(p.sample)) {
        canvas.drawCircle(Offset(c.x, c.y) * scale, chairDiameterCm / 2 * scale, chair);
      }
    }
    final fill = Paint()..color = AppColors.surfaceRaised;
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (p.shape == TableShape.round) {
      canvas
        ..drawOval(rect, fill)
        ..drawOval(rect, stroke);
    } else {
      canvas
        ..drawRect(rect, fill)
        ..drawRect(rect, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _PresetPainter old) =>
      old.preset != preset || old.scale != scale || old.line != line;
}

/// Kilka zaznaczonych obiektów: wyrównanie, równe odstępy, duplikowanie i usuwanie naraz.
class _SelectionInspector extends StatelessWidget {
  const _SelectionInspector({
    required this.count,
    required this.onAlign,
    required this.onDistribute,
    required this.onDuplicate,
    required this.onDelete,
    required this.onClose,
  });

  final int count;
  final ValueChanged<_Align> onAlign;
  final ValueChanged<Axis> onDistribute;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget button(String label, VoidCallback? onPressed) => Expanded(
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 6),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
      ),
    );
    Widget row(List<Widget> buttons) => Row(
      children: [
        for (final (i, b) in buttons.indexed) ...[if (i > 0) const SizedBox(width: 6), b],
      ],
    );
    return PanelCard(
      title: 'Zaznaczone: $count',
      trailing: IconButton(
        tooltip: 'Odznacz',
        icon: const Glyph(AppIcons.close, size: 16),
        onPressed: onClose,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Wyrównaj w poziomie', style: text.titleSmall),
          const SizedBox(height: 8),
          row([
            button('Do lewej', () => onAlign(_Align.left)),
            button('Środkiem', () => onAlign(_Align.centerX)),
            button('Do prawej', () => onAlign(_Align.right)),
          ]),
          const SizedBox(height: 14),
          Text('Wyrównaj w pionie', style: text.titleSmall),
          const SizedBox(height: 8),
          row([
            button('Do góry', () => onAlign(_Align.top)),
            button('Środkiem', () => onAlign(_Align.centerY)),
            button('Do dołu', () => onAlign(_Align.bottom)),
          ]),
          const SizedBox(height: 14),
          Text('Równe odstępy', style: text.titleSmall),
          const SizedBox(height: 8),
          row([
            button('W poziomie', count >= 3 ? () => onDistribute(Axis.horizontal) : null),
            button('W pionie', count >= 3 ? () => onDistribute(Axis.vertical) : null),
          ]),
          const SizedBox(height: 14),
          Text(
            'Przeciągnij jeden z nich, żeby przesunąć wszystkie. Shift albo Ctrl dodaje do zaznaczenia, '
            'strzałki przesuwają o 10 cm.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onDuplicate,
                icon: const Glyph(AppIcons.copy, size: 16),
                label: const Text('Duplikuj'),
              ),
              const Spacer(),
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Usuń'),
              ),
            ],
          ),
        ],
      ),
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
  void didUpdateWidget(covariant _ZoneInspector old) {
    super.didUpdateWidget(old);
    // Wymiary zmienione przeciąganiem krawędzi strefy na planie.
    if (old.zone.widthCm != widget.zone.widthCm) _width.text = '${widget.zone.widthCm}';
    if (old.zone.heightCm != widget.zone.heightCm) _height.text = '${widget.zone.heightCm}';
  }

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
            'Stolików w strefie: ${widget.tableCount}. Kliknij stolik na planie, żeby zmienić jego wymiary, liczbę miejsc '
            'i obrót. Wymiary strefy zmienisz też, przeciągając jej prawą albo dolną krawędź.',
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
    widget.onChanged((t) => resizedTable(t, w, h));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.table;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
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
  void didUpdateWidget(covariant _ElementInspector old) {
    super.didUpdateWidget(old);
    // Wymiary zmienione uchwytami na planie.
    if (old.element.widthCm != widget.element.widthCm) _width.text = '${widget.element.widthCm}';
    if (old.element.heightCm != widget.element.heightCm) _height.text = '${widget.element.heightCm}';
  }

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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
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
            'Ściana, bar, filar albo donica. Na planie jest jasnoszary, bez napisu, i nie da się go zarezerwować. '
            'Wymiary i obrót zmienisz też uchwytami na planie.',
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
