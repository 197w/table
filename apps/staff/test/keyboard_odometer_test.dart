import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_staff/courier_location.dart';
import 'package:table_staff/data.dart';
import 'package:table_staff/ui.dart';
import 'package:table_staff/vehicle_check.dart';

// 25.11.2026: klawiatura chowa się po stuknięciu w tło, przebieg mniejszy niż ostatnio widać od razu przy polu,
// a zgoda na lokalizację na iPhonie idzie wprost z CoreLocation.
void main() {
  testWidgets('dotknięcie poza polem chowa klawiaturę, dotknięcie pola nie, przyciski działają', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TapToDismissKeyboard(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              const TextField(key: Key('pole'), decoration: InputDecoration(labelText: 'Szukaj')),
              TextButton(onPressed: () => pressed++, child: const Text('Plus')),
              const SizedBox(height: 300, child: Center(child: Text('Tło'))),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('pole')));
    await tester.pump();
    bool focused() => tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;
    expect(focused(), isTrue);

    // Stuknięcie w pole (także w napis pola) nie zamyka klawiatury.
    await tester.tap(find.text('Szukaj'));
    await tester.pump();
    expect(focused(), isTrue);

    // Przycisk działa i chowa klawiaturę.
    await tester.tap(find.text('Plus'));
    await tester.pump();
    expect(pressed, 1);
    expect(focused(), isFalse);

    // Tło zamyka.
    await tester.tap(find.byKey(const Key('pole')));
    await tester.pump();
    expect(focused(), isTrue);
    await tester.tap(find.text('Tło'));
    await tester.pump();
    expect(focused(), isFalse);
  });

  // 26.11.2026: wersja z GestureDetector nad aplikacją wstrzymywała rozstrzygnięcie dotyku do podniesienia palca,
  // przez co natywne dolne menu na iPhonie nie reagowało na stuknięcia. Widok, który rozpoznaje dotyk sam (jak natywna
  // kontrolka), ma wygrać od razu przy dotknięciu.
  testWidgets('nie wstrzymuje dotyku dla natywnych kontrolek', (tester) async {
    final solo = _SoloRecognizer();
    addTearDown(solo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TapToDismissKeyboard(child: child!),
        home: Scaffold(
          body: Center(
            child: RawGestureDetector(
              gestures: {
                _SoloRecognizer: GestureRecognizerFactoryWithHandlers<_SoloRecognizer>(() => solo, (_) {}),
              },
              child: const SizedBox(width: 200, height: 50, child: Text('Zakładka')),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(tester.getCenter(find.text('Zakładka')));
    await tester.pump();
    expect(solo.acceptedBeforeUp, isTrue);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('przebieg mniejszy niż ostatnio: błąd od razu przy polu', (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const job = Job(
      memberId: 'm1',
      restaurantId: 'r1',
      restaurantName: 'Lokal',
      memberName: 'Marek',
      weekSeconds: 0,
      isCourier: true,
    );
    const status = VehicleStatus(
      required: true,
      onShift: true,
      vehicleId: 'v1',
      startDone: true,
      endDone: false,
      startKm: 130,
      startVehicleId: 'v1',
      vehicles: [CheckVehicle(id: 'v1', name: 'Fiat Punto', kind: 'car', plate: 'BI 12345', lastKm: 130)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [vehicleStatusProvider.overrideWith((ref, id) async => status)],
        child: MaterialApp(
          theme: AppTheme.build(AppPalette.dark),
          builder: (context, child) => TapToDismissKeyboard(child: child!),
          home: const VehicleCheckScreen(job: job, end: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    await tester.enterText(field, '128');
    await tester.pump();
    expect(find.text('Mniej niż ostatnio (130 km). Sprawdź licznik.'), findsOneWidget);

    await tester.enterText(field, '131');
    await tester.pump();
    expect(find.textContaining('Mniej niż ostatnio'), findsNothing);

    // Stuknięcie w napis nad polem (tło) chowa klawiaturę.
    await tester.tap(field);
    await tester.pump();
    bool focused() => tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;
    expect(focused(), isTrue);
    await tester.tap(find.textContaining('Wpisz przebieg i zrób zdjęcia'));
    await tester.pump();
    expect(focused(), isFalse);
  });

  test('stan zgody z CoreLocation', () {
    expect(iosLocationGate('whenInUse'), LocationGate.ready);
    expect(iosLocationGate('always'), LocationGate.ready);
    expect(iosLocationGate('notDetermined'), LocationGate.denied);
    expect(iosLocationGate('denied'), LocationGate.deniedForever);
    expect(iosLocationGate('restricted'), LocationGate.deniedForever);
    expect(iosLocationGate(null), LocationGate.denied);
  });
}

/// Jak natywny widok: przyjmuje dotyk, gdy nikt inny go nie chce, i pamięta, czy stało się to jeszcze przed
/// podniesieniem palca.
class _SoloRecognizer extends OneSequenceGestureRecognizer {
  bool _up = false;
  bool acceptedBeforeUp = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _up = false;
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent) _up = true;
    stopTrackingIfPointerNoLongerDown(event);
  }

  @override
  void acceptGesture(int pointer) {
    if (!_up) acceptedBeforeUp = true;
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'natywny widok';
}
