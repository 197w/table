import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';

/// Grubość nowej ściany narysowanej narzędziem „Ściana”, w centymetrach.
const wallThicknessCm = 12;

/// Element stały, który traktujemy jak ścianę: prostokąt nie grubszy niż 30 cm.
/// Do jego końców przyciąga się rysowana ściana.
bool isWallLike(FloorElement e) => e.shape == TableShape.rect && math.min(e.widthCm, e.heightCm) <= 30;

/// Obrót punktu wokół zera o kąt w stopniach (zgodnie z ruchem wskazówek zegara na ekranie).
Offset rotateOffset(Offset p, double degrees) {
  final a = degrees * math.pi / 180;
  return Offset(
    p.dx * math.cos(a) - p.dy * math.sin(a),
    p.dx * math.sin(a) + p.dy * math.cos(a),
  );
}

/// Widok planu jak w UniFi Design Center: skala (piksele na centymetr) i miejsce
/// lewego górnego rogu strefy na ekranie. Przybliżanie i przesuwanie zmienia tylko widok, nie układ.
@immutable
class PlanView {
  const PlanView(this.scale, this.origin);

  /// Cała strefa w [area] (współrzędne widoku), na środku.
  factory PlanView.fit(FloorZone zone, Rect area) {
    final scale = math.max(
      0.01,
      math.min(area.width / zone.widthCm, area.height / zone.heightCm),
    );
    return PlanView(
      scale,
      area.center - Offset(zone.widthCm * scale, zone.heightCm * scale) / 2,
    );
  }

  final double scale;
  final Offset origin;

  Offset toScreen(Offset cm) => origin + cm * scale;
  Offset toCm(Offset px) => (px - origin) / scale;

  /// Przybliżenie o [factor] wokół punktu [focal] na ekranie: punkt pod kursorem zostaje w miejscu.
  PlanView zoomAt(Offset focal, double factor, {required double min, required double max}) {
    final s = (scale * factor).clamp(min, max);
    return PlanView(s, focal - toCm(focal) * s);
  }

  PlanView pannedBy(Offset delta) => PlanView(scale, origin + delta);

  @override
  bool operator ==(Object other) => other is PlanView && other.scale == scale && other.origin == origin;

  @override
  int get hashCode => Object.hash(scale, origin);
}

/// Blat stolika albo element stały jako prostokąt lub koło w centymetrach, z obrotem w stopniach.
@immutable
class PlanBox {
  const PlanBox(this.center, this.size, this.rotation, {this.round = false});

  factory PlanBox.of(Object item) => switch (item) {
    final DiningTable t => PlanBox(
      Offset(t.xCm.toDouble(), t.yCm.toDouble()),
      Size(t.widthCm.toDouble(), t.heightCm.toDouble()),
      t.rotation.toDouble(),
      round: t.shape == TableShape.round || t.isSeat,
    ),
    final FloorElement e => PlanBox(
      Offset(e.xCm.toDouble(), e.yCm.toDouble()),
      Size(e.widthCm.toDouble(), e.heightCm.toDouble()),
      e.rotation.toDouble(),
      round: e.shape == TableShape.round,
    ),
    _ => throw ArgumentError.value(item, 'item', 'Stolik albo element stały'),
  };

  final Offset center;
  final Size size;
  final double rotation;
  final bool round;

  /// Punkt planu w układzie kształtu: środek w zerze, przed obrotem.
  Offset toLocal(Offset p) => rotateOffset(p - center, -rotation);

  /// Punkt w układzie kształtu z powrotem na planie.
  Offset toPlan(Offset local) => center + rotateOffset(local, rotation);

  /// Prostokąt opisany na obróconym kształcie, w osiach planu.
  Rect get bounds {
    if (round) return Rect.fromCenter(center: center, width: size.width, height: size.height);
    final a = rotation * math.pi / 180;
    final w = (size.width * math.cos(a)).abs() + (size.height * math.sin(a)).abs();
    final h = (size.width * math.sin(a)).abs() + (size.height * math.cos(a)).abs();
    return Rect.fromCenter(center: center, width: w, height: h);
  }

  /// Czy punkt planu leży na kształcie, z zapasem [tolerance] cm wokół krawędzi.
  bool contains(Offset p, {double tolerance = 0}) {
    final l = toLocal(p);
    final hw = size.width / 2 + tolerance;
    final hh = size.height / 2 + tolerance;
    if (round) return (l.dx * l.dx) / (hw * hw) + (l.dy * l.dy) / (hh * hh) <= 1;
    return l.dx.abs() <= hw && l.dy.abs() <= hh;
  }
}

/// Zaokrąglenie do wielokrotności [step].
double snapTo(double v, double step) => (v / step).roundToDouble() * step;

/// Punkt na kratce co [step] cm.
Offset snapPoint(Offset p, double step) => Offset(snapTo(p.dx, step), snapTo(p.dy, step));

/// Kierunek od [from] do [to] przyciągnięty do wielokrotności [stepDegrees], długość co 5 cm.
Offset snapAngle(Offset from, Offset to, {double stepDegrees = 15}) {
  final v = to - from;
  final length = v.distance;
  if (length < 0.01) return to;
  final step = stepDegrees * math.pi / 180;
  final angle = snapTo(math.atan2(v.dy, v.dx), step);
  return from + Offset(math.cos(angle), math.sin(angle)) * snapTo(length, 5);
}

/// Linie prowadzące przy przesuwaniu: lewa krawędź, środek albo prawa krawędź przesuwanego obszaru
/// przyciąga się do krawędzi i środków innych obiektów i strefy, jeśli jest bliżej niż [tolerance].
/// Zwraca poprawkę przesunięcia na każdej osi i miejsce linii (null, gdy nic nie przyciąga).
({double? dx, double? dy, double? guideX, double? guideY}) snapToGuides(
  Rect moving,
  Iterable<Rect> others,
  Size zone,
  double tolerance,
) {
  final targetsX = <double>[0, zone.width / 2, zone.width];
  final targetsY = <double>[0, zone.height / 2, zone.height];
  for (final r in others) {
    targetsX.addAll([r.left, r.center.dx, r.right]);
    targetsY.addAll([r.top, r.center.dy, r.bottom]);
  }

  (double, double)? best(List<double> mine, List<double> targets) {
    (double, double)? found;
    for (final m in mine) {
      for (final t in targets) {
        final d = t - m;
        if (d.abs() <= tolerance && (found == null || d.abs() < found.$1.abs())) found = (d, t);
      }
    }
    return found;
  }

  final x = best([moving.left, moving.center.dx, moving.right], targetsX);
  final y = best([moving.top, moving.center.dy, moving.bottom], targetsY);
  return (dx: x?.$1, dy: y?.$1, guideX: x?.$2, guideY: y?.$2);
}

/// Nowy środek i wymiary po przeciągnięciu uchwytu do punktu [p] planu. [handle] to strona uchwytu
/// na każdej osi (−1, 0 albo 1, w układzie kształtu); przeciwna krawędź zostaje w miejscu.
/// Koło zmienia oba wymiary naraz.
({Offset center, Size size}) resizeBox(
  PlanBox start,
  Offset handle,
  Offset p, {
  required double min,
  required double max,
  required double step,
}) {
  final local = start.toLocal(p);
  final w = start.size.width;
  final h = start.size.height;
  var nw = handle.dx == 0 ? w : snapTo(handle.dx * local.dx + w / 2, step).clamp(min, max);
  var nh = handle.dy == 0 ? h : snapTo(handle.dy * local.dy + h / 2, step).clamp(min, max);
  if (start.round) {
    final s = math.max(handle.dx == 0 ? 0.0 : nw, handle.dy == 0 ? 0.0 : nh);
    nw = s;
    nh = s;
  }
  final shift = Offset(
    handle.dx == 0 ? 0 : handle.dx * (nw - w) / 2,
    handle.dy == 0 ? 0 : handle.dy * (nh - h) / 2,
  );
  return (center: start.toPlan(shift), size: Size(nw, nh));
}

/// Obrót wskazywany kursorem: kąt od środka do punktu [p], gdzie 0° to kierunek „w górę”,
/// co [step] stopni, w zakresie 0–359.
int rotationTowards(Offset center, Offset p, {int step = 15}) {
  final degrees = math.atan2(p.dy - center.dy, p.dx - center.dx) * 180 / math.pi + 90;
  final snapped = (degrees / step).round() * step;
  return ((snapped % 360) + 360) % 360;
}

/// Ściana od punktu [a] do [b] (cm) jako element stały: prostokąt o grubości [thickness],
/// wydłużony o pół grubości z obu stron, żeby narożniki się domykały. Kąt 0–179°.
FloorElement wallElement({
  required String draftKey,
  required String zone,
  required Offset a,
  required Offset b,
  int thickness = wallThicknessCm,
}) {
  final v = b - a;
  final degrees = (math.atan2(v.dy, v.dx) * 180 / math.pi).round();
  final center = (a + b) / 2;
  return FloorElement(
    id: null,
    draftKey: draftKey,
    zone: zone,
    xCm: center.dx.round().clamp(0, 10000),
    yCm: center.dy.round().clamp(0, 10000),
    widthCm: (v.distance + thickness).round().clamp(5, 5000),
    heightCm: thickness,
    rotation: ((degrees % 180) + 180) % 180,
    shape: TableShape.rect,
  );
}

/// Końce ściany (środki jej krótszych boków, bez zakładki na grubość).
List<Offset> wallEnds(FloorElement e) {
  final box = PlanBox.of(e);
  final along = e.widthCm >= e.heightCm;
  final half = (e.widthCm - e.heightCm).abs() / 2;
  final dir = along ? const Offset(1, 0) : const Offset(0, 1);
  return [box.toPlan(-dir * half), box.toPlan(dir * half)];
}

/// Długość w metrach do podpisu: „3,4 m”, „12 m”.
String metersLabel(double cm) {
  final text = (cm / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '${text.replaceAll('.', ',')} m';
}
