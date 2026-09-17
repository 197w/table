import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';

/// Zapas wokół blatu na krzesła, w centymetrach.
const chairMarginCm = 24.0;

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

  /// Druga linia pod numerem stolika, na przykład „18:30 Kowalski”.
  final String? caption;
  final Color? captionColor;
  final bool dimmed;
}

/// Strefa sali narysowana w skali: siatka co 50 cm i stoliki z krzesłami.
/// Pozycje w bazie są w centymetrach, skala dopasowuje strefę do dostępnego miejsca.
class FloorCanvas extends StatelessWidget {
  const FloorCanvas({
    super.key,
    required this.zone,
    required this.tables,
    required this.lookOf,
    required this.selectedId,
    required this.onTapTable,
    this.onTapEmpty,
    this.onDragTable,
    this.onDragEnd,
  });

  final FloorZone zone;
  final List<DiningTable> tables;
  final TableLook Function(DiningTable) lookOf;

  /// Klucz stolika: identyfikator albo numer dla niezapisanych.
  final String? selectedId;
  final ValueChanged<DiningTable> onTapTable;
  final VoidCallback? onTapEmpty;

  /// Przesunięcie w centymetrach. Null wyłącza przeciąganie.
  final void Function(DiningTable table, Offset deltaCm)? onDragTable;
  final ValueChanged<DiningTable>? onDragEnd;

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
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.ringStrong),
                      ),
                      child: CustomPaint(
                        painter: _GridPainter(
                          scale: scale,
                          color: AppColors.ring,
                        ),
                      ),
                    ),
                  ),
                  for (final t in tables) _positioned(context, t, scale),
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

  Widget _positioned(BuildContext context, DiningTable t, double scale) {
    final look = lookOf(t);
    final key = keyOf(t);
    final selected = key == selectedId;
    final boxW = (t.widthCm + chairMarginCm * 2) * scale;
    final boxH = (t.heightCm + chairMarginCm * 2) * scale;
    // Obszar mieszczący obrócony stolik.
    final extent = math.sqrt(boxW * boxW + boxH * boxH);
    final text = Theme.of(context).textTheme;

    return Positioned(
      left: t.xCm * scale - extent / 2,
      top: t.yCm * scale - extent / 2,
      width: extent,
      height: extent,
      child: Center(
        child: MouseRegion(
          cursor: onDragTable != null
              ? SystemMouseCursors.move
              : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onTapTable(t),
            onPanStart: onDragTable == null ? null : (_) => onTapTable(t),
            onPanUpdate: onDragTable == null
                ? null
                : (d) => onDragTable!(t, d.delta / scale),
            onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(t),
            child: Opacity(
              opacity: look.dimmed ? 0.45 : 1,
              child: SizedBox(
                width: boxW,
                height: boxH,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: t.rotation * math.pi / 180,
                      child: CustomPaint(
                        size: Size(boxW, boxH),
                        painter: _TablePainter(
                          table: t,
                          scale: scale,
                          fill: look.fill,
                          stroke: selected ? AppColors.accent : look.stroke,
                          strokeWidth: selected ? 2.5 : look.strokeWidth,
                          chairColor: AppColors.ringStrong,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.label,
                          style: text.labelLarge?.copyWith(
                            fontSize: math.max(11, math.min(15, 16 * scale * 2)),
                          ),
                        ),
                        if (look.caption != null)
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: math.max(60, boxW)),
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _meters(int cm) {
  final m = cm / 100;
  return m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1).replaceAll('.', ',');
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
    required this.scale,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.chairColor,
  });

  final DiningTable table;
  final double scale;
  final Color fill;
  final Color stroke;
  final double strokeWidth;
  final Color chairColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final w = table.widthCm * scale;
    final h = table.heightCm * scale;
    final chairPaint = Paint()..color = chairColor;
    final chairLong = 40 * scale;
    final chairShort = 16 * scale;
    final gap = 6 * scale;

    void chair(Offset c, bool horizontal) {
      final rect = Rect.fromCenter(
        center: c,
        width: horizontal ? chairLong : chairShort,
        height: horizontal ? chairShort : chairLong,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(4 * scale + 1)),
        chairPaint,
      );
    }

    final seats = table.seats;
    if (table.shape == TableShape.round) {
      final r = math.max(w, h) / 2 + gap + chairShort / 2;
      for (var i = 0; i < seats; i++) {
        final a = -math.pi / 2 + 2 * math.pi * i / seats;
        final c = center + Offset(math.cos(a) * r, math.sin(a) * r);
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(a + math.pi / 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: chairLong * 0.9, height: chairShort),
            Radius.circular(4 * scale + 1),
          ),
          chairPaint,
        );
        canvas.restore();
      }
    } else {
      // Krzesła na dłuższych bokach, przy nieparzystej liczbie jedno na krótszym.
      final horizontal = w >= h;
      final longSide = horizontal ? w : h;
      final perSide = seats ~/ 2;
      final extra = seats.isOdd ? 1 : 0;
      for (final sign in [-1.0, 1.0]) {
        final count = sign < 0 ? perSide + (seats == 1 ? 1 : 0) : perSide;
        for (var i = 0; i < count; i++) {
          final t = (i + 1) / (count + 1);
          final along = -longSide / 2 + longSide * t;
          final off = (horizontal ? h : w) / 2 + gap + chairShort / 2;
          final c = horizontal
              ? center + Offset(along, sign * off)
              : center + Offset(sign * off, along);
          chair(c, horizontal);
        }
      }
      if (extra == 1 && seats > 1) {
        final off = longSide / 2 + gap + chairShort / 2;
        final c = horizontal ? center + Offset(off, 0) : center + Offset(0, off);
        chair(c, !horizontal);
      }
    }

    final tableRect = Rect.fromCenter(center: center, width: w, height: h);
    final fillPaint = Paint()..color = fill;
    final strokePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    if (table.shape == TableShape.round) {
      canvas.drawOval(tableRect, fillPaint);
      canvas.drawOval(tableRect, strokePaint);
    } else {
      final rr = RRect.fromRectAndRadius(tableRect, Radius.circular(6 * scale + 2));
      canvas.drawRRect(rr, fillPaint);
      canvas.drawRRect(rr, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TablePainter old) =>
      old.table != table ||
      old.scale != scale ||
      old.fill != fill ||
      old.stroke != stroke ||
      old.strokeWidth != strokeWidth;
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
      stroke: AppColors.ring,
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
  return TableLook(
    fill: AppColors.surface,
    stroke: soon ? AppColors.warning : AppColors.ringStrong,
    caption: next == null ? '${table.seats} os. · wolny' : 'wolny do ${Fmt.time(next.startsAt)}',
  );
}
