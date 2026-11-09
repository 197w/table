import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

// „Zamknij” w oknie od dołu na iOS 26 (OverlayGlassButton): natywny przycisk UIKit nad Flutterem jest cały czas
// i jedzie razem z oknem, chowa się tylko pod drugim oknem, a okno przyjmuje dotyk jak zwykle (9.11.2026: natywny
// widok platformy w oknie blokował na iPhonie całe okno).
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

  testWidgets('natywny przycisk jedzie z oknem, okno działa', (tester) async {
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

    Rect sent(MethodCall call) {
      final a = call.arguments as Map<Object?, Object?>;
      return Rect.fromLTWH(a['x']! as double, a['y']! as double, a['width']! as double, a['height']! as double);
    }

    Rect glass() =>
        tester.getRect(find.descendant(of: find.byType(OverlayGlassButton), matching: find.byType(GlassSurface)));

    await tester.tap(find.text('Otwórz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Natywny od pierwszej klatki i jedzie razem z oknem.
    expect(named('show'), hasLength(1));
    expect(named('show').single.arguments, containsPair('symbol', 'xmark'));
    expect(sent(calls.last), glass());

    await tester.pumpAndSettle();
    expect(named('move'), isNotEmpty);
    expect(named('hide'), isEmpty);
    expect(sent(calls.last), glass());

    // Treść okna przyjmuje dotyk.
    await tester.tap(find.text('Opcja'));
    expect(tapped, 1);

    // Przeciąganie okna przesuwa natywny przycisk razem z oknem, bez chowania.
    calls.clear();
    final drag = await tester.startGesture(tester.getCenter(find.text('Opcja')));
    await drag.moveBy(const Offset(0, 30));
    await tester.pump();
    await drag.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(named('hide'), isEmpty);
    expect(calls.last.method, 'move');
    expect(sent(calls.last), glass());
    await drag.up();
    await tester.pumpAndSettle();
    expect(sent(calls.last), glass());

    // Drugie okno nad pierwszym (np. kółka godzin): natywny przycisk pierwszego się chowa, po zamknięciu wraca.
    calls.clear();
    final sheetContext = tester.element(find.text('Opcja'));
    showModalBottomSheet<void>(context: sheetContext, builder: (_) => const SizedBox(height: 120));
    await tester.pumpAndSettle();
    expect(named('hide'), isNotEmpty);
    expect(named('show'), isEmpty);
    Navigator.pop(sheetContext);
    await tester.pumpAndSettle();
    expect(named('show'), hasLength(1));
    expect(sent(calls.last), glass());

    // Stuknięcie w natywny przycisk zamyka okno: przycisk zjeżdża z oknem i znika na stałe.
    final id = (calls.last.arguments as Map<Object?, Object?>)['id'];
    calls.clear();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('pressed', id)),
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(named('move'), isNotEmpty, reason: 'zjeżdża razem z oknem');
    expect(named('hide'), isEmpty);
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(find.text('Opcja'), findsNothing);
    expect(named('remove').map((c) => (c.arguments as Map<Object?, Object?>)['id']), contains(id));
  });
}
