import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
import 'package:table_panel/features/floor/floor_canvas.dart';
import 'package:table_panel/features/floor/floor_screen.dart';

DiningTable _table(String label, int x, int y) => DiningTable(
  id: 'id-$label',
  label: label,
  seats: 4,
  widthCm: 120,
  heightCm: 80,
  zone: 'sala',
  priority: 0,
  active: true,
  xCm: x,
  yCm: y,
  rotation: 0,
  shape: TableShape.rect,
);

/// Geist zamiast testowej czcionki Ahem, żeby napisy w panelach miały prawdziwą szerokość.
Future<void> _loadFonts() async {
  final loader = FontLoader('packages/table_core/Geist');
  for (final weight in ['Regular', 'Medium', 'SemiBold']) {
    loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
  }
  await loader.load();
}

void main() {
  testWidgets('edytor sali: przeciąganie, przybliżanie, ściany, ramka i cofanie', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1200, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppColors.use(PanelPalette.dark);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentRestaurantProvider.overrideWithValue(
            const PanelRestaurant(id: 'r1', name: 'Lokal', city: 'Kraków', isPro: true, role: StaffRole.owner),
          ),
          zonesProvider.overrideWith(
            (ref, id) async => const [FloorZone(id: 'z1', name: 'sala', widthCm: 1200, heightCm: 800, position: 0)],
          ),
          tablesProvider.overrideWith(
            (ref, id) async => [_table('S1', 200, 200), _table('S2', 420, 200), _table('S3', 640, 200)],
          ),
          elementsProvider.overrideWith((ref, id) async => const <FloorElement>[]),
          reservationsProvider.overrideWith((ref, q) async => const <PanelReservation>[]),
        ],
        child: MaterialApp(
          theme: PanelTheme.build(PanelPalette.dark),
          home: const Scaffold(body: FloorScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    FloorCanvas canvas() => tester.widget<FloorCanvas>(find.byType(FloorCanvas));
    Offset at(double x, double y) => tester.getTopLeft(find.byType(FloorCanvas)) + canvas().view!.toScreen(Offset(x, y));
    DiningTable table(String label) => canvas().tables.firstWhere((t) => t.label == label);

    await tester.tap(find.text('Edytuj układ'));
    await tester.pump();

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    Future<void> click(Offset p) async {
      await tester.sendEventToBinding(mouse.hover(p));
      await tester.sendEventToBinding(mouse.down(p));
      await tester.sendEventToBinding(mouse.up());
      await tester.pump();
    }

    Future<void> drag(Offset from, Offset to) async {
      await tester.sendEventToBinding(mouse.hover(from));
      await tester.sendEventToBinding(mouse.down(from));
      for (var i = 1; i <= 6; i++) {
        await tester.sendEventToBinding(mouse.move(Offset.lerp(from, to, i / 6)!));
        await tester.pump();
      }
      await tester.sendEventToBinding(mouse.up());
      await tester.pump();
    }

    // Stolik idzie za myszą co 10 cm.
    await drag(at(420, 200), at(423, 327));
    expect(table('S2').yCm, 330);
    expect(table('S2').xCm, 420);

    // Kółko myszy przybliża, Ctrl+0 wraca do całej strefy.
    final fitScale = canvas().view!.scale;
    await tester.sendEventToBinding(mouse.hover(at(600, 400)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -400)));
    await tester.pump();
    expect(canvas().view!.scale, closeTo(fitScale * 2, 1e-9));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(canvas().view!.scale, closeTo(fitScale, 1e-9));

    // Ściana w kształcie litery L: dwa odcinki, pionowy i poziomy.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await click(at(100, 700));
    await click(at(100, 500));
    await tester.pump(const Duration(milliseconds: 500));
    await click(at(500, 500));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    final walls = canvas().elements;
    expect(walls.map((e) => (e.rotation, e.widthCm, e.heightCm)), [(90, 212, 12), (0, 412, 12)]);

    // Cofnięcie usuwa ostatni odcinek, ponowienie go przywraca.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(canvas().elements, hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(canvas().elements, hasLength(2));

    // Ramka zaznacza stoliki, które przecina.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await drag(at(120, 120), at(720, 260));
    expect(canvas().selectedIds, {'id-S1', 'id-S3'});
    expect(find.text('Zaznaczone: 2'), findsOneWidget);

    // Strzałka przesuwa całe zaznaczenie o 10 cm.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect((table('S1').xCm, table('S3').xCm), (210, 650));

    await tester.pumpWidget(const SizedBox());
  });
}
