import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table/data/models.dart';
import 'package:table/data/providers.dart';
import 'package:table/features/discover/restaurant_cards.dart';
import 'package:table/features/restaurant/event_widgets.dart';
import 'package:table_core/table_core.dart';

// Wydarzenia dla gości (26.11.2026, prośba użytkownika: „wydarzenia nie są za bardzo widoczne i krzykliwe”):
// znaczek z „kiedy”, wybór wydarzenia do karty w Odkrywaj, zniżki i specjalne menu wydarzenia.

RestaurantEvent _event(
  String id,
  DateTime start,
  DateTime end, {
  String restaurant = 'r1',
  bool allDay = false,
  String color = 'violet',
}) => RestaurantEvent(
  id: id,
  title: 'Wieczór $id',
  startsAt: start,
  endsAt: end,
  allDay: allDay,
  color: color,
  restaurantId: restaurant,
  description: 'Muzyka na żywo i zimowe menu.',
);

void main() {
  final now = DateTime(2026, 11, 26, 17, 0); // czwartek

  test('kiedy na znaczku', () {
    expect(eventBadgeWhen(_event('a', DateTime(2026, 11, 26, 16), DateTime(2026, 11, 26, 22)), now), 'Trwa teraz');
    expect(eventBadgeWhen(_event('a', DateTime(2026, 11, 26, 18), DateTime(2026, 11, 26, 22)), now), 'Dziś 18:00');
    expect(eventBadgeWhen(_event('a', DateTime(2026, 11, 27, 19, 30), DateTime(2026, 11, 27, 23)), now), 'Jutro 19:30');
    expect(eventBadgeWhen(_event('a', DateTime(2026, 11, 29, 12), DateTime(2026, 11, 29, 14)), now), 'Niedz 12:00');
    expect(
      eventBadgeWhen(_event('a', DateTime(2026, 12, 6), DateTime(2026, 12, 7), allDay: true), now),
      '6 gru',
    );
  });

  test('przy lokalu trwające wydarzenie, bez niego najbliższe', () {
    final events = [
      _event('wcześniej', DateTime(2026, 11, 26, 12), DateTime(2026, 11, 26, 23)),
      _event('później', DateTime(2026, 11, 27, 18), DateTime(2026, 11, 27, 23)),
      _event('b1', DateTime(2026, 11, 28, 18), DateTime(2026, 11, 28, 23), restaurant: 'r2'),
      _event('b0', DateTime(2026, 11, 27, 18), DateTime(2026, 11, 27, 23), restaurant: 'r2'),
      _event('minione', DateTime(2026, 11, 20, 18), DateTime(2026, 11, 20, 23), restaurant: 'r3'),
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final featured = featuredEvents(events, now);
    expect(featured['r1']!.id, 'wcześniej');
    expect(featured['r2']!.id, 'b0');
    expect(featured.containsKey('r3'), isFalse);
  });

  test('zniżki i specjalne menu wydarzenia', () {
    final e = _event('e1', DateTime(2026, 11, 28, 18), DateTime(2026, 11, 28, 23));
    final other = _event('e2', DateTime(2026, 12, 5, 18), DateTime(2026, 12, 5, 23));
    Map<String, dynamic> discount(int percent, RestaurantEvent ev) => {
      'percent': percent,
      'event': {'starts_at': ev.startsAt.toUtc().toIso8601String(), 'ends_at': ev.endsAt.toUtc().toIso8601String()},
    };
    final perks = eventPerksFrom([
      {'name': 'Pizze', 'discounts': [discount(10, e)]},
      {'name': 'Desery', 'discounts': [discount(25, e), discount(5, other)]},
      {'name': 'Zimowe dania', 'event_id': 'e1', 'discounts': const []},
      {'name': 'Napoje', 'discounts': const []},
    ], [e, other]);
    expect(perks['e1'], ['−25% · Desery', '−10% · Pizze', 'Specjalne menu · Zimowe dania']);
    expect(perks['e2'], ['−5% · Desery']);
  });

  testWidgets('karta wydarzenia i znaczek na karcie lokalu', (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('pl_PL');
      final loader = FontLoader('packages/table_core/Geist');
      for (final weight in ['Regular', 'Medium', 'SemiBold']) {
        loader.addFont(rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
      }
      await loader.load();
    });
    tester.view.physicalSize = const Size(400, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppColors.use(AppPalette.dark);
    final start = DateTime.now().subtract(const Duration(hours: 1));
    final live = _event('e1', start, start.add(const Duration(hours: 5)));
    final later = _event('e2', start.add(const Duration(days: 2)), start.add(const Duration(days: 2, hours: 4)), color: 'amber');
    const r = RestaurantSummary(
      id: 'r1',
      name: 'REVE Restaurant',
      cuisine: 'polska',
      priceLevel: 2,
      address: 'Lipowa 1',
      city: 'Białystok',
      isPro: true,
      isExample: false,
      distanceM: 1200,
      verifiedReviews: 4,
      unverifiedReviews: 0,
      foodAvg: 8.6,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upcomingEventsProvider.overrideWith((ref) async => {'r1': live}),
          likedIdsProvider.overrideWith(_NoLikes.new),
        ],
        child: MaterialApp(
          theme: AppTheme.build(AppPalette.dark),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                EventCard(event: live, featured: true, perks: const ['−20% · Pizze', 'Specjalne menu · Zimowe dania'], onMenu: () {}),
                const SizedBox(height: 12),
                EventCard(event: later),
                const SizedBox(height: 16),
                const RestaurantCard(restaurant: r, showDistance: true, unit: DistanceUnit.kilometers),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('TRWA TERAZ'), findsOneWidget);
    expect(find.text('Wieczór e1'), findsOneWidget);
    expect(find.text('−20% · Pizze'), findsOneWidget);
    expect(find.text('Zobacz menu'), findsOneWidget);
    expect(find.text('Trwa teraz · Wieczór e1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _NoLikes extends LikedIdsNotifier {
  @override
  Future<Set<String>> build() async => const {};
}
