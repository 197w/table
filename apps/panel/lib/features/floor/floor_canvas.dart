import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';

/// Średnica krzesła na planie, w centymetrach.
const chairDiameterCm = 38.0;

/// Odstęp krzesła od krawędzi blatu, w centymetrach.
const chairGapCm = 6.0;

/// Najmniejsza i największa odległość środka krzesła od krawędzi blatu, w centymetrach.
/// Krzesło można przesuwać tylko w tym pasie, więc zawsze stoi przy swoim stoliku.
const chairMinReachCm = chairDiameterCm / 2 - 6;
const chairMaxReachCm = chairGapCm + chairDiameterCm / 2 + 20;

/// Wygląd stolika na planie.
class TableLook {
  const TableLook({
    required this.fill,
    required this.stroke,
    this.caption,
    this.captionColor,
    this.strokeWidth = 1.5,
    this.dimmed = false,
  });

  final Color fill;
  final Color stroke;
  final double strokeWidth;

  /// Druga linia pod numerem stolika, na przykład „od 18:30 · Kowalski”.
  final String? caption;
  final Color? captionColor;
  final bool dimmed;
}

/// Automatyczne rozstawienie krzeseł: w cm względem środka blatu, przed obrotem.
List<ChairPos> autoChairs(DiningTable t) {
  if (t.isSeat) return const [];
  final w = t.widthCm.toDouble();
  final h = t.heightCm.toDouble();
  const r = chairDiameterCm / 2;
  final seats = t.seats;
  final result = <ChairPos>[];

  if (t.shape == TableShape.round) {
    final radius = math.max(w, h) / 2 + chairGapCm + r;
    for (var i = 0; i < seats; i++) {
      final a = -math.pi / 2 + 2 * math.pi * i / seats;
      result.add(ChairPos(math.cos(a) * radius, math.sin(a) * radius));
    }
    return result;
  }

  // Krzesła zawsze wzdłuż szerokości, przy nieparzystej liczbie jedno na prawym końcu.
  // Zmiana wymiarów nie przerzuca więc krzeseł na inne boki, stolik obraca tylko kąt obrotu.
  final off = h / 2 + chairGapCm + r;
  final perSide = seats ~/ 2;
  for (final sign in [-1.0, 1.0]) {
    final count = sign < 0 ? perSide + (seats == 1 ? 1 : 0) : perSide;
    for (var i = 0; i < count; i++) {
      result.add(ChairPos(-w / 2 + w * (i + 1) / (count + 1), sign * off));
    }
  }
  if (seats.isOdd && seats > 1) {
    result.add(ChairPos(w / 2 + chairGapCm + r, 0));
  }
  return result;
}

/// Przyciąga krzesło do stolika: środek krzesła zostaje w pasie wokół blatu.
/// Pozycja w cm względem środka blatu, przed obrotem.
ChairPos attachChair(DiningTable t, ChairPos c) {
  final p = Offset(c.x, c.y);
  if (t.shape == TableShape.round) {
    final radius = math.max(t.widthCm, t.heightCm) / 2;
    final d = p.distance;
    final dir = d < 0.01 ? const Offset(0, -1) : p / d;
    final q = dir * (radius + (d - radius).clamp(chairMinReachCm, chairMaxReachCm));
    return ChairPos(q.dx, q.dy);
  }

  final hw = t.widthCm / 2;
  final hh = t.heightCm / 2;
  Offset edge;
  Offset normal;
  double dist;
  if (p.dx.abs() <= hw && p.dy.abs() <= hh) {
    // Krzesło na blacie: wypychamy je przez najbliższą krawędź.
    final sx = p.dx < 0 ? -1.0 : 1.0;
    final sy = p.dy < 0 ? -1.0 : 1.0;
    final toX = hw - p.dx.abs();
    final toY = hh - p.dy.abs();
    if (toX < toY) {
      edge = Offset(sx * hw, p.dy);
      normal = Offset(sx, 0);
      dist = -toX;
    } else {
      edge = Offset(p.dx, sy * hh);
      normal = Offset(0, sy);
      dist = -toY;
    }
  } else {
    edge = Offset(p.dx.clamp(-hw, hw), p.dy.clamp(-hh, hh));
    final v = p - edge;
    dist = v.distance;
    normal = v / dist;
  }
  final q = edge + normal * dist.clamp(chairMinReachCm, chairMaxReachCm);
  return ChairPos(q.dx, q.dy);
}

/// Krzesła stolika: własne ustawienie (zawsze przy blacie) albo automatyczne.
List<ChairPos> chairsOf(DiningTable t) =>
    t.chairs == null ? autoChairs(t) : [for (final c in t.chairs!) attachChair(t, c)];

Offset _rotate(Offset p, double degrees) {
  final a = degrees * math.pi / 180;
  return Offset(
    p.dx * math.cos(a) - p.dy * math.sin(a),
    p.dx * math.sin(a) + p.dy * math.cos(a),
  );
}

bool get _lightTheme => AppColors.palette.brightness == Brightness.light;

/// Obrys stolików i ścian strefy. W jasnym motywie pierścienie są zbyt blade, więc linia jest ciemniejsza.
Color get planLine => _lightTheme ? const Color(0x8A000000) : const Color(0x4DFFFFFF);

/// Kratka co 50 cm.
Color get planGrid => _lightTheme ? const Color(0x21000000) : const Color(0x0DFFFFFF);

/// Krzesła.
Color get planChair => _lightTheme ? const Color(0xFFB3B9B6) : const Color(0xFF3A3A41);

/// Obrys wyłączonego stolika.
Color get planLineMuted => _lightTheme ? const Color(0x4D000000) : const Color(0x24FFFFFF);

/// Kolor stałych elementów sali: jasnoszary w obu motywach.
/// W ciemnym motywie przygaszony, żeby na czarnej podłodze nie świecił jak plama.
Color elementFill(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF45454C)
    : const Color(0xFFD6D9D7);

/// Strefa sali narysowana w skali: stałe elementy, stoliki z krzesłami i miejsca do rezerwacji.
/// Pozycje w bazie są w centymetrach, skala dopasowuje strefę do dostępnego miejsca.
class FloorCanvas extends StatelessWidget {
  const FloorCanvas({
    super.key,
    required this.zone,
    required this.tables,
    required this.lookOf,
    required this.selectedId,
    required this.onTapTable,
    this.elements = const [],
    this.showGrid = true,
    this.onTapEmpty,
    this.onDragTable,
    this.onDragEnd,
    this.onTapElement,
    this.onDragElement,
    this.onDragElementEnd,
    this.chairEditKey,
    this.onDragChair,
    this.onDragChairEnd,
    this.onTapTableAt,
  });

  final FloorZone zone;
  final List<DiningTable> tables;
  final List<FloorElement> elements;
  final TableLook Function(DiningTable) lookOf;

  /// Klucz zaznaczonego stolika albo elementu.
  final String? selectedId;
  final bool showGrid;
  final ValueChanged<DiningTable> onTapTable;
  final VoidCallback? onTapEmpty;

  /// Przesunięcie w centymetrach. Null wyłącza przeciąganie.
  final void Function(DiningTable table, Offset deltaCm)? onDragTable;
  final ValueChanged<DiningTable>? onDragEnd;

  final ValueChanged<FloorElement>? onTapElement;
  final void Function(FloorElement element, Offset deltaCm)? onDragElement;
  final ValueChanged<FloorElement>? onDragElementEnd;

  /// Klucz stolika, którego krzesła można przeciągać.
  final String? chairEditKey;

  /// Przesunięcie krzesła w cm, w układzie blatu (przed obrotem).
  final void Function(DiningTable table, int index, Offset deltaCm)? onDragChair;
  final ValueChanged<DiningTable>? onDragChairEnd;

  /// Kliknięcie stolika razem z jego położeniem na ekranie (blat z krzesłami),
  /// na przykład do menu obok stolika. Gdy jest ustawione, zastępuje [onTapTable].
  final void Function(DiningTable table, Rect globalRect)? onTapTableAt;

  static String keyOf(DiningTable t) => t.id ?? t.draftKey ?? t.label;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final scale = math.min(
          c.maxWidth / zone.widthCm,
          c.maxHeight / zone.heightCm,
        );
        final width = zone.widthCm * scale;
        final height = zone.heightCm * scale;

        DiningTable? chairTable;
        for (final t in tables) {
          if (keyOf(t) == chairEditKey && !t.isSeat) chairTable = t;
        }

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapEmpty,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      // W ciemnym motywie podłoga sali jest ciemniejsza od karty,
                      // więc plan wygląda jak wgłębienie, a nie kolejne pudełko.
                      decoration: BoxDecoration(
                        color: _lightTheme ? AppColors.surface : AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _lightTheme ? planLine : AppColors.ring),
                      ),
                      child: showGrid
                          ? CustomPaint(
                              painter: _GridPainter(scale: scale, color: planGrid),
                            )
                          : null,
                    ),
                  ),
                  for (final e in elements) _element(context, e, scale),
                  for (final t in tables) _table(context, t, scale),
                  if (chairTable != null) ..._chairHandles(chairTable, scale),
                  if (showGrid)
                    Positioned(
                      right: 8,
                      bottom: 6,
                      child: Text(
                        '${_meters(zone.widthCm)} × ${_meters(zone.heightCm)} m · kratka 50 cm',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textDisabled,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _element(BuildContext context, FloorElement e, double scale) {
    final w = e.widthCm * scale;
    final h = e.heightCm * scale;
    final extent = math.sqrt(w * w + h * h);
    final selected = e.key == selectedId;
    final fill = elementFill(context);

    return Positioned(
      left: e.xCm * scale - extent / 2,
      top: e.yCm * scale - extent / 2,
      width: extent,
      height: extent,
      child: Center(
        child: MouseRegion(
          cursor: onDragElement != null ? SystemMouseCursors.move : MouseCursor.defer,
          child: GestureDetector(
            onTap: onTapElement == null ? null : () => onTapElement!(e),
            onPanStart: onDragElement == null ? null : (_) => onTapElement?.call(e),
            onPanUpdate: onDragElement == null ? null : (d) => onDragElement!(e, d.delta / scale),
            onPanEnd: onDragElementEnd == null ? null : (_) => onDragElementEnd!(e),
            child: Transform.rotate(
              angle: e.rotation * math.pi / 180,
              child: Container(
                width: math.max(w, 2),
                height: math.max(h, 2),
                decoration: BoxDecoration(
                  color: fill,
                  shape: e.shape == TableShape.round ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: e.shape == TableShape.round
                      ? null
                      : BorderRadius.circular(math.min(4, math.min(w, h) / 2)),
                  border: selected ? Border.all(color: AppColors.accent, width: 2) : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _table(BuildContext context, DiningTable t, double scale) {
    final look = lookOf(t);
    final selected = keyOf(t) == selectedId;
    final chairs = chairsOf(t);
    const r = chairDiameterCm / 2;

    // Promień obejmujący blat i wszystkie krzesła, niezależnie od obrotu.
    var reach = math.sqrt(t.widthCm * t.widthCm + t.heightCm * t.heightCm) / 2;
    for (final c in chairs) {
      reach = math.max(reach, math.sqrt(c.x * c.x + c.y * c.y) + r);
    }
    final extent = (reach * 2 + 4) * scale;
    final text = Theme.of(context).textTheme;
    final tableW = t.widthCm * scale;

    return Positioned(
      left: t.xCm * scale - extent / 2,
      top: t.yCm * scale - extent / 2,
      width: extent,
      height: extent,
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(extent, extent),
              painter: _TablePainter(
                table: t,
                chairs: chairs,
                scale: scale,
                fill: look.fill,
                stroke: selected ? AppColors.accent : look.stroke,
                strokeWidth: selected ? 2.5 : look.strokeWidth,
                chairColor: planChair,
                dimmed: look.dimmed,
              ),
            ),
            // Obszar klikania to sam blat, żeby dało się złapać krzesło obok.
            SizedBox(
              width: math.max(t.widthCm, t.heightCm) * scale,
              height: math.max(t.widthCm, t.heightCm) * scale,
              child: MouseRegion(
                cursor: onDragTable != null ? SystemMouseCursors.move : SystemMouseCursors.click,
                child: Builder(
                  builder: (hitContext) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final at = onTapTableAt;
                    final box = hitContext.findRenderObject() as RenderBox?;
                    if (at != null && box != null && box.hasSize) {
                      // Obszar razem z krzesłami, żeby menu obok stolika ich nie zasłaniało.
                      final top = box.localToGlobal(Offset.zero) & box.size;
                      at(
                        t,
                        Rect.fromCenter(
                          center: top.center,
                          width: math.max(top.width, extent),
                          height: math.max(top.height, extent),
                        ),
                      );
                    } else {
                      onTapTable(t);
                    }
                  },
                  onPanStart: onDragTable == null ? null : (_) => onTapTable(t),
                  onPanUpdate: onDragTable == null ? null : (d) => onDragTable!(t, d.delta / scale),
                  onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(t),
                  child: Opacity(
                    opacity: look.dimmed ? 0.5 : 1,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t.label,
                            style: text.labelLarge?.copyWith(
                              fontSize: t.isSeat ? 11 : math.max(11, math.min(15, 32 * scale)),
                            ),
                          ),
                          if (look.caption != null && !t.isSeat)
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: math.max(70, tableW + 30)),
                              child: Text(
                                look.caption!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: text.bodySmall?.copyWith(
                                  fontSize: 10,
                                  height: 1.2,
                                  color: look.captionColor ?? AppColors.textMuted,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Uchwyty krzeseł zaznaczonego stolika w trybie edycji.
  List<Widget> _chairHandles(DiningTable t, double scale) {
    final chairs = chairsOf(t);
    final size = chairDiameterCm * scale + 8;
    return [
      for (var i = 0; i < chairs.length; i++)
        () {
          final p = _rotate(Offset(chairs[i].x, chairs[i].y), t.rotation.toDouble());
          return Positioned(
            left: (t.xCm + p.dx) * scale - size / 2,
            top: (t.yCm + p.dy) * scale - size / 2,
            width: size,
            height: size,
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: onDragChair == null
                    ? null
                    : (d) => onDragChair!(t, i, _rotate(d.delta / scale, -t.rotation.toDouble())),
                onPanEnd: onDragChairEnd == null ? null : (_) => onDragChairEnd!(t),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent, width: 1.5),
                  ),
                ),
              ),
            ),
          );
        }(),
    ];
  }
}

String _meters(int cm) {
  final m = cm / 100;
  return m == m.roundToDouble()
      ? m.toStringAsFixed(0)
      : m.toStringAsFixed(1).replaceAll('.', ',');
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.scale, required this.color});

  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..color = color
      ..strokeWidth = 1;
    final step = 50 * scale;
    if (step < 6) return;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), thin);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), thin);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.scale != scale || old.color != color;
}

class _TablePainter extends CustomPainter {
  _TablePainter({
    required this.table,
    required this.chairs,
    required this.scale,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.chairColor,
    required this.dimmed,
  });

  final DiningTable table;
  final List<ChairPos> chairs;
  final double scale;
  final Color fill;
  final Color stroke;
  final double strokeWidth;
  final Color chairColor;
  final bool dimmed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(table.rotation * math.pi / 180);

    final alpha = dimmed ? 0.5 : 1.0;
    final chairPaint = Paint()..color = chairColor.withValues(alpha: chairColor.a * alpha);
    const r = chairDiameterCm / 2;
    for (final c in chairs) {
      canvas.drawCircle(Offset(c.x * scale, c.y * scale), r * scale, chairPaint);
    }

    final w = table.widthCm * scale;
    final h = table.heightCm * scale;
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final fillPaint = Paint()..color = fill.withValues(alpha: fill.a * alpha);
    final strokePaint = Paint()
      ..color = stroke.withValues(alpha: stroke.a * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    if (table.shape == TableShape.round || table.isSeat) {
      canvas.drawOval(rect, fillPaint);
      canvas.drawOval(rect, strokePaint);
    } else {
      // Blaty rysujemy ostrymi narożnikami, bez zaokrągleń.
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, strokePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TablePainter old) =>
      old.table != table ||
      old.chairs != chairs ||
      old.scale != scale ||
      old.fill != fill ||
      old.stroke != stroke ||
      old.strokeWidth != strokeWidth ||
      old.dimmed != dimmed;
}

/// Strefy w stałej kolejności: najpierw te dodane wcześniej, potem alfabetycznie.
/// Strefy, których nie ma w tabeli stref, a mają stoliki, dopisujemy na końcu.
List<FloorZone> orderedZones(List<FloorZone> zones, List<DiningTable> tables) {
  final list = [...zones]
    ..sort((a, b) {
      if (a.position != b.position) return a.position.compareTo(b.position);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  for (final t in tables) {
    if (!list.any((z) => z.name == t.zone)) {
      list.add(
        FloorZone(
          id: null,
          name: t.zone,
          widthCm: 1000,
          heightCm: 700,
          position: list.length,
        ),
      );
    }
  }
  return list;
}

/// Czy dwa stoliki nachodzą na siebie. Obrót przybliżamy prostokątem opisanym.
bool tablesOverlap(DiningTable a, DiningTable b) {
  if (a.zone != b.zone) return false;
  Rect bounds(DiningTable t) {
    final rad = t.rotation * math.pi / 180;
    final w = (t.widthCm * math.cos(rad)).abs() + (t.heightCm * math.sin(rad)).abs();
    final h = (t.widthCm * math.sin(rad)).abs() + (t.heightCm * math.cos(rad)).abs();
    return Rect.fromCenter(
      center: Offset(t.xCm.toDouble(), t.yCm.toDouble()),
      width: w,
      height: h,
    );
  }

  return bounds(a).deflate(1).overlaps(bounds(b).deflate(1));
}

/// Rezerwacja zajmująca stolik o danej godzinie i najbliższa kolejna.
({PanelReservation? current, PanelReservation? next}) tableState(
  DiningTable table,
  List<PanelReservation> reservations,
  DateTime at, {
  bool seatedCountsNow = true,
}) {
  PanelReservation? current;
  PanelReservation? next;
  for (final r in reservations) {
    if (!r.status.isActive || !r.tableIds.contains(table.id)) continue;
    final seatedNow = seatedCountsNow && r.status == ReservationStatus.seated;
    if ((!r.startsAt.isAfter(at) || seatedNow) && r.endsAt.isAfter(at)) {
      current = r;
    } else if (r.startsAt.isAfter(at) &&
        (next == null || r.startsAt.isBefore(next.startsAt))) {
      next = r;
    }
  }
  return (current: current, next: next);
}

String _shortName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.length > 1 ? parts.last : parts.first;
}

/// Kolory stolika w podglądzie zajętości.
TableLook liveTableLook(
  DiningTable table,
  List<PanelReservation> reservations,
  DateTime at, {
  bool seatedCountsNow = true,
  bool highlighted = false,
}) {
  if (!table.active) {
    return TableLook(
      fill: AppColors.surface,
      stroke: planLineMuted,
      caption: 'wyłączony',
      dimmed: true,
    );
  }
  final state = tableState(table, reservations, at, seatedCountsNow: seatedCountsNow);
  final current = state.current;
  if (current != null) {
    final seated = current.status == ReservationStatus.seated;
    return TableLook(
      fill: seated ? AppColors.accentTint : AppColors.warning.withValues(alpha: 0.14),
      stroke: highlighted
          ? AppColors.accent
          : (seated ? AppColors.accent : AppColors.warning),
      strokeWidth: highlighted ? 3 : 2,
      caption:
          '${seated ? 'do' : 'od'} ${Fmt.time(seated ? current.endsAt : current.startsAt)} · ${_shortName(current.guestName)}',
      captionColor: seated ? AppColors.accent : AppColors.warning,
    );
  }
  final next = state.next;
  final soon = next != null && next.startsAt.difference(at).inMinutes <= 90;
  // Wolny stolik nie potrzebuje podpisu: sam numer wystarczy.
  return TableLook(
    fill: AppColors.surface,
    stroke: highlighted ? AppColors.accent : (soon ? AppColors.warning : planLine),
    strokeWidth: highlighted ? 3 : 1.5,
  );
}
