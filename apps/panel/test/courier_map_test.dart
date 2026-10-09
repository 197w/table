import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/courier_map.dart';

void main() {
  test('linia trasy z zapisu Google i OSRM', () {
    // Przykład z dokumentacji Google: trzy punkty.
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points, hasLength(3));
    expect(points[0].latitude, closeTo(38.5, 1e-5));
    expect(points[0].longitude, closeTo(-120.2, 1e-5));
    expect(points[1].latitude, closeTo(40.7, 1e-5));
    expect(points[2].longitude, closeTo(-126.453, 1e-5));
    expect(decodePolyline(''), isEmpty);
  });

  test('mapa dostawców: dostawcy, cele, trasy i czekające dostawy', () {
    final now = DateTime.now();
    final map = CourierMap.fromJson({
      'tracking': true,
      'restaurant': {'name': 'REVE', 'address': 'Rynek 1, Białystok', 'lat': 53.13, 'lng': 23.16},
      'couriers': [
        {
          'member_id': 'm1', 'name': 'Adam Nowak', 'busy': true, 'located': true, 'color': 1,
          'lat': 53.12, 'lng': 23.15, 'updated_at': now.toUtc().toIso8601String(),
        },
        {'member_id': 'm2', 'name': 'Bartek', 'busy': false, 'located': false},
      ],
      'orders': [
        {'id': 'o1', 'number': 12, 'fulfillment': 'on_the_way', 'courier_member': 'm1', 'lat': 53.11, 'lng': 23.14,
         'geo': 'google', 'address': 'Lipowa 1'},
        {'id': 'o2', 'number': 13, 'fulfillment': 'ready', 'address': 'Polna 2'},
        {'id': 'o3', 'number': 14, 'fulfillment': 'accepted', 'address': 'Nieznana 9', 'geo': 'none'},
      ],
      'routes': [
        {'member_id': 'm1', 'order_id': 'o1', 'polyline': '_p~iF~ps|U_ulLnnqC', 'duration_s': 600, 'distance_m': 2300,
         'provider': 'google', 'computed_at': now.toUtc().toIso8601String()},
      ],
    });
    expect(map.couriers.first.initials, 'AN');
    expect(map.couriers.last.initials, 'BA');
    expect(map.couriers.first.stale(now), isFalse);
    expect(map.couriers.last.stale(now), isTrue);
    final o1 = map.orders.first;
    expect(o1.onTheWay, isTrue);
    expect(map.routeFor(o1)!.points, hasLength(2));
    expect(map.routeFor(o1)!.arrival!.difference(now).inMinutes, inInclusiveRange(9, 10));
    expect(map.waiting.map((o) => o.number), [13, 14]);
    expect(map.orders[1].needsGeocode, isTrue);
    expect(map.orders[2].needsGeocode, isFalse);
    expect(map.orders[2].notFound, isTrue);
    expect(map.ordersOf('m1').single.number, 12);
  });

  test('kafelki: Google z sesją albo OpenStreetMap', () {
    expect(const MapTiles.osm().google, isFalse);
    expect(const MapTiles.osm().urlTemplate, contains('openstreetmap'));
    final g = MapTiles.fromJson({'provider': 'google', 'session': 's', 'key': 'k', 'expiry': '4102444800'});
    expect(g.google, isTrue);
    expect(g.urlTemplate, 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=s&key=k');
    expect(g.expired(DateTime(2026, 10, 9)), isFalse);
    expect(g.expired(DateTime(2101, 1, 1)), isTrue);
  });
}
