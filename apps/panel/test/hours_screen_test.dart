import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
import 'package:table_panel/features/management/hours_screen.dart';

void main() {
  testWidgets('godziny pracy: panel jak w Pracownikach, tabela godzin, filtry i przełączenie na tydzień', (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('pl_PL');
      final loader = FontLoader('packages/table_core/Geist');
      for (final weight in ['Regular', 'Medium', 'SemiBold']) {
        loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
      }
      await loader.load();
    });
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppColors.use(PanelPalette.dark);
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, 1, 9);
    final members = [
      const StaffMember(id: 'm1', name: 'Anna Kowalska', color: 0, active: true),
      const StaffMember(id: 'm2', name: 'Marek Zalewski', color: 1, active: true),
    ];
    final shifts = [
      StaffShift(id: 's1', memberId: 'm1', startedAt: day, endedAt: day.add(const Duration(hours: 8))),
      StaffShift(id: 's2', memberId: 'm1', startedAt: day.add(const Duration(days: 0, hours: 10)), endedAt: day.add(const Duration(hours: 12))),
      StaffShift(
        id: 's3',
        memberId: 'm2',
        startedAt: day,
        endedAt: day.add(const Duration(hours: 6)),
        originalStartedAt: day.subtract(const Duration(minutes: 30)),
        originalEndedAt: day.add(const Duration(hours: 6)),
        editedAt: day,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentRestaurantProvider.overrideWithValue(
            const PanelRestaurant(id: 'r1', name: 'Lokal', city: 'Białystok', isPro: true, role: StaffRole.owner),
          ),
          memberPermissionsProvider.overrideWithValue({'timesheet'}),
          staffProvider.overrideWith((ref, id) async => members),
          shiftsProvider.overrideWith((ref, q) async => shifts),
        ],
        child: MaterialApp(
          theme: PanelTheme.build(PanelPalette.dark),
          home: const Scaffold(body: HoursScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Panel po lewej: przełącznik, wyszukiwanie, „Dopisz zmianę” i filtry z liczbami zmian.
    expect(find.text('Miesiąc'), findsOneWidget);
    expect(find.text('Tydzień'), findsOneWidget);
    expect(find.text('Dopisz zmianę'), findsOneWidget);
    expect(find.text('Anna Kowalska (2)'), findsOneWidget);
    expect(find.text('Marek Zalewski (1)'), findsOneWidget);
    expect(find.text('Poprawione (1)'), findsOneWidget);
    // Tabela: godziny w miesiącu (Anna 8 + 2 = 10 h, Marek 6 h).
    expect(find.text('Pracownik'), findsWidgets);
    expect(find.text('Anna Kowalska'), findsOneWidget);
    expect(find.textContaining('10:00 h'), findsOneWidget);

    // Filtr „Poprawione” zostawia tylko Marka.
    await tester.tap(find.text('Poprawione (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Anna Kowalska'), findsNothing);
    expect(find.text('Marek Zalewski'), findsOneWidget);
    await tester.tap(find.text('Poprawione (1)'));
    await tester.pumpAndSettle();

    // Widok tygodnia.
    await tester.tap(find.text('Tydzień'));
    await tester.pumpAndSettle();
    expect(find.text('Razem'), findsWidgets);
  });
}
