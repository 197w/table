import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/app/panel_theme.dart';
import 'package:table_panel/data/courier_history.dart';
import 'package:table_panel/data/delivery_map.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';
import 'package:table_panel/features/deliveries/delivery_map_screen.dart';

// Historia tras dostawców (24.11.2026): kursy z punktów telefonu i dostaw, powroty, postoje, przerwy w danych
// i objazd wobec najkrótszej trasy z Mapbox.

const _restaurant = LatLng(53.1300, 23.1600);

DateTime _t(int h, int m) => DateTime(2026, 11, 24, h, m);

List<Object> _p(DateTime at, double lat, double lng) => [at.millisecondsSinceEpoch, lat, lng, 8.0];

Map<String, dynamic> _o(String id, int number, {String? course, DateTime? picked, DateTime? delivered, DateTime? promised}) =>
    {
      'id': id,
      'number': number,
      'course_id': course,
      'fulfillment': delivered != null ? 'delivered' : (picked != null ? 'on_the_way' : 'ready'),
      'address': 'Lipowa $number, Białystok',
      'customer': 'Klient $number',
      'picked_up_at': picked?.toUtc().toIso8601String(),
      'delivered_at': delivered?.toUtc().toIso8601String(),
      'promised_at': promised?.toUtc().toIso8601String(),
    };

/// Dzień Marka: kurs #12 naokoło (na wschód, potem na północ i z powrotem na zachód), powrót do lokalu, kurs
/// #14 i #15 prosto, powrót, a od 20:00 kurs #16 w drodze. #17 czeka w lokalu.
CourierTrack _day() => CourierTrack.fromJson({
  'points': [
    _p(_t(18, 0), 53.1300, 23.1600),
    _p(_t(18, 3), 53.1300, 23.1800),
    _p(_t(18, 7), 53.1450, 23.1800),
    _p(_t(18, 11), 53.1450, 23.1600),
    _p(_t(18, 15), 53.1400, 23.1600),
    _p(_t(18, 20), 53.1350, 23.1600),
    _p(_t(18, 25), 53.1301, 23.1601),
    _p(_t(19, 0), 53.1300, 23.1600),
    _p(_t(19, 5), 53.1250, 23.1600),
    _p(_t(19, 10), 53.1200, 23.1600),
    _p(_t(19, 15), 53.1200, 23.1650),
    _p(_t(19, 20), 53.1200, 23.1700),
    _p(_t(19, 30), 53.1302, 23.1602),
    _p(_t(20, 0), 53.1300, 23.1600),
    _p(_t(20, 5), 53.1300, 23.1500),
  ],
  'orders': [
    _o('a', 12, picked: _t(18, 0), delivered: _t(18, 15), promised: _t(18, 10)),
    _o('b', 15, course: 'k2', picked: _t(19, 0), delivered: _t(19, 20), promised: _t(19, 30)),
    _o('c', 14, course: 'k2', picked: _t(19, 0), delivered: _t(19, 10), promised: _t(19, 30)),
    _o('d', 16, picked: _t(20, 0)),
    _o('e', 17),
  ],
});

MapTrip _trip(List<double> meters, {List<int>? order}) => MapTrip(
  order: order ?? [for (var i = 0; i < meters.length; i++) i],
  legSeconds: [for (final m in meters) m / 8],
  legMeters: meters,
  geometry: const [],
);

/// Kafelki bez sieci: przezroczysty obrazek 1×1.
class _BlankTiles extends TileProvider {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => MemoryImage(Uint8List.fromList(_png));
}

void main() {
  group('kursy z trasy telefonu', () {
    test('punkty i dostawy z bazy', () {
      final track = _day();
      expect(track.points.length, 15);
      expect(track.points.first.point, const LatLng(53.13, 23.16));
      expect(track.points.first.speed, 8.0);
      expect(track.points.first.at, _t(18, 0));
      expect(track.orders.first.courseKey, 'a');
      expect(track.orders[1].courseKey, 'k2');
      expect(track.orders.first.deliveredAt, _t(18, 15));
      expect(CourierTrack.fromJson(const {}).points, isEmpty);
    });

    test('kurs od odbioru do ostatniego dowiezienia, powrót do lokalu, kurs w drodze do ostatniego punktu', () {
      final rides = courierRides(_day(), restaurant: _restaurant);
      expect(rides.map((r) => r.key), ['a', 'back:a', 'k2', 'back:k2', 'd']);

      final first = rides.first;
      expect(first.from, _t(18, 0));
      expect(first.to, _t(18, 15));
      expect(first.points.length, 5);
      expect(first.finished, isTrue);

      // Powrót kończy się na pierwszym punkcie przy lokalu (150 m).
      final back = rides[1];
      expect(back.back, isTrue);
      expect(back.from, _t(18, 15));
      expect(back.to, _t(18, 25));
      expect(back.orders, isEmpty);

      // Dwie dostawy w jednym kursie po kolei dowiezienia.
      final course = rides[2];
      expect(course.orders.map((o) => o.number), [14, 15]);
      expect(course.to, _t(19, 20));
      expect(course.dropPoints(_day().points), [const LatLng(53.12, 23.16), const LatLng(53.12, 23.17)]);

      final onTheWay = rides.last;
      expect(onTheWay.finished, isFalse);
      expect(onTheWay.to, _t(20, 5));

      // Bez położenia lokalu nie ma powrotów; nieodebrana dostawa (#17) nie jest kursem.
      expect(courierRides(_day()).map((r) => r.key), ['a', 'k2', 'd']);

      final summary = daySummary(rides, _day().points);
      expect(summary.courses, 3);
      expect(summary.riding, const Duration(minutes: 15 + 20 + 5));
      expect(summary.meters, closeTo(trackMeters(_day().points), 0.001));
    });

    test('postoje: stoi kilka minut w jednym miejscu (bez punktów z telefonu), poza lokalem i adresami', () {
      final track = CourierTrack.fromJson({
        'points': [
          _p(_t(18, 0), 53.1300, 23.1600),
          _p(_t(18, 3), 53.1350, 23.1700),
          _p(_t(18, 11), 53.13502, 23.17005), // 8 minut w tym samym miejscu
          _p(_t(18, 14), 53.1400, 23.1800),
          _p(_t(18, 16), 53.1450, 23.1900),
          _p(_t(18, 17), 53.1451, 23.1901),
        ],
      });
      final stops = trackStops(track.points, skip: [_restaurant]);
      expect(stops.length, 1);
      expect(stops.single.from, _t(18, 3));
      expect(stops.single.duration, const Duration(minutes: 8));
      // Przy adresie dostawy to nie postój.
      expect(trackStops(track.points, skip: [const LatLng(53.135, 23.17)]), isEmpty);
      // Krótko w miejscu też nie.
      expect(trackStops(track.points, minimum: const Duration(minutes: 10)), isEmpty);
    });

    test('przerwa w danych: długo bez punktów, a dostawca jest daleko', () {
      final points = CourierTrack.fromJson({
        'points': [
          _p(_t(18, 0), 53.1300, 23.1600),
          _p(_t(18, 10), 53.1600, 23.1600),
          _p(_t(18, 11), 53.1610, 23.1600),
        ],
      }).points;
      expect(trackGaps(points), 1);
      expect(trackGaps(points.sublist(1)), 0);
    });
  });

  group('objazd wobec najkrótszej trasy', () {
    test('ponad 30% i ponad 1 km dłużej to objazd', () {
      final ride = courierRides(_day(), restaurant: _restaurant).first;
      final driven = ride.meters;
      expect(driven, greaterThan(4500));
      final check = checkRide(ride, _trip([1300]))!;
      expect(check.driven, driven);
      expect(check.planned, 1300);
      expect(check.detour, isTrue);
      expect(check.extraPercent, greaterThan(200));
      expect(check.otherOrder, isFalse);

      // Kilka procent dłużej to trasa w normie; ponad 30%, ale mniej niż 1 km też.
      expect(checkRide(ride, _trip([driven * 0.95]))!.detour, isFalse);
      expect(const RideCheck(driven: 1800, planned: 1000).detour, isFalse);
      expect(const RideCheck(driven: 2100, planned: 1000).detour, isTrue);

      // Bez trasy z Mapbox albo bez punktów nie ma oceny.
      expect(checkRide(ride, null), isNull);
    });

    test('inna kolejność adresów niż najszybsza', () {
      final course = courierRides(_day(), restaurant: _restaurant)[2];
      expect(checkRide(course, _trip([1100, 700], order: [1, 0]))!.otherOrder, isTrue);
      expect(checkRide(course, _trip([1100, 700]))!.otherOrder, isFalse);
    });
  });

  testWidgets('Mapa → Historia: dostawca, kursy, objazd i powrót w normie', (tester) async {
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

    // Mapbox: każda najkrótsza trasa ma 1,3 km.
    final requests = <Uri>[];
    final mapbox = MapboxClient(
      'pk.test',
      client: MockClient((req) async {
        requests.add(req.url);
        if (req.url.path.contains('/directions/v5/')) {
          return http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'geometry': '',
                  'legs': [
                    {'duration': 200, 'distance': 1300},
                  ],
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    final track = CourierTrack.fromJson({
      'points': [for (final p in (_day().points.take(7))) _p(p.at, p.point.latitude, p.point.longitude)],
      'orders': [_o('a', 12, picked: _t(18, 0), delivered: _t(18, 15), promised: _t(18, 10))],
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentRestaurantProvider.overrideWithValue(
            const PanelRestaurant(id: 'r1', name: 'Lokal', city: 'Białystok', isPro: true, role: StaffRole.owner),
          ),
          mapboxProvider.overrideWithValue(mapbox),
          deliveryMapProvider.overrideWith(
            (ref, id) async => const DeliveryMap(
              restaurantName: 'Lokal',
              restaurantCity: 'Białystok',
              restaurant: _restaurant,
              couriers: [],
              orders: [],
            ),
          ),
          courierDaysProvider.overrideWith(
            (ref, q) async => const [CourierDay(memberId: 'm1', name: 'Marek', points: 7, deliveries: 1)],
          ),
          courierHistoryProvider.overrideWith((ref, q) async => track),
        ],
        child: MaterialApp(
          theme: PanelTheme.build(PanelPalette.dark),
          home: Scaffold(body: DeliveryMapScreen(tileProvider: _BlankTiles())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Historia'));
    await tester.pumpAndSettle();

    expect(find.text('Marek · 1 dostawa'), findsOneWidget);
    expect(find.text('Dziś'), findsOneWidget);
    expect(find.text('#12'), findsWidgets);
    expect(find.text('Powrót do lokalu'), findsOneWidget);
    expect(find.text('18:00–18:15 · 15 min'), findsOneWidget);
    // Kurs naokoło: objazd z kilometrami; powrót prosto: w normie.
    expect(find.textContaining('Objazd +'), findsOneWidget);
    expect(find.text('Trasa w normie'), findsOneWidget);
    expect(find.text('Objazdy: 1'), findsOneWidget);
    expect(find.textContaining('najkrótsza 1,3 km'), findsNWidgets(2));
    expect(find.textContaining('spóźnione 5 min'), findsOneWidget);
    // Dwie trasy z Mapbox: kurs i powrót (bez szukania adresu: miejsce dowiezienia z telefonu).
    expect(requests.where((u) => u.path.contains('/directions/v5/')).length, 2);
    expect(requests.where((u) => u.path.contains('/geocode/')), isEmpty);

    // Kliknięcie kursu zaznacza go; drugi raz odznacza.
    await tester.tap(find.textContaining('Objazd +'));
    await tester.pumpAndSettle();

    // Zamknięcie ekranu zatrzymuje odświeżanie.
    await tester.pumpWidget(const SizedBox());
  });
}
