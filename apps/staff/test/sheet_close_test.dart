import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

// „Zamknij” w oknie od dołu na iOS 26 (OverlayGlassButton): natywny przycisk UIKit nad Flutterem pokazuje się
// dopiero, gdy okno stoi, chowa się w ruchu, a okno przyjmuje dotyk jak zwykle (9.11.2026: natywny widok
// platformy w oknie blokował na iPhonie całe okno).
void main() {
  const channel = MethodChannel('pl.table.glass');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'show' ? true : null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Iterable<MethodCall> named(String method) => calls.where((c) => c.method == method);

  testWidgets('natywny przycisk tylko w stojącym oknie, okno działa', (tester) async {
    var closed = 0;
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OverlayGlassButton(
                          symbol: 'xmark',
                          icon: AppIcons.close,
                          label: 'Zamknij',
                          onTap: () {
                            closed++;
                            Navigator.pop(context);
                          },
                        ),
                      ),
                      SizedBox(
                        height: 300,
                        child: Center(
                          child: TextButton(onPressed: () => tapped++, child: const Text('Opcja')),
                        ),
                      ),
                    ],
                  ),
                ),
                child: const Text('Otwórz'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Otwórz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(named('show'), isEmpty, reason: 'okno jeszcze jedzie');

    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(named('show'), hasLength(1));
    final show = named('show').single.arguments as Map<Object?, Object?>;
    final glass = tester.getRect(
      find.descendant(of: find.byType(OverlayGlassButton), matching: find.byType(GlassSurface)),
    );
    expect(Rect.fromLTWH(show['x']! as double, show['y']! as double, 44, 44), glass);
    expect(show['symbol'], 'xmark');

    // Treść okna przyjmuje dotyk.
    await tester.tap(find.text('Opcja'));
    expect(tapped, 1);

    // Przeciąganie okna chowa natywny przycisk, po powrocie okna wraca.
    calls.clear();
    final drag = await tester.startGesture(tester.getCenter(find.text('Opcja')));
    await drag.moveBy(const Offset(0, 30));
    await tester.pump();
    await drag.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(named('hide'), isNotEmpty);
    await drag.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(calls.last.method, 'show');

    // Drugie okno nad pierwszym (np. kółka godzin): natywny przycisk pierwszego się chowa, po zamknięciu wraca.
    calls.clear();
    final sheetContext = tester.element(find.text('Opcja'));
    showModalBottomSheet<void>(context: sheetContext, builder: (_) => const SizedBox(height: 120));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    expect(named('hide'), isNotEmpty);
    expect(named('show'), isEmpty);
    Navigator.pop(sheetContext);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(calls.last.method, 'show');

    // Stuknięcie w natywny przycisk zamyka okno, a przycisk znika na stałe.
    final id = (calls.last.arguments as Map<Object?, Object?>)['id'];
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('pressed', id)),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(find.text('Opcja'), findsNothing);
    expect(named('remove').map((c) => (c.arguments as Map<Object?, Object?>)['id']), contains(id));
  });
}
