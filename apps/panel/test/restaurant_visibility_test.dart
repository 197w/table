import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
import 'package:table_panel/data/repository.dart';
import 'package:table_panel/features/profile/profile_screen.dart';

class _Repo implements PanelRepository {
  final calls = <(String, bool)>[];
  Object? failure;

  @override
  Future<void> setListed(String restaurantId, bool listed) async {
    if (failure case final e?) throw e;
    calls.add((restaurantId, listed));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<_Repo> open(WidgetTester tester, {required bool listed, bool editable = true}) async {
    await tester.runAsync(() async {
      final loader = FontLoader('packages/table_core/Geist');
      for (final weight in ['Regular', 'Medium', 'SemiBold']) {
        loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
      }
      await loader.load();
    });
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppColors.use(PanelPalette.dark);
    final repo = _Repo();
    final restaurant = PanelRestaurant(
      id: 'r1',
      name: 'Lokal',
      city: 'Białystok',
      isPro: true,
      role: StaffRole.owner,
      listed: listed,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          restaurantsProvider.overrideWith((ref) async => [restaurant]),
        ],
        child: MaterialApp(
          theme: PanelTheme.build(PanelPalette.dark),
          home: Scaffold(body: RestaurantVisibilityCard(restaurant: restaurant, editable: editable)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('widoczny lokal: wyłączenie pyta o potwierdzenie i ukrywa lokal w bazie', (tester) async {
    final repo = await open(tester, listed: true);
    expect(find.text('Widoczność w aplikacji'), findsOneWidget);
    expect(find.text('Lokal widoczny dla klientów'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Ukryć lokal w aplikacji?'), findsOneWidget);
    // „Anuluj” nic nie zmienia.
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ukryj lokal'));
    await tester.pumpAndSettle();
    expect(repo.calls, [('r1', false)]);
  });

  testWidgets('ukryty lokal: włączenie nie pyta o potwierdzenie, błąd weryfikacji jest pokazany', (tester) async {
    final repo = await open(tester, listed: false);
    expect(find.textContaining('Lokal jest ukryty'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Ukryć lokal w aplikacji?'), findsNothing);
    expect(repo.calls, [('r1', true)]);
  });

  testWidgets('bez uprawnień do ustawień przełącznik jest wyłączony', (tester) async {
    final repo = await open(tester, listed: true, editable: false);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(repo.calls, isEmpty);
  });
}
