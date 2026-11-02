part of 'floor_screen.dart';

// Obsługa planu w Edycji sali jak w UniFi Design Center: kółko myszy przybliża wokół kursora,
// przeciąganie pustego miejsca przesuwa widok (z Shift albo Ctrl zaznacza ramką), spacja albo środkowy
// przycisk też przesuwa widok, prawy przycisk otwiera menu obiektu, a narzędzia z paska rysują ściany
// i elementy oraz stawiają stoliki. Stolik łapie się za blat albo za krzesło.

/// Pozycje menu pod prawym przyciskiem myszy.
enum _MenuAction { duplicate, rotate, copy, delete, paste, selectAll, fit }

/// Plan z ostatniego rysowania: mysz i klawiatura liczą na tym samym widoku, który widać.
class _PlanFrame {
  const _PlanFrame({
    required this.zone,
    required this.tables,
    required this.elements,
    required this.view,
    required this.area,
    required this.fitScale,
    required this.editing,
  });

  final FloorZone zone;
  final List<DiningTable> tables;
  final List<FloorElement> elements;
  final PlanView view;

  /// Część planu wolna od pływających paneli.
  final Rect area;

  /// Skala, w której cała strefa mieści się w [area].
  final double fitScale;
  final bool editing;

  double get minScale => fitScale * 0.4;
  double get maxScale => math.max(4, fitScale * 2);
}

/// Rozpoczęty gest na planie. [pointer] to przycisk myszy albo palec, który go prowadzi.
sealed class _Gesture {
  _Gesture(this.pointer);

  final int pointer;

  /// Stan sprzed gestu jest już w historii. Zapisujemy go przy pierwszym ruchu,
  /// więc samo kliknięcie uchwytu nie dodaje pustego kroku do „Cofnij”.
  bool remembered = false;
}

/// Wciśnięcie, zanim wiadomo, czy to kliknięcie, czy przeciąganie.
class _Press extends _Gesture {
  _Press(
    super.pointer, {
    required this.downPx,
    required this.downCm,
    required this.hitKey,
    required this.additive,
    required this.touch,
  });

  final Offset downPx;
  final Offset downCm;
  final String? hitKey;

  /// Shift albo Ctrl: kliknięcie dodaje do zaznaczenia albo z niego zdejmuje.
  final bool additive;
  final bool touch;
}

class _PanGesture extends _Gesture {
  _PanGesture(super.pointer, this.lastPx);

  Offset lastPx;
}

class _MoveGesture extends _Gesture {
  _MoveGesture(
    super.pointer, {
    required this.startCm,
    required this.starts,
    required this.bounds,
    required this.anchor,
  });

  final Offset startCm;

  /// Środek złapanego obiektu na początku gestu: bez linii prowadzących staje on na kratce co 10 cm.
  final Offset anchor;

  /// Środki przesuwanych obiektów na początku gestu.
  final Map<String, Offset> starts;

  /// Wspólny obrys przesuwanych obiektów na początku gestu.
  final Rect bounds;
}

class _ResizeGesture extends _Gesture {
  _ResizeGesture(super.pointer, this.start, this.handle);

  final Object start;
  final Offset handle;
}

class _RotateGesture extends _Gesture {
  _RotateGesture(super.pointer, this.start);

  final Object start;
}

class _ChairGesture extends _Gesture {
  _ChairGesture(super.pointer, this.tableKey, this.index);

  final String tableKey;
  final int index;
}

class _BandGesture extends _Gesture {
  _BandGesture(super.pointer, this.startCm, this.base);

  final Offset startCm;

  /// Zaznaczenie sprzed ramki (z Shift ramka do niego dodaje).
  final Set<String> base;
}

class _ZoneGesture extends _Gesture {
  _ZoneGesture(super.pointer, this.zoneName, {required this.width, required this.height});

  final String zoneName;
  final bool width;
  final bool height;
}

class _DrawGesture extends _Gesture {
  _DrawGesture(super.pointer, this.startCm);

  final Offset startCm;
}

/// Dwa palce: przybliżanie i przesuwanie widoku.
class _PinchGesture extends _Gesture {
  _PinchGesture(this.lastFocal, this.lastDistance) : super(-1);

  Offset lastFocal;
  double lastDistance;
}

/// Uchwyt na ekranie: zmiana wymiarów ([resize]: strona −1, 0 albo 1 na osiach kształtu), obrót,
/// krzesło zaznaczonego stolika ([chair]) albo krawędź strefy ([zoneWidth], [zoneHeight]).
class _Handle {
  const _Handle(
    this.px, {
    this.resize,
    this.rotate = false,
    this.chair,
    this.zoneWidth = false,
    this.zoneHeight = false,
    this.from,
  });

  final Offset px;
  final Offset? resize;
  final bool rotate;
  final int? chair;
  final bool zoneWidth;
  final bool zoneHeight;

  /// Początek kreski prowadzącej do uchwytu obrotu (środek górnej krawędzi).
  final Offset? from;

  bool get isZone => zoneWidth || zoneHeight;
}

extension _PlanInput on _FloorScreenState {
  bool get _shift => HardwareKeyboard.instance.isShiftPressed;
  bool get _alt => HardwareKeyboard.instance.isAltPressed;
  bool get _ctrl => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;

  // W edycji liczymy na bieżącej kopii roboczej, bo między rysowaniami może przyjść kilka zdarzeń.
  FloorZone _zoneNow(_PlanFrame f) =>
      f.editing ? _zones.firstWhere((z) => z.name == f.zone.name, orElse: () => f.zone) : f.zone;

  List<DiningTable> _zoneTables(_PlanFrame f) => f.editing
      ? [
          for (final t in _tables)
            if (t.zone == f.zone.name) t,
        ]
      : f.tables;

  List<FloorElement> _zoneElements(_PlanFrame f) => f.editing
      ? [
          for (final e in _elements)
            if (e.zone == f.zone.name) e,
        ]
      : f.elements;

  String _keyOf(Object item) => item is DiningTable ? FloorCanvas.keyOf(item) : (item as FloorElement).key;

  /// Czy obiekt stoi w strefie planu. Stolik przeniesiony w panelu do innej strefy zostaje zaznaczony,
  /// ale na tym planie nie ma już uchwytów i nie jedzie z resztą zaznaczenia.
  bool _inZone(Object item, _PlanFrame f) =>
      (item is DiningTable ? item.zone : (item as FloorElement).zone) == f.zone.name;

  Object? _itemByKey(String key) {
    for (final t in _tables) {
      if (FloorCanvas.keyOf(t) == key) return t;
    }
    for (final e in _elements) {
      if (e.key == key) return e;
    }
    return null;
  }

  /// Punkt na kratce co 10 cm (z Alt co 1 cm).
  Offset _snap(Offset cm) =>
      _alt ? Offset(cm.dx.roundToDouble(), cm.dy.roundToDouble()) : snapPoint(cm, 10);

  /// Stolik albo element pod punktem planu, od wierzchu. Najpierw blaty, potem krzesła (krzesło należy
  /// do swojego stolika, więc za nie też się go łapie), na końcu elementy stałe. Na żywo tylko stoliki.
  Object? _hitItem(_PlanFrame f, Offset cm) {
    final tolerance = 4 / f.view.scale;
    final tables = _zoneTables(f).reversed.toList();
    for (final t in tables) {
      if (PlanBox.of(t).contains(cm, tolerance: tolerance)) return t;
    }
    for (final t in tables) {
      final box = PlanBox.of(t);
      for (final c in chairsOf(t)) {
        if ((box.toPlan(Offset(c.x, c.y)) - cm).distance <= chairDiameterCm / 2 + tolerance) return t;
      }
    }
    if (!f.editing) return null;
    for (final e in _zoneElements(f).reversed) {
      if (PlanBox.of(e).contains(cm, tolerance: tolerance)) return e;
    }
    return null;
  }

  /// Uchwyty na ekranie: wymiary, obrót i krzesła zaznaczonego obiektu oraz krawędzie strefy.
  List<_Handle> _handles(_PlanFrame f) {
    if (!f.editing || _tool != _Tool.select) return const [];
    final view = f.view;
    final list = <_Handle>[];
    final key = _selectedKey;
    final item = key == null ? null : _itemByKey(key);
    if (item != null && _inZone(item, f) && !(item is DiningTable && item.isSeat)) {
      final box = PlanBox.of(item);
      final hw = box.size.width / 2;
      final hh = box.size.height / 2;
      Offset at(double x, double y) => view.toScreen(box.toPlan(Offset(x, y)));
      // Uchwyty krótkiego boku zlewałyby się w jeden: ściana ma tylko uchwyty na końcach.
      final wide = box.size.width * view.scale >= 24;
      final tall = box.size.height * view.scale >= 24;
      if (wide && tall) {
        for (final sx in [-1.0, 1.0]) {
          for (final sy in [-1.0, 1.0]) {
            list.add(_Handle(at(sx * hw, sy * hh), resize: Offset(sx, sy)));
          }
        }
      }
      if (!box.round) {
        if (wide) {
          list
            ..add(_Handle(at(-hw, 0), resize: const Offset(-1, 0)))
            ..add(_Handle(at(hw, 0), resize: const Offset(1, 0)));
        }
        if (tall) {
          list
            ..add(_Handle(at(0, -hh), resize: const Offset(0, -1)))
            ..add(_Handle(at(0, hh), resize: const Offset(0, 1)));
        }
        // Obrót nad krzesłami, żeby uchwyt na nie nie nachodził.
        final reach = item is DiningTable ? hh + chairGapCm + chairDiameterCm : hh;
        final up = rotateOffset(const Offset(0, -1), box.rotation);
        list.add(_Handle(at(0, -reach) + up * 18, rotate: true, from: at(0, -hh)));
      }
      if (item is DiningTable) {
        final chairs = chairsOf(item);
        for (var i = 0; i < chairs.length; i++) {
          list.add(_Handle(at(chairs[i].x, chairs[i].y), chair: i));
        }
      }
    }
    final zone = _zoneNow(f);
    final w = zone.widthCm.toDouble();
    final h = zone.heightCm.toDouble();
    list
      ..add(_Handle(view.toScreen(Offset(w, h / 2)), zoneWidth: true))
      ..add(_Handle(view.toScreen(Offset(w / 2, h)), zoneHeight: true))
      ..add(_Handle(view.toScreen(Offset(w, h)), zoneWidth: true, zoneHeight: true));
    return list;
  }

  /// Uchwyt zaznaczonego obiektu pod kursorem: najpierw wymiary i obrót, potem krzesła.
  _Handle? _hitObjectHandle(_PlanFrame f, Offset px) {
    _Handle? chair;
    for (final h in _handles(f)) {
      if (h.isZone) continue;
      final d = (h.px - px).distance;
      if (h.chair == null && d <= 10) return h;
      if (h.chair != null && chair == null && d <= chairDiameterCm / 2 * f.view.scale + 3) chair = h;
    }
    return chair;
  }

  _Handle? _hitZoneHandle(_PlanFrame f, Offset px) {
    for (final h in _handles(f)) {
      if (h.isZone && (h.px - px).distance <= 10) return h;
    }
    return null;
  }

  MouseCursor _handleCursor(_Handle h) {
    if (h.chair != null) return SystemMouseCursors.move;
    if (h.rotate) return SystemMouseCursors.grab;
    if (h.zoneWidth && h.zoneHeight) return SystemMouseCursors.resizeUpLeftDownRight;
    if (h.zoneWidth) return SystemMouseCursors.resizeLeftRight;
    if (h.zoneHeight) return SystemMouseCursors.resizeUpDown;
    final key = _selectedKey;
    final item = key == null ? null : _itemByKey(key);
    if (item == null) return SystemMouseCursors.move;
    // Strzałka według kierunku uchwytu na ekranie, po obrocie kształtu.
    final dir = rotateOffset(h.resize!, PlanBox.of(item).rotation);
    final angle = ((math.atan2(dir.dy, dir.dx) * 180 / math.pi) % 180 + 180) % 180;
    if (angle < 22.5 || angle >= 157.5) return SystemMouseCursors.resizeLeftRight;
    if (angle < 67.5) return SystemMouseCursors.resizeUpLeftDownRight;
    if (angle < 112.5) return SystemMouseCursors.resizeUpDown;
    return SystemMouseCursors.resizeUpRightDownLeft;
  }

  void _onPointerDown(PointerDownEvent e) {
    final f = _frame;
    if (f == null) return;
    _canvasFocus.requestFocus();
    final touch = e.kind == PointerDeviceKind.touch;
    if (touch) {
      _touches[e.pointer] = e.localPosition;
      if (_touches.length == 2) {
        _startPinch();
        return;
      }
      if (_touches.length > 2) return;
    }
    final px = e.localPosition;
    final cm = f.view.toCm(px);
    _pointerPx = px;

    if (e.buttons & kSecondaryMouseButton != 0) {
      // Prawy przycisk kończy rysowanie ściany, a przy zaznaczaniu otwiera menu obiektu albo planu.
      if (_wallStart != null) {
        _finishWall();
      } else if (f.editing && _tool == _Tool.select && _gesture == null) {
        _contextMenu(f, e.position, cm);
      }
      return;
    }
    if (e.buttons & kMiddleMouseButton != 0 || _spaceDown || (f.editing && _tool == _Tool.pan)) {
      _gesture = _PanGesture(e.pointer, px);
      _set(() => _cursor = SystemMouseCursors.grabbing);
      return;
    }
    if (!f.editing) {
      final hit = _hitItem(f, cm);
      _gesture = _Press(
        e.pointer,
        downPx: px,
        downCm: cm,
        hitKey: hit == null ? null : _keyOf(hit),
        additive: false,
        touch: touch,
      );
      return;
    }

    switch (_tool) {
      case _Tool.wall:
        _wallClick(f, px, cm);
        return;
      case _Tool.element:
        _gesture = _DrawGesture(e.pointer, _snap(cm));
        return;
      case _Tool.table || _Tool.seat:
        _addTable(_zoneNow(f), seat: _tool == _Tool.seat, at: _snap(cm));
        _set(() => _tool = _Tool.select);
        return;
      case _Tool.select || _Tool.pan:
        break;
    }

    final handle = _hitObjectHandle(f, px);
    final selected = _selectedKey == null ? null : _itemByKey(_selectedKey!);
    if (handle != null && selected != null) {
      _gesture = switch (handle) {
        _Handle(chair: final chair?) => _ChairGesture(e.pointer, _keyOf(selected), chair),
        _Handle(rotate: true) => _RotateGesture(e.pointer, selected),
        _ => _ResizeGesture(e.pointer, selected, handle.resize!),
      };
      return;
    }
    final hit = _hitItem(f, cm);
    if (hit == null) {
      final zoneHandle = _hitZoneHandle(f, px);
      if (zoneHandle != null) {
        _gesture = _ZoneGesture(
          e.pointer,
          f.zone.name,
          width: zoneHandle.zoneWidth,
          height: zoneHandle.zoneHeight,
        );
        return;
      }
    }
    final key = hit == null ? null : _keyOf(hit);
    final additive = _shift || _ctrl;
    if (key != null && !additive && !_selection.contains(key)) _set(() => _select(key));
    _gesture = _Press(e.pointer, downPx: px, downCm: cm, hitKey: key, additive: additive, touch: touch);
  }

  void _onPointerMove(PointerMoveEvent e) {
    final f = _frame;
    if (f == null) return;
    if (_touches.containsKey(e.pointer)) {
      _touches[e.pointer] = e.localPosition;
      if (_gesture case final _PinchGesture pinch) {
        _updatePinch(f, pinch);
        return;
      }
    }
    final g = _gesture;
    if (g == null || g.pointer != e.pointer) return;
    final px = e.localPosition;
    final cm = f.view.toCm(px);
    _pointerPx = px;
    if (g is _ResizeGesture || g is _RotateGesture || g is _ChairGesture || g is _ZoneGesture) {
      if (!g.remembered) _remember();
      g.remembered = true;
    }
    switch (g) {
      case _Press():
        if ((px - g.downPx).distance < (g.touch ? 8 : 4)) return;
        if (!f.editing || (g.hitKey == null && !g.additive)) {
          // Puste miejsce (i wszystko na żywo) przesuwa widok jak mapę; ramka zaznaczania tylko z Shift albo Ctrl.
          final pan = _PanGesture(g.pointer, g.downPx);
          _gesture = pan;
          _panTo(pan, px);
        } else if (g.hitKey case final key?) {
          if (g.additive) _selection.add(key);
          final items = _selectedItems().where((item) => _inZone(item, f)).toList();
          if (items.isEmpty) return;
          _remember();
          final starts = {for (final item in items) _keyOf(item): PlanBox.of(item).center};
          final bounds = items.map((i) => PlanBox.of(i).bounds).reduce((a, b) => a.expandToInclude(b));
          final move = _MoveGesture(
            g.pointer,
            startCm: g.downCm,
            starts: starts,
            bounds: bounds,
            anchor: starts[key] ?? bounds.center,
          );
          _gesture = move;
          _moveTo(f, move, cm);
        } else {
          final band = _BandGesture(g.pointer, g.downCm, g.additive ? {..._selection} : {});
          _gesture = band;
          _bandTo(f, band, cm);
        }
      case _PanGesture():
        _panTo(g, px);
      case _MoveGesture():
        _moveTo(f, g, cm);
      case _ResizeGesture():
        _resizeTo(f, g, cm);
      case _RotateGesture():
        _rotateTo(g, cm);
      case _ChairGesture():
        _chairTo(g, cm);
      case _BandGesture():
        _bandTo(f, g, cm);
      case _ZoneGesture():
        _zoneTo(g, cm);
      case _DrawGesture():
        _drawTo(g, cm);
      case _PinchGesture():
        break;
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _touches.remove(e.pointer);
    final f = _frame;
    final g = _gesture;
    if (g is _PinchGesture) {
      if (_touches.isEmpty) _gesture = null;
      return;
    }
    if (g == null || g.pointer != e.pointer || f == null) return;
    _gesture = null;
    switch (g) {
      case _Press():
        _click(g);
      case _DrawGesture():
        _finishDraw(f, g);
      default:
        break;
    }
    _clearFeedback();
    if (e.kind == PointerDeviceKind.mouse) _hover(f, e.localPosition);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _touches.remove(e.pointer);
    final g = _gesture;
    if (g == null) return;
    if (g is _PinchGesture ? _touches.isNotEmpty : g.pointer != e.pointer) return;
    _gesture = null;
    _clearFeedback();
  }

  /// Po geście znikają ramka, linie prowadzące i wymiar przy kursorze.
  void _clearFeedback() => _set(() {
    _band = null;
    _draft = null;
    _measure = null;
    _guides = (x: null, y: null);
  });

  void _click(_Press p) {
    final key = p.hitKey;
    _set(() {
      if (key == null) {
        if (!p.additive) _selection.clear();
      } else if (p.additive) {
        if (!_selection.remove(key)) _selection.add(key);
      } else {
        _select(key);
      }
    });
  }

  void _onPointerHover(PointerHoverEvent e) {
    final f = _frame;
    if (f != null) _hover(f, e.localPosition);
  }

  /// Kursor i podświetlenie obiektu pod myszą.
  void _hover(_PlanFrame f, Offset px) {
    final cm = f.view.toCm(px);
    String? key;
    MouseCursor cursor;
    if (_spaceDown || (f.editing && _tool == _Tool.pan)) {
      cursor = SystemMouseCursors.grab;
    } else if (f.editing && _tool != _Tool.select) {
      cursor = SystemMouseCursors.precise;
    } else {
      final item = _hitItem(f, cm);
      final handle = f.editing ? (_hitObjectHandle(f, px) ?? (item == null ? _hitZoneHandle(f, px) : null)) : null;
      if (handle != null) {
        cursor = _handleCursor(handle);
      } else {
        key = item == null ? null : _keyOf(item);
        // Puste miejsce: rączka, bo przeciąganie przesuwa widok (z Shift albo Ctrl ramka zaznaczania).
        cursor = item == null
            ? (f.editing && (_shift || _ctrl) ? SystemMouseCursors.precise : SystemMouseCursors.grab)
            : (f.editing ? SystemMouseCursors.move : SystemMouseCursors.click);
      }
    }
    _pointerPx = px;
    // Rysowana ściana idzie za kursorem, więc wtedy odświeżamy przy każdym ruchu.
    final drawingWall = f.editing && _tool == _Tool.wall && _wallStart != null;
    if (key != _hoverKey || cursor != _cursor || drawingWall) {
      _set(() {
        _hoverKey = key;
        _cursor = cursor;
      });
    }
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final f = _frame;
      final view = _view;
      if (f == null || view == null || event is! PointerScrollEvent) return;
      // Kółko myszy przybliża wokół kursora, jak w UniFi Design Center.
      final factor = math.pow(2, -event.scrollDelta.dy / 400).toDouble();
      _set(() {
        _view = view.zoomAt(event.localPosition, factor, min: f.minScale, max: f.maxScale);
        _viewTouched = true;
      });
    });
  }

  void _onPanZoomStart(PointerPanZoomStartEvent e) => _panZoomScale = 1;

  /// Gładzik: dwa palce przesuwają widok, rozsunięcie przybliża.
  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    final f = _frame;
    final view = _view;
    if (f == null || view == null) return;
    var next = view.pannedBy(e.panDelta);
    if (e.scale != _panZoomScale && _panZoomScale > 0) {
      next = next.zoomAt(e.localPosition, e.scale / _panZoomScale, min: f.minScale, max: f.maxScale);
      _panZoomScale = e.scale;
    }
    _set(() {
      _view = next;
      _viewTouched = true;
    });
  }

  void _startPinch() {
    final points = _touches.values.take(2).toList();
    // Drugi palec przerywa rozpoczęty gest (to, co już przesunięte, zostaje) i zaczyna przybliżanie.
    _gesture = _PinchGesture((points[0] + points[1]) / 2, (points[0] - points[1]).distance);
    _clearFeedback();
  }

  void _updatePinch(_PlanFrame f, _PinchGesture g) {
    final view = _view;
    if (_touches.length < 2 || view == null) return;
    final points = _touches.values.take(2).toList();
    final focal = (points[0] + points[1]) / 2;
    final distance = (points[0] - points[1]).distance;
    var next = view.pannedBy(focal - g.lastFocal);
    if (g.lastDistance > 0 && distance > 0) {
      next = next.zoomAt(focal, distance / g.lastDistance, min: f.minScale, max: f.maxScale);
    }
    g
      ..lastFocal = focal
      ..lastDistance = distance;
    _set(() {
      _view = next;
      _viewTouched = true;
    });
  }

  void _panTo(_PanGesture g, Offset px) {
    final view = _view;
    if (view == null) return;
    final delta = px - g.lastPx;
    g.lastPx = px;
    _set(() {
      _view = view.pannedBy(delta);
      _viewTouched = true;
      _cursor = SystemMouseCursors.grabbing;
    });
  }

  /// Przesuwa zaznaczenie za kursorem: krawędzie i środki przyciągają się do innych obiektów
  /// i strefy (linie prowadzące), a bez nich złapany obiekt staje na kratce co 10 cm. Alt wyłącza przyciąganie.
  void _moveTo(_PlanFrame f, _MoveGesture m, Offset cm) {
    final zone = _zoneNow(f);
    var d = cm - m.startCm;
    double? guideX;
    double? guideY;
    if (!_alt) {
      final others = [
        for (final item in <Object>[..._zoneElements(f), ..._zoneTables(f)])
          if (!m.starts.containsKey(_keyOf(item))) PlanBox.of(item).bounds,
      ];
      final s = snapToGuides(
        m.bounds.shift(d),
        others,
        Size(zone.widthCm.toDouble(), zone.heightCm.toDouble()),
        6 / f.view.scale,
      );
      final a = m.anchor;
      d = Offset(
        s.dx == null ? snapTo(a.dx + d.dx, 10) - a.dx : d.dx + s.dx!,
        s.dy == null ? snapTo(a.dy + d.dy, 10) - a.dy : d.dy + s.dy!,
      );
      guideX = s.guideX;
      guideY = s.guideY;
    }
    int x(double v) => v.round().clamp(0, zone.widthCm);
    int y(double v) => v.round().clamp(0, zone.heightCm);
    _set(() {
      _tables = [
        for (final t in _tables)
          if (m.starts[FloorCanvas.keyOf(t)] case final s?)
            t.copyWith(xCm: x(s.dx + d.dx), yCm: y(s.dy + d.dy))
          else
            t,
      ];
      _elements = [
        for (final e in _elements)
          if (m.starts[e.key] case final s?) e.copyWith(xCm: x(s.dx + d.dx), yCm: y(s.dy + d.dy)) else e,
      ];
      _guides = (x: guideX, y: guideY);
      _dirty = true;
    });
  }

  /// Zmiana wymiarów uchwytem co 5 cm (z Alt co 1 cm); przeciwna krawędź zostaje w miejscu.
  void _resizeTo(_PlanFrame f, _ResizeGesture g, Offset cm) {
    final zone = _zoneNow(f);
    final start = g.start;
    final isTable = start is DiningTable;
    final box = PlanBox.of(start);
    final r = resizeBox(box, g.handle, cm, min: isTable ? 30 : 5, max: isTable ? 1000 : 5000, step: _alt ? 1 : 5);
    final w = r.size.width.round();
    final h = r.size.height.round();
    final x = r.center.dx.round().clamp(0, zone.widthCm);
    final y = r.center.dy.round().clamp(0, zone.heightCm);
    _set(() {
      switch (start) {
        case DiningTable():
          final key = FloorCanvas.keyOf(start);
          _tables = [
            for (final t in _tables)
              if (FloorCanvas.keyOf(t) == key) resizedTable(start, w, h).copyWith(xCm: x, yCm: y) else t,
          ];
        case FloorElement():
          _elements = [
            for (final e in _elements)
              if (e.key == start.key) e.copyWith(widthCm: w, heightCm: h, xCm: x, yCm: y) else e,
          ];
      }
      _measure = box.round ? 'Ø $w cm' : '$w × $h cm';
      _dirty = true;
    });
  }

  /// Obrót uchwytem co 15° (z Shift co 1°).
  void _rotateTo(_RotateGesture g, Offset cm) {
    final start = g.start;
    final degrees = rotationTowards(PlanBox.of(start).center, cm, step: _shift ? 1 : 15);
    _set(() {
      switch (start) {
        case DiningTable():
          final key = FloorCanvas.keyOf(start);
          _tables = [
            for (final t in _tables)
              if (FloorCanvas.keyOf(t) == key) t.copyWith(rotation: degrees) else t,
          ];
        case FloorElement():
          _elements = [
            for (final e in _elements)
              if (e.key == start.key) e.copyWith(rotation: degrees) else e,
          ];
      }
      _measure = '$degrees°';
      _dirty = true;
    });
  }

  /// Krzesło idzie za kursorem, ale zostaje w pasie wokół blatu.
  /// Przy pierwszej zmianie automatyczne rozstawienie staje się własnym.
  void _chairTo(_ChairGesture g, Offset cm) {
    _set(() {
      _tables = [
        for (final t in _tables)
          if (FloorCanvas.keyOf(t) == g.tableKey)
            () {
              final chairs = [...chairsOf(t)];
              if (g.index >= chairs.length) return t;
              final local = PlanBox.of(t).toLocal(cm);
              chairs[g.index] = attachChair(t, ChairPos(local.dx, local.dy));
              return t.copyWith(chairs: chairs);
            }()
          else
            t,
      ];
      _dirty = true;
    });
  }

  void _bandTo(_PlanFrame f, _BandGesture g, Offset cm) {
    final rect = Rect.fromPoints(g.startCm, cm);
    _set(() {
      _band = rect;
      _selection
        ..clear()
        ..addAll(g.base)
        ..addAll([
          for (final item in <Object>[..._zoneElements(f), ..._zoneTables(f)])
            if (PlanBox.of(item).bounds.overlaps(rect)) _keyOf(item),
        ]);
    });
  }

  /// Wymiary strefy przeciąganiem prawej albo dolnej krawędzi, co 10 cm.
  void _zoneTo(_ZoneGesture g, Offset cm) {
    final step = _alt ? 1.0 : 10.0;
    _set(() {
      _zones = [
        for (final z in _zones)
          if (z.name == g.zoneName)
            z.copyWith(
              widthCm: g.width ? snapTo(cm.dx, step).round().clamp(200, 10000) : null,
              heightCm: g.height ? snapTo(cm.dy, step).round().clamp(200, 10000) : null,
            )
          else
            z,
      ];
      final zone = _zones.firstWhere((z) => z.name == g.zoneName);
      _measure =
          '${metersLabel(zone.widthCm.toDouble()).replaceAll(' m', '')} × ${metersLabel(zone.heightCm.toDouble())}';
      _dirty = true;
    });
  }

  void _drawTo(_DrawGesture g, Offset cm) {
    final rect = Rect.fromPoints(g.startCm, _snap(cm));
    _set(() {
      _draft = rect;
      _measure = '${rect.width.round()} × ${rect.height.round()} cm';
    });
  }

  /// Koniec rysowania prostokąta: nowy element stały. Samo kliknięcie wstawia 2 × 0,6 m.
  void _finishDraw(_PlanFrame f, _DrawGesture g) {
    final rect = _draft;
    final zone = _zoneNow(f);
    if (rect == null || (rect.width < 10 && rect.height < 10)) {
      _addElement(zone, at: g.startCm);
    } else {
      _addElement(
        zone,
        at: rect.center,
        width: rect.width.round().clamp(5, 5000),
        height: rect.height.round().clamp(5, 5000),
      );
    }
    _set(() => _tool = _Tool.select);
  }

  /// Punkt ściany pod kursorem: koniec innej ściany (do 10 px), bez Shift kąt co 15° od poprzedniego
  /// narożnika, a pierwszy narożnik na kratce co 10 cm. Zawsze w granicach strefy.
  Offset _wallPoint(_PlanFrame f, Offset cm) {
    final zone = _zoneNow(f);
    Offset inside(Offset p) => Offset(
      p.dx.clamp(0, zone.widthCm.toDouble()),
      p.dy.clamp(0, zone.heightCm.toDouble()),
    );
    final tolerance = 10 / f.view.scale;
    for (final e in _zoneElements(f)) {
      if (!isWallLike(e)) continue;
      for (final end in wallEnds(e)) {
        if ((end - cm).distance <= tolerance) return end;
      }
    }
    final start = _wallStart;
    if (start != null && !_shift) return inside(snapAngle(start, cm));
    return inside(_snap(cm));
  }

  /// Koniec rysowania ściany (Enter, Esc, dwuklik, prawy przycisk): powrót do zaznaczania,
  /// żeby kolejne kliknięcie nie zaczynało przypadkiem nowej ściany. Następną zaczyna W.
  void _finishWall() => _set(() {
    _wallStart = null;
    if (_tool == _Tool.wall) _tool = _Tool.select;
  });

  /// Kolejny narożnik ściany. Dwuklik kończy ścianę.
  void _wallClick(_PlanFrame f, Offset px, Offset cm) {
    final now = DateTime.now();
    final doubleClick = (px - _lastWallClickPx).distance < 6 &&
        now.difference(_lastWallClick) < const Duration(milliseconds: 350);
    _lastWallClick = now;
    _lastWallClickPx = px;
    if (doubleClick) {
      _finishWall();
      return;
    }
    final point = _wallPoint(f, cm);
    final start = _wallStart;
    if (start == null) {
      _set(() => _wallStart = point);
      return;
    }
    if ((point - start).distance < 10) return;
    _remember();
    final wall = wallElement(
      draftKey: 'sciana-${now.microsecondsSinceEpoch}',
      zone: f.zone.name,
      a: start,
      b: point,
    );
    _set(() {
      _elements = [..._elements, wall];
      _wallStart = point;
      _selection.clear();
      _dirty = true;
    });
  }

  /// Menu pod prawym przyciskiem: na obiekcie (zaznacza go, jeśli nie był zaznaczony) duplikowanie, obrót
  /// o 90°, kopiowanie i usuwanie, a na pustym miejscu wklejanie, zaznaczanie wszystkiego i dopasowanie widoku.
  Future<void> _contextMenu(_PlanFrame f, Offset global, Offset cm) async {
    final hit = _hitItem(f, cm);
    if (hit != null && !_selection.contains(_keyOf(hit))) _set(() => _select(_keyOf(hit)));
    final onItems = hit != null && _selection.isNotEmpty;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = overlay.globalToLocal(global);
    final text = Theme.of(context).textTheme;

    PopupMenuItem<_MenuAction> item(_MenuAction value, AppIconData icon, String label, String? shortcut,
        {bool enabled = true, bool danger = false}) {
      final color = !enabled ? AppColors.textDisabled : (danger ? AppColors.error : AppColors.text);
      return PopupMenuItem(
        value: value,
        enabled: enabled,
        height: 40,
        child: Row(
          children: [
            Glyph(icon, size: 16, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: text.labelLarge?.copyWith(color: color))),
            if (shortcut != null)
              Text(shortcut, style: text.labelMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular)),
          ],
        ),
      );
    }

    final choice = await showMenu<_MenuAction>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      color: AppColors.surface,
      constraints: const BoxConstraints(minWidth: 240),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.ring),
      ),
      items: onItems
          ? [
              item(_MenuAction.duplicate, AppIcons.copy, 'Duplikuj', 'Ctrl+D'),
              item(_MenuAction.rotate, AppIcons.refresh, 'Obróć o 90°', null),
              item(_MenuAction.copy, AppIcons.clipboardText, 'Kopiuj', 'Ctrl+C'),
              const PopupMenuDivider(),
              item(
                _MenuAction.delete,
                AppIcons.trash,
                _selection.length > 1 ? 'Usuń zaznaczone (${_selection.length})' : 'Usuń',
                'Delete',
                danger: true,
              ),
            ]
          : [
              item(_MenuAction.paste, AppIcons.clipboardText, 'Wklej', 'Ctrl+V', enabled: _clipboard.isNotEmpty),
              item(_MenuAction.selectAll, AppIcons.cursor, 'Zaznacz wszystko', 'Ctrl+A'),
              item(_MenuAction.fit, AppIcons.cornersOut, 'Dopasuj widok', 'Ctrl+0'),
            ],
    );
    if (choice == null || !mounted) return;
    final zone = _zoneNow(f);
    switch (choice) {
      case _MenuAction.duplicate:
        _paste(_selectedItems(), zone);
      case _MenuAction.rotate:
        _rotateSelection(90);
      case _MenuAction.copy:
        _copy();
      case _MenuAction.delete:
        await _deleteSelection();
      case _MenuAction.paste:
        _paste(_clipboard, zone);
      case _MenuAction.selectAll:
        _selectAll();
      case _MenuAction.fit:
        _fit();
    }
    _canvasFocus.requestFocus();
  }

  void _setTool(_PlanFrame f, _Tool tool) {
    _set(() {
      _tool = tool;
      _wallStart = null;
    });
    if (_pointerPx case final px?) _hover(f, px);
  }

  /// Esc: przerywa rysowanie (ściana wraca też do zaznaczania), potem wraca do zaznaczania, a na końcu odznacza.
  void _escape() {
    _set(() {
      if (_gesture is _DrawGesture) {
        _gesture = null;
        _draft = null;
        _measure = null;
      } else if (_wallStart != null) {
        _wallStart = null;
        _tool = _Tool.select;
      } else if (_tool != _Tool.select) {
        _tool = _Tool.select;
      } else {
        _selection.clear();
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final f = _frame;
    if (f == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      // Przytrzymana spacja przesuwa widok jak rączka.
      final down = event is! KeyUpEvent;
      if (down != _spaceDown) {
        _set(() {
          _spaceDown = down;
          _cursor = down ? SystemMouseCursors.grab : MouseCursor.defer;
        });
        if (!down && _pointerPx != null) _hover(f, _pointerPx!);
      }
      return KeyEventResult.handled;
    }
    // Skróty z Ctrl obsługuje CallbackShortcuts nad planem.
    if (event is KeyUpEvent || _ctrl) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.escape) {
      _escape();
      return KeyEventResult.handled;
    }
    if (!f.editing) return KeyEventResult.ignored;
    final zone = _zoneNow(f);
    final step = _shift ? 50.0 : (_alt ? 1.0 : 10.0);
    final first = event is KeyDownEvent;
    switch (key) {
      case LogicalKeyboardKey.arrowLeft:
        _nudge(zone, Offset(-step, 0));
      case LogicalKeyboardKey.arrowRight:
        _nudge(zone, Offset(step, 0));
      case LogicalKeyboardKey.arrowUp:
        _nudge(zone, Offset(0, -step));
      case LogicalKeyboardKey.arrowDown:
        _nudge(zone, Offset(0, step));
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        if (first) _deleteSelection();
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        _finishWall();
      case LogicalKeyboardKey.keyV || LogicalKeyboardKey.keyS:
        _setTool(f, _Tool.select);
      case LogicalKeyboardKey.keyH:
        _setTool(f, _Tool.pan);
      case LogicalKeyboardKey.keyW:
        _setTool(f, _Tool.wall);
      case LogicalKeyboardKey.keyR:
        _setTool(f, _Tool.element);
      case LogicalKeyboardKey.keyT:
        _setTool(f, _Tool.table);
      case LogicalKeyboardKey.keyM:
        _setTool(f, _Tool.seat);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Obiekt z panelu „Dodaj na plan” upuszczony na plan, na kratce co 10 cm.
  void _dropPreset(_Preset preset, Offset global) {
    final f = _frame;
    final box = _planKey.currentContext?.findRenderObject() as RenderBox?;
    if (f == null || box == null) return;
    final zone = _zoneNow(f);
    final cm = _snap(f.view.toCm(box.globalToLocal(global)));
    _addPreset(
      preset,
      zone,
      at: Offset(cm.dx.clamp(0, zone.widthCm.toDouble()), cm.dy.clamp(0, zone.heightCm.toDouble())),
    );
  }

  _PlanOverlay _overlay(FloorZone zone, PlanView view, bool editing) {
    final f = _frame;
    final pointer = _pointerPx;
    final wallStart = editing && _tool == _Tool.wall ? _wallStart : null;
    final wallEnd = wallStart != null && pointer != null && f != null ? _wallPoint(f, view.toCm(pointer)) : null;
    Rect? group;
    if (editing && _selection.length > 1) {
      final items = _selectedItems();
      if (items.isNotEmpty) {
        group = items.map((i) => PlanBox.of(i).bounds).reduce((a, b) => a.expandToInclude(b));
      }
    }
    return _PlanOverlay(
      view: view,
      zone: Size(zone.widthCm.toDouble(), zone.heightCm.toDouble()),
      handles: f == null ? const [] : _handles(f),
      group: group,
      band: _band,
      guides: _guides,
      draft: _draft,
      wallStart: wallStart,
      wallEnd: wallEnd,
      measure: wallEnd != null ? metersLabel((wallEnd - wallStart!).distance) : _measure,
      pointer: pointer,
      zoneLabels: editing,
      accent: AppColors.accent,
      surface: AppColors.surface,
      muted: AppColors.textMuted,
      ring: AppColors.ring,
      label: Theme.of(context).textTheme.labelMedium!.copyWith(
        color: AppColors.text,
        fontFeatures: _tabular,
      ),
    );
  }
}

/// Wszystko, co edytor rysuje nad planem: uchwyty, ramka zaznaczania, linie prowadzące,
/// rysowana ściana albo prostokąt i wymiar przy kursorze.
class _PlanOverlay extends CustomPainter {
  _PlanOverlay({
    required this.view,
    required this.zone,
    required this.handles,
    required this.group,
    required this.band,
    required this.guides,
    required this.draft,
    required this.wallStart,
    required this.wallEnd,
    required this.measure,
    required this.pointer,
    required this.zoneLabels,
    required this.accent,
    required this.surface,
    required this.muted,
    required this.ring,
    required this.label,
  });

  final PlanView view;
  final Size zone;
  final List<_Handle> handles;
  final Rect? group;
  final Rect? band;
  final ({double? x, double? y}) guides;
  final Rect? draft;
  final Offset? wallStart;
  final Offset? wallEnd;
  final String? measure;
  final Offset? pointer;

  /// Wymiary strefy przy jej górnej i lewej krawędzi (w edycji).
  final bool zoneLabels;
  final Color accent;
  final Color surface;
  final Color muted;
  final Color ring;
  final TextStyle label;

  Rect _screen(Rect cm) => Rect.fromPoints(view.toScreen(cm.topLeft), view.toScreen(cm.bottomRight));

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = accent
      ..strokeWidth = 1;
    final stroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final fill = Paint()..color = surface;

    if (zoneLabels) {
      final style = label.copyWith(color: muted, fontWeight: FontWeight.w500);
      final top = TextPainter(text: TextSpan(text: metersLabel(zone.width), style: style), textDirection: TextDirection.ltr)
        ..layout();
      final topAt = view.toScreen(Offset(zone.width / 2, 0));
      top.paint(canvas, topAt - Offset(top.width / 2, top.height + 8));
      final side = TextPainter(text: TextSpan(text: metersLabel(zone.height), style: style), textDirection: TextDirection.ltr)
        ..layout();
      final sideAt = view.toScreen(Offset(0, zone.height / 2));
      canvas
        ..save()
        ..translate(sideAt.dx - side.height - 8, sideAt.dy)
        ..rotate(-math.pi / 2);
      side.paint(canvas, Offset(-side.width / 2, 0));
      canvas.restore();
    }

    if (guides.x case final x?) {
      canvas.drawLine(view.toScreen(Offset(x, 0)) - const Offset(0, 24), view.toScreen(Offset(x, zone.height)) + const Offset(0, 24), line);
    }
    if (guides.y case final y?) {
      canvas.drawLine(view.toScreen(Offset(0, y)) - const Offset(24, 0), view.toScreen(Offset(zone.width, y)) + const Offset(24, 0), line);
    }

    if (band case final b?) {
      final r = _screen(b);
      canvas
        ..drawRect(r, Paint()..color = accent.withValues(alpha: 0.08))
        ..drawRect(
          r,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
    }

    if (group case final g?) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(_screen(g).inflate(8), const Radius.circular(6)),
        Paint()
          ..color = accent.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    if (draft case final d?) {
      final r = _screen(d);
      canvas
        ..drawRect(r, Paint()..color = accent.withValues(alpha: 0.15))
        ..drawRect(r, stroke);
    }

    if (wallStart case final start?) {
      final a = view.toScreen(start);
      if (wallEnd case final end?) {
        canvas.drawLine(
          a,
          view.toScreen(end),
          Paint()
            ..color = accent.withValues(alpha: 0.55)
            ..strokeWidth = math.max(3, wallThicknessCm * view.scale)
            ..strokeCap = StrokeCap.square,
        );
      }
      canvas.drawCircle(a, 4, Paint()..color = accent);
    }

    for (final h in handles) {
      if (h.chair != null) continue; // Krzesła obrysowuje FloorCanvas.
      if (h.isZone) {
        final r = Rect.fromCenter(
          center: h.px,
          width: h.zoneWidth && !h.zoneHeight ? 6 : (h.zoneHeight && !h.zoneWidth ? 22 : 10),
          height: h.zoneHeight && !h.zoneWidth ? 6 : (h.zoneWidth && !h.zoneHeight ? 22 : 10),
        );
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
        canvas
          ..drawRRect(rr, fill)
          ..drawRRect(
            rr,
            Paint()
              ..color = muted
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        continue;
      }
      if (h.rotate) {
        if (h.from case final from?) canvas.drawLine(from, h.px, line);
        canvas
          ..drawCircle(h.px, 6, fill)
          ..drawCircle(h.px, 6, stroke);
        continue;
      }
      final r = Rect.fromCenter(center: h.px, width: 9, height: 9);
      canvas
        ..drawRect(r, fill)
        ..drawRect(r, stroke);
    }

    if ((measure, pointer) case (final text?, final at?)) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: label),
        textDirection: TextDirection.ltr,
      )..layout();
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(at.dx + 16, at.dy + 16, tp.width + 14, tp.height + 8),
        const Radius.circular(8),
      );
      canvas
        ..drawRRect(box, fill)
        ..drawRRect(
          box,
          Paint()
            ..color = ring
            ..style = PaintingStyle.stroke,
        );
      tp.paint(canvas, Offset(at.dx + 23, at.dy + 20));
    }
  }

  @override
  bool shouldRepaint(covariant _PlanOverlay old) => true;
}
