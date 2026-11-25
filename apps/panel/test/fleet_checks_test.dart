import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
import 'package:table_panel/data/repository.dart';
import 'package:table_panel/features/fleet/fleet_screen.dart';
import 'package:table_panel/features/fleet/vehicle_days.dart';

class _Repo implements PanelRepository {
  @override
  Future<Map<String, String>> vehiclePhotoUrls(List<String> paths) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Flota → aparat (25.11.2026, prośba użytkownika): „Przebieg i zdjęcia” w oknie przy prawej krawędzi zamiast okna na
// środku, aparat w kolorze aplikacji.
void main() {
  testWidgets('aparat otwiera Przebieg i zdjęcia z prawej, Zamknij zamyka', (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('pl_PL');
      final loader = FontLoader('packages/table_core/Geist');
      for (final weight in ['Regular', 'Medium', 'SemiBold']) {
        loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
      }
      await loader.load();
    });
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppColors.use(PanelPalette.dark);

    const car = Vehicle(id: 'v1', kind: VehicleKind.car, name: 'Fiat Punto', active: true, plate: 'BI 12345');
    final day = DateTime(2026, 11, 24);
    final checks = [
      VehicleCheck(
        id: 'c2',
        vehicleId: 'v1',
        day: day,
        start: false,
        createdAt: DateTime(2026, 11, 24, 22, 10),
        memberName: 'Marek',
        odometerKm: 130180,
        photos: const ['a', 'b', 'c', 'd'],
      ),
      VehicleCheck(
        id: 'c1',
        vehicleId: 'v1',
        day: day,
        start: true,
        createdAt: DateTime(2026, 11, 24, 16, 2),
        memberName: 'Marek',
        odometerKm: 130042,
        photos: const ['e', 'f', 'g', 'h'],
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentRestaurantProvider.overrideWithValue(
            const PanelRestaurant(id: 'r1', name: 'Lokal', city: 'Białystok', isPro: true, role: StaffRole.owner),
          ),
          repositoryProvider.overrideWithValue(_Repo()),
          memberPermissionsProvider.overrideWithValue(const {'fleet'}),
          vehiclesProvider.overrideWith((ref, id) async => const [car]),
          staffProvider.overrideWith((ref, id) async => const <StaffMember>[]),
          todayVehicleDaysProvider.overrideWith((ref, id) async => const <VehicleDay>[]),
          vehicleNotesProvider.overrideWith((ref, id) async => const <String, List<Note>>{}),
          vehicleChecksProvider.overrideWith((ref, q) async => checks),
        ],
        child: MaterialApp(
          theme: PanelTheme.build(PanelPalette.dark),
          home: const Scaffold(body: FleetScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Przebieg i zdjęcia'), findsNothing);

    final camera = find.byTooltip('Przebieg i zdjęcia');
    // Aparat w kolorze aplikacji.
    final glyph = tester.widget<IconButton>(find.ancestor(of: find.byType(Glyph), matching: find.byType(IconButton)).last);
    expect(glyph.style?.foregroundColor?.resolve(const {}), AppColors.accent);

    await tester.tap(camera);
    await tester.pumpAndSettle();
    expect(find.text('Przebieg i zdjęcia'), findsOneWidget);
    expect(find.text('Fiat Punto · BI 12345'), findsWidgets);
    expect(find.text('130 180 km'), findsOneWidget);
    expect(find.text('130 042 km'), findsOneWidget);
    expect(find.text('Przejechane: 138 km'), findsOneWidget);
    // Okno stoi przy prawej krawędzi, nad tabelą (nie na środku).
    final sheet = tester.getRect(find.byType(VehicleChecksSheet));
    expect(sheet.right, 1500);
    expect(sheet.width, vehicleChecksSheetWidth);
    expect(find.byType(AlertDialog), findsNothing);

    // Okno zakrywa aparat (może zakrywać resztę), więc zamyka je „Zamknij”.
    await tester.tap(find.byTooltip('Zamknij'));
    await tester.pumpAndSettle();
    expect(find.text('Przebieg i zdjęcia'), findsNothing);
  });
}
