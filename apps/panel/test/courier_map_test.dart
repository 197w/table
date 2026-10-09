import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/courier_map.dart';
import 'package:table_panel/features/deliveries/map_style.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

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

  test('mapa Table: tylko to, czego potrzebuje dostawca', () {
    for (final dark in [true, false]) {
      final style = tableMapStyle(dark: dark);
      final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
      final sourceLayers = {for (final l in layers) l['source-layer']};
      // Bez punktów usług, placów zabaw (landuse), przystanków, granic i lotnisk.
      for (final hidden in ['poi', 'landuse', 'boundary', 'aeroway', 'aerodrome_label', 'mountain_peak']) {
        expect(sourceLayers.contains(hidden), isFalse, reason: hidden);
      }
      // Drogi tylko dla aut i skuterów: bez ścieżek (w tym rowerowych), torów i promów.
      final roads = layers.where((l) => l['source-layer'] == 'transportation').toList();
      expect(roads, isNotEmpty);
      for (final r in roads) {
        final text = r['filter'].toString();
        for (final hidden in ['path', 'track', 'rail', 'ferry', 'cycleway']) {
          expect(text.contains(hidden), isFalse, reason: '${r['id']}: $hidden');
        }
      }
      expect(sourceLayers, containsAll(['housenumber', 'transportation_name', 'building', 'water']));
      // Styl czyta się bez błędów i używa jednego źródła kafelków.
      final theme = vtr.ThemeReader().read(style);
      expect(theme.tileSources, {mapTileSource});
    }
  });
}
