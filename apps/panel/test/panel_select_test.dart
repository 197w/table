import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/shared/panel_select.dart';
import 'package:table_panel/shared/panel_widgets.dart';

Future<void> _boot(WidgetTester tester, Widget child, {Size size = const Size(900, 700)}) async {
  await tester.runAsync(() async {
    final loader = FontLoader('packages/table_core/Geist');
    for (final weight in ['Regular', 'Medium', 'SemiBold']) {
      loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
    }
    await loader.load();
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  AppColors.use(PanelPalette.dark);
  await tester.pumpWidget(
    MaterialApp(
      theme: PanelTheme.build(PanelPalette.dark),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(24), child: Align(alignment: Alignment.topLeft, child: child)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('lista wyboru', () {
    testWidgets('otwiera panel z opcjami, wybrana ma haczyk, wybór zmienia pole i woła onChanged', (tester) async {
      String? picked;
      await _boot(
        tester,
        SizedBox(
          width: 320,
          child: PanelSelect<String>(
            initialValue: 'greeting',
            decoration: const InputDecoration(labelText: 'Rodzaj'),
            items: const [
              DropdownMenuItem(value: 'audio', child: Text('Plik audio')),
              DropdownMenuItem(value: 'greeting', child: Text('Powitanie')),
              DropdownMenuItem(value: 'siren', child: Text('Syrena')),
            ],
            onChanged: (v) => picked = v,
          ),
        ),
      );
      // Zamknięta: tylko wybrana opcja.
      expect(find.text('Powitanie'), findsOneWidget);
      expect(find.text('Syrena'), findsNothing);

      await tester.tap(find.text('Powitanie'));
      await tester.pumpAndSettle();
      // Otwarta: wszystkie opcje, haczyk tylko przy wybranej, wybrana pogrubiona.
      expect(find.text('Plik audio'), findsOneWidget);
      expect(find.text('Syrena'), findsOneWidget);
      expect(find.descendant(of: find.byType(MenuItemButton), matching: find.byType(Glyph)), findsOneWidget);
      final bold = tester.widget<DefaultTextStyle>(
        find.ancestor(of: find.text('Powitanie').last, matching: find.byType(DefaultTextStyle)).first,
      );
      expect(bold.style.fontWeight, FontWeight.w600);
      final plain = tester.widget<DefaultTextStyle>(
        find.ancestor(of: find.text('Syrena'), matching: find.byType(DefaultTextStyle)).first,
      );
      expect(plain.style.fontWeight, FontWeight.w400);

      await tester.tap(find.text('Syrena'));
      await tester.pumpAndSettle();
      expect(picked, 'siren');
      expect(find.text('Plik audio'), findsNothing);
      expect(find.text('Syrena'), findsOneWidget);
    });

    testWidgets('pozycja z wartością null jest wybraną, gdy nic nie wybrano; wyłączona nie otwiera listy', (tester) async {
      await _boot(
        tester,
        Column(
          children: [
            SizedBox(
              width: 320,
              child: PanelSelect<String?>(
                initialValue: null,
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('Bez auta')),
                  DropdownMenuItem<String?>(value: 'a', child: Text('Fiat')),
                ],
                onChanged: (_) {},
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 320,
              child: PanelSelect<String>(
                initialValue: 'x',
                items: [DropdownMenuItem(value: 'x', child: Text('Stała'))],
                onChanged: null,
              ),
            ),
          ],
        ),
      );
      expect(find.text('Bez auta'), findsOneWidget);
      await tester.tap(find.text('Stała'));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      await tester.tap(find.text('Bez auta'));
      await tester.pumpAndSettle();
      expect(find.text('Fiat'), findsOneWidget);
    });
  });

  group('przełącznik opcji', () {
    Widget tabs(ValueNotifier<int> selected, {bool expand = false}) => ValueListenableBuilder<int>(
      valueListenable: selected,
      builder: (_, value, _) => SegmentedTabs<int>(
        expand: expand,
        options: const [(0, 'Sprzedaż'), (1, 'Goście'), (2, 'Inwentaryzacja')],
        selected: value,
        onChanged: (v) => selected.value = v,
      ),
    );

    double widthOf(WidgetTester tester, String label) =>
        tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(PanelPress)).first).width;

    testWidgets('wszystkie opcje mają tę samą szerokość: najdłuższego napisu', (tester) async {
      final selected = ValueNotifier(0);
      await _boot(tester, tabs(selected));
      final a = widthOf(tester, 'Sprzedaż');
      final b = widthOf(tester, 'Goście');
      final c = widthOf(tester, 'Inwentaryzacja');
      expect(a, b);
      expect(b, c);
      // Szerokość najdłuższego napisu (Inwentaryzacja) z marginesem, więc szersza niż sam krótki napis.
      expect(a, greaterThan(100));
      // Zmiana wyboru nie zmienia szerokości.
      selected.value = 2;
      await tester.pumpAndSettle();
      expect(widthOf(tester, 'Sprzedaż'), a);
    });

    testWidgets('z expand opcje dzielą szerokość po równo', (tester) async {
      final selected = ValueNotifier(0);
      await _boot(tester, SizedBox(width: 480, child: tabs(selected, expand: true)));
      final a = widthOf(tester, 'Sprzedaż');
      expect(widthOf(tester, 'Goście'), a);
      expect(widthOf(tester, 'Inwentaryzacja'), a);
      expect(a * 3, closeTo(480 - 6, 0.5));
    });

    testWidgets('kliknięcie wybiera opcję, a przeciągnięcie po pigułce przesuwa wybór', (tester) async {
      final selected = ValueNotifier(0);
      await _boot(tester, tabs(selected));
      await tester.tap(find.text('Goście'));
      await tester.pumpAndSettle();
      expect(selected.value, 1);

      // Przeciągnięcie z pierwszej opcji na koniec wybiera ostatnią.
      final first = tester.getCenter(find.text('Sprzedaż'));
      final gesture = await tester.startGesture(first);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(selected.value, 0, reason: 'jeszcze w pierwszej opcji');
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(selected.value, 1);
      await gesture.moveBy(const Offset(160, 0));
      await tester.pump();
      expect(selected.value, 2);
      // Przeciągnięcie poza pigułkę zostaje przy skrajnej opcji.
      await gesture.moveBy(const Offset(300, 0));
      await tester.pump();
      expect(selected.value, 2);
      await gesture.moveBy(const Offset(-900, 0));
      await tester.pump();
      expect(selected.value, 0);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
