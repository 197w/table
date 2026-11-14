import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:table_panel/app/app.dart';
import 'package:table_panel/data/delivery_map.dart';

MapOrder _order(String id, {String stage = 'accepted', String? course, DateTime? promised, DateTime? kitchenAt}) =>
    MapOrder(
      id: id,
      number: id.hashCode % 100,
      stage: stage,
      courseId: course,
      address: 'Lipowa $id',
      promisedAt: promised,
      kitchenAt: kitchenAt,
    );

void main() {
  test('trasa z zapisu polyline: 5 i 6 miejsc po przecinku', () {
    const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
    final five = decodePolyline(encoded);
    expect(five.first.latitude, closeTo(38.5, 1e-9));
    expect(five.first.longitude, closeTo(-120.2, 1e-9));
    expect(five.last.latitude, closeTo(43.252, 1e-9));
    final six = decodePolyline(encoded, precision: 6);
    expect(six.first.latitude, closeTo(3.85, 1e-9));
    expect(six.length, 3);
  });

  test('dane mapy z bazy i kursy: w drodze pierwsze, potem obiecana godzina', () {
    final map = DeliveryMap.fromJson({
      'restaurant': {'name': 'REVE', 'address': 'Lodowa 71a, Białystok', 'city': 'Białystok', 'lat': 53.13, 'lng': 23.17},
      'couriers': [
        {'member_id': 'm1', 'name': 'Jan Kowalski', 'busy': true, 'ready': true, 'color': 2, 'vehicle_name': 'Fiat'},
        {'member_id': 'm2', 'name': 'Ola', 'busy': false, 'ready': false, 'lat': 53.1, 'lng': 23.1},
      ],
      'orders': [
        {'id': 'a', 'number': 3, 'fulfillment': 'ready', 'promised_at': '2026-11-14T18:30:00Z'},
        {'id': 'b', 'number': 4, 'fulfillment': 'accepted', 'promised_at': '2026-11-14T18:00:00Z'},
        {'id': 'c', 'number': 5, 'fulfillment': 'on_the_way', 'course_id': 'k', 'courier_member': 'm1'},
        {'id': 'd', 'number': 6, 'fulfillment': 'on_the_way', 'course_id': 'k', 'courier_member': 'm1'},
      ],
    });
    expect(map.restaurant, const LatLng(53.13, 23.17));
    expect(map.couriers.first.initials, 'JK');
    expect(map.couriers.last.ready, isFalse);
    expect(map.couriers.last.position, const LatLng(53.1, 23.1));
    final courses = map.courses;
    expect([for (final c in courses) c.key], ['k', 'b', 'a']);
    expect(courses.first.orders.length, 2);
    expect(courses.first.onTheWay, isTrue);
    expect(courses.first.courierId, 'm1');
    expect(courses.last.ready, isTrue);
  });

  test('najszybsza kolejność przystanków z Optimization API i czasy z postojami', () {
    final trip = parseOptimizedTrip({
      'code': 'Ok',
      'waypoints': [
        {'waypoint_index': 0},
        {'waypoint_index': 2},
        {'waypoint_index': 3},
        {'waypoint_index': 1},
      ],
      'trips': [
        {
          'geometry': '_p~iF~ps|U_ulLnnqC',
          'legs': [
            {'duration': 300, 'distance': 2000},
            {'duration': 240, 'distance': 1500},
            {'duration': 180, 'distance': 900},
          ],
        },
      ],
    }, 3)!;
    // Cel 2 jest pierwszy, potem cel 0, potem cel 1.
    expect(trip.order, [2, 0, 1]);
    expect(trip.seconds, 720);
    expect(trip.meters, 4400);
    expect(trip.cumulative(), const [Duration(seconds: 300), Duration(seconds: 660), Duration(seconds: 960)]);
    expect(parseOptimizedTrip({'code': 'NoRoute'}, 3), isNull);
    final single = parseDirections({
      'code': 'Ok',
      'routes': [
        {
          'geometry': '',
          'legs': [
            {'duration': 420.5, 'distance': 3100},
          ],
        },
      ],
    }, 1)!;
    expect(single.order, [0]);
    expect(single.cumulative().single, const Duration(seconds: 421));
  });

  test('propozycje kursów: blisko siebie, w lokalu, każdy kurs raz, bez pominiętych', () {
    final now = DateTime(2026, 11, 14, 18);
    final courses = groupCourses([
      _order('a', promised: now.add(const Duration(minutes: 30))),
      _order('b', stage: 'ready', promised: now.add(const Duration(minutes: 40))),
      _order('c', promised: now.add(const Duration(minutes: 35))),
      _order('d', stage: 'on_the_way'),
      _order('e', kitchenAt: now.add(const Duration(hours: 1))),
    ]);
    const table = <String, double>{
      '-a': 600, '-b': 700, '-c': 900, '-d': 500, '-e': 650,
      'a-b': 240, 'b-a': 260, 'a-c': 360, 'c-a': 380, 'b-c': 200, 'c-b': 210,
      'a-d': 60, 'd-a': 60, 'a-e': 30, 'e-a': 30,
    };
    double? seconds(String? from, String? to) => table['${from ?? ''}-${to ?? ''}'];

    final all = suggestCourses(courses: courses, seconds: seconds, now: now);
    // b i c są najbliżej (200 s), więc a zostaje bez pary; d jest w drodze, e czeka na kuchnię.
    expect(all.length, 1);
    expect(all.single.orderIds, unorderedEquals(['b', 'c']));
    expect(all.single.gapSeconds, 200);
    // Najpierw b (700 + 200 = 900 s, a przez c 900 + 210), ostatni klient (c) i tak jedzie 900 s: nie czeka dłużej.
    expect(all.single.extraSeconds, 0);

    final withoutBc = suggestCourses(courses: courses, seconds: seconds, now: now, dismissed: {all.single.key});
    expect(withoutBc.single.orderIds, unorderedEquals(['a', 'b']));
    expect(withoutBc.single.extraSeconds, 140);

    // Za daleko od siebie albo obiecane godziny za daleko: brak propozycji.
    expect(suggestCourses(courses: courses, seconds: seconds, now: now, maxGap: const Duration(seconds: 100)), isEmpty);
    final late = groupCourses([
      _order('a', promised: now),
      _order('b', promised: now.add(const Duration(hours: 1))),
    ]);
    expect(suggestCourses(courses: late, seconds: seconds, now: now), isEmpty);
  });

  test('Mapbox: adres z miastem lokalu w pamięci, trasa z korkami, a przy odmowie bez nich', () async {
    final requests = <Uri>[];
    final client = MockClient((req) async {
      requests.add(req.url);
      final path = req.url.path;
      if (path.startsWith('/search/geocode/v6/forward')) {
        return http.Response(
          jsonEncode({
            'features': [
              {
                'geometry': {
                  'coordinates': [23.15, 53.12],
                },
              },
            ],
          }),
          200,
        );
      }
      if (path.contains('/optimized-trips/v1/mapbox/driving-traffic/')) return http.Response('{}', 422);
      if (path.contains('/optimized-trips/v1/mapbox/driving/')) {
        return http.Response(
          jsonEncode({
            'code': 'Ok',
            'waypoints': [
              {'waypoint_index': 0},
              {'waypoint_index': 1},
              {'waypoint_index': 2},
            ],
            'trips': [
              {
                'geometry': '',
                'legs': [
                  {'duration': 100, 'distance': 800},
                  {'duration': 200, 'distance': 1200},
                ],
              },
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    final mapbox = MapboxClient('pk.test', client: client);
    expect(mapbox.configured, isTrue);
    expect(MapboxClient('').configured, isFalse);
    expect(mapbox.tileUrl('mapbox/dark-v11'), contains('/styles/v1/mapbox/dark-v11/tiles/512/{z}/{x}/{y}{r}'));

    final point = await mapbox.geocode('Lipowa 5', near: const LatLng(53.13, 23.17), city: 'Białystok');
    expect(point, const LatLng(53.12, 23.15));
    expect(requests.single.queryParameters['q'], 'Lipowa 5, Białystok');
    expect(requests.single.queryParameters['country'], 'pl');
    expect(requests.single.queryParameters['proximity'], '23.17,53.13');
    await mapbox.geocode('Lipowa 5', city: 'Białystok');
    expect(requests.length, 1, reason: 'drugi raz z pamięci');
    await mapbox.geocode('Lipowa 5, Białystok');
    expect(requests.length, 1, reason: 'miasto już jest w adresie');

    final trip = await mapbox.trip(const LatLng(53.13, 23.17), const [LatLng(53.12, 23.15), LatLng(53.11, 23.16)]);
    expect(trip!.seconds, 300);
    expect(requests[1].path, contains('driving-traffic'));
    expect(requests[2].path, contains('/mapbox/driving/23.170000,53.130000;23.150000,53.120000;23.160000,53.110000'));
    expect(requests[2].queryParameters['source'], 'first');
    expect(requests[2].queryParameters['roundtrip'], 'false');
  });

  test('zakładka Mapa w Dostawach z uprawnieniem do zamówień', () {
    expect(PanelRoutes.deliveryMap, '/mapa');
    expect(canOpenRoute(PanelRoutes.deliveryMap, {'orders'}), isTrue);
    expect(canOpenRoute(PanelRoutes.deliveryMap, {'menu'}), isFalse);
  });
}
