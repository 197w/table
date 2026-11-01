import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/features/floor/plan_geometry.dart';

FloorElement _element({int x = 500, int y = 300, int w = 200, int h = 60, int rotation = 0}) => FloorElement(
  id: null,
  draftKey: 'e',
  zone: 'sala',
  xCm: x,
  yCm: y,
  widthCm: w,
  heightCm: h,
  rotation: rotation,
  shape: TableShape.rect,
);

void main() {
  const zone = FloorZone(id: null, name: 'sala', widthCm: 1000, heightCm: 600, position: 0);

  test('dopasowanie mieści całą strefę na środku obszaru', () {
    final view = PlanView.fit(zone, const Rect.fromLTWH(0, 0, 500, 500));
    expect(view.scale, 0.5);
    expect(view.toScreen(const Offset(500, 300)), const Offset(250, 250));
  });

  test('przybliżenie zostawia punkt pod kursorem w miejscu', () {
    const view = PlanView(0.5, Offset(10, 20));
    const focal = Offset(200, 150);
    final before = view.toCm(focal);
    final zoomed = view.zoomAt(focal, 2, min: 0.1, max: 4);
    expect(zoomed.scale, 1);
    expect(zoomed.toCm(focal).dx, closeTo(before.dx, 1e-9));
    expect(zoomed.toCm(focal).dy, closeTo(before.dy, 1e-9));
  });

  test('przybliżenie ma granice', () {
    const view = PlanView(1, Offset.zero);
    expect(view.zoomAt(Offset.zero, 100, min: 0.2, max: 4).scale, 4);
    expect(view.zoomAt(Offset.zero, 0.001, min: 0.2, max: 4).scale, 0.2);
  });

  test('obrócony element trafia się po obrocie, a nie po prostokącie bez obrotu', () {
    final box = PlanBox.of(_element(rotation: 90));
    expect(box.contains(const Offset(500, 390)), isTrue);
    expect(box.contains(const Offset(590, 300)), isFalse);
    expect(box.bounds.width, closeTo(60, 1e-9));
    expect(box.bounds.height, closeTo(200, 1e-9));
  });

  test('krawędź przyciąga się do krawędzi innego obiektu', () {
    final s = snapToGuides(
      const Rect.fromLTWH(103, 400, 100, 50),
      [const Rect.fromLTWH(100, 100, 120, 80)],
      const Size(1000, 600),
      5,
    );
    expect(s.dx, -3);
    expect(s.guideX, 100);
  });

  test('bez niczego w pobliżu nic nie przyciąga', () {
    final s = snapToGuides(
      const Rect.fromLTWH(333, 222, 10, 10),
      const [],
      const Size(1000, 600),
      5,
    );
    expect(s.dx, isNull);
    expect(s.dy, isNull);
  });

  test('prawy uchwyt wydłuża blat, a lewa krawędź zostaje w miejscu', () {
    final start = PlanBox.of(_element(x: 500, y: 300, w: 200, h: 60));
    final r = resizeBox(start, const Offset(1, 0), const Offset(702, 330), min: 5, max: 5000, step: 5);
    expect(r.size.width, 300);
    expect(r.size.height, 60);
    expect(r.center.dx, 550);
    expect(r.center.dy, 300);
  });

  test('uchwyt obróconego blatu działa w jego osiach', () {
    final start = PlanBox.of(_element(x: 500, y: 300, w: 200, h: 60, rotation: 90));
    final r = resizeBox(start, const Offset(1, 0), const Offset(500, 450), min: 5, max: 5000, step: 5);
    expect(r.size.width, 250);
    expect(r.center.dx, closeTo(500, 1e-9));
    expect(r.center.dy, closeTo(325, 1e-9));
  });

  test('obrót co 15 stopni, zero to kierunek w górę', () {
    expect(rotationTowards(Offset.zero, const Offset(0, -10)), 0);
    expect(rotationTowards(Offset.zero, const Offset(10, 0)), 90);
    expect(rotationTowards(Offset.zero, const Offset(10, -9)), 45);
    expect(rotationTowards(Offset.zero, const Offset(-10, 0)), 270);
  });

  test('ściana domyka narożniki i ma kąt od 0 do 179 stopni', () {
    final wall = wallElement(draftKey: 'w', zone: 'sala', a: const Offset(100, 100), b: const Offset(100, 400));
    expect(wall.widthCm, 300 + wallThicknessCm);
    expect(wall.heightCm, wallThicknessCm);
    expect(wall.rotation, 90);
    expect((wall.xCm, wall.yCm), (100, 250));
    final ends = wallEnds(wall);
    expect(ends.first.dy, closeTo(100, 1e-9));
    expect(ends.last.dy, closeTo(400, 1e-9));

    final back = wallElement(draftKey: 'w', zone: 'sala', a: const Offset(400, 100), b: const Offset(100, 100));
    expect(back.rotation, 0);
  });

  test('kąt ściany przyciąga się co 15 stopni', () {
    final p = snapAngle(Offset.zero, const Offset(100, 4));
    expect(p.dy, closeTo(0, 1e-9));
    expect(p.dx, 100);
  });

  test('podpis długości w metrach', () {
    expect(metersLabel(1000), '10 m');
    expect(metersLabel(340), '3,4 m');
    expect(metersLabel(345), '3,45 m');
    expect(metersLabel(50), '0,5 m');
  });
}
