import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:table_staff/courier_location.dart';
import 'package:table_staff/deliveries_data.dart';

Course _course(String id, int number, String address, {String stage = 'ready', DateTime? promised}) => Course.fromJson({
  'id': id,
  'number': number,
  'fulfillment': stage,
  'delivery_address': address,
  'total_grosze': 1000,
  'promised_at': promised?.toUtc().toIso8601String(),
});

Position _position(double lat, double lng, DateTime at, {double accuracy = 8, double speed = 10}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: at,
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 90,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: 0,
);

void main() {
  group('trasa w domyślnej nawigacji', () {
    test('jeden adres: Apple Maps na iPhonie, geo: na Androidzie', () {
      final ios = routeUri(['Lipowa 14/3, Białystok'], ios: true)!;
      expect(ios.host, 'maps.apple.com');
      expect(ios.queryParameters['daddr'], 'Lipowa 14/3, Białystok');
      expect(ios.queryParameters['dirflg'], 'd');

      final android = routeUri(['Lipowa 14/3, Białystok'], ios: false)!;
      expect(android.scheme, 'geo');
      expect(android.toString(), 'geo:0,0?q=Lipowa%2014%2F3%2C%20Bia%C5%82ystok');
    });

    test('kilka adresów: przystanki po kolei, ostatni to cel', () {
      final stops = ['Lipowa 1, Białystok', 'Sienkiewicza 5, Białystok', 'Wiejska 3, Białystok'];
      final ios = routeUri(stops, ios: true)!;
      expect(ios.path, '/directions');
      expect(ios.queryParameters['destination'], 'Wiejska 3, Białystok');
      expect(ios.queryParametersAll['waypoint'], ['Lipowa 1, Białystok', 'Sienkiewicza 5, Białystok']);
      expect(ios.queryParameters['mode'], 'driving');

      final android = routeUri(stops, ios: false)!;
      expect(android.host, 'www.google.com');
      expect(android.queryParameters['destination'], 'Wiejska 3, Białystok');
      expect(android.queryParameters['waypoints'], 'Lipowa 1, Białystok|Sienkiewicza 5, Białystok');
      expect(android.queryParameters['travelmode'], 'driving');
    });

    test('puste i powtórzone adresy są pomijane', () {
      expect(routeUri(const [], ios: true), isNull);
      expect(routeUri(const ['  '], ios: false), isNull);
      // Dwie dostawy pod ten sam adres to jeden cel.
      expect(routeUri(const ['Lipowa 1', 'Lipowa 1'], ios: false)!.scheme, 'geo');
    });

    test('kolejność przystanków: najpierw w drodze, potem według obiecanej godziny', () {
      final early = DateTime(2026, 11, 24, 18, 30);
      final late = DateTime(2026, 11, 24, 19, 0);
      final a = _course('a', 12, 'A', promised: late);
      final b = _course('b', 11, 'B', promised: early);
      final c = _course('c', 13, 'C');
      expect(routeStops([a, b, c]).map((x) => x.number), [11, 12, 13]);
      // Gdy któraś dostawa jest w drodze, trasa idzie tylko przez dostawy w drodze.
      final d = _course('d', 14, 'D', stage: 'on_the_way', promised: late);
      final e = _course('e', 15, 'E', stage: 'on_the_way', promised: early);
      expect(routeStops([a, d, b, e]).map((x) => x.number), [15, 14]);
    });
  });

  group('wysyłanie pozycji dostawcy', () {
    test('punkty idą paczką, bez internetu czekają, koniec zmiany zatrzymuje wysyłanie', () async {
      final controller = StreamController<Position>.broadcast();
      final sent = <(String, List<Map<String, dynamic>>)>[];
      var online = false;
      final service = CourierLocationService(
        send: (member, points) async {
          if (!online) throw Exception('brak internetu');
          sent.add((member, points));
          return points.length;
        },
        positions: () => controller.stream,
        flushEvery: const Duration(hours: 1),
        batch: 3,
      );
      addTearDown(service.dispose);

      service.update('m1');
      expect(service.status.value.active, isTrue);
      final t = DateTime.utc(2026, 11, 24, 18);
      controller.add(_position(53.13, 23.16, t));
      controller.add(_position(53.14, 23.17, t.add(const Duration(seconds: 10)), speed: -1));
      await Future<void>.delayed(Duration.zero);
      expect(service.status.value.pending, 2);
      expect(sent, isEmpty);

      // Trzeci punkt: paczka, ale bez internetu punkty zostają.
      controller.add(_position(53.15, 23.18, t.add(const Duration(seconds: 20))));
      await Future<void>.delayed(Duration.zero);
      expect(sent, isEmpty);
      expect(service.status.value.pending, 3);

      online = true;
      await service.flush();
      expect(sent.single.$1, 'm1');
      expect(sent.single.$2.length, 3);
      expect(sent.single.$2.first['lat'], 53.13);
      expect(sent.single.$2.first['at'], '2026-11-24T18:00:00.000Z');
      // Prędkość nieznana (−1) nie jest wysyłana.
      expect(sent.single.$2[1].containsKey('speed'), isFalse);
      expect(service.status.value.pending, 0);
      expect(service.status.value.lastSentAt, isNotNull);

      // Koniec zmiany: wysyłanie stoi, nowe punkty nie są zbierane.
      service.update(null);
      expect(service.status.value.active, isFalse);
      expect(service.memberId, isNull);
      controller.add(_position(53.16, 23.19, t.add(const Duration(seconds: 30))));
      await Future<void>.delayed(Duration.zero);
      expect(service.status.value.pending, 0);
      await controller.close();
    });
  });
}
