import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Mapa dostawców (14.11.2026, prośba użytkownika: stary projekt „Mapa” z mapą Mapbox). Dane z bazy
/// (`panel_delivery_map`), a adresy, trasy, czasy i kolejność przystanków z Mapbox (klucz w env.json).

double? _d(Object? v) => v is num ? v.toDouble() : null;
int? _i(Object? v) => v is num ? v.toInt() : null;
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
LatLng? _point(Object? lat, Object? lng) {
  final a = _d(lat);
  final b = _d(lng);
  return a == null || b == null ? null : LatLng(a, b);
}

/// Dostawca na zmianie: stan w kolejce, auto na dziś i ostatnia pozycja z telefonu (gdy telefon ją wysyła).
class MapCourier {
  const MapCourier({
    required this.memberId,
    required this.name,
    required this.busy,
    this.ready = true,
    this.color = 0,
    this.vehicle,
    this.vehicleName,
    this.position,
    this.heading,
    this.updatedAt,
  });

  final String memberId;
  final String name;

  /// Ma kurs (przyjęty, gotowy albo w drodze).
  final bool busy;

  /// Może dostać kurs (zrobił kontrolę auta, gdy lokal jej wymaga).
  final bool ready;
  final int color;

  /// Auto na dziś z Floty: car, scooter, bike, other.
  final String? vehicle;
  final String? vehicleName;
  final LatLng? position;
  final double? heading;
  final DateTime? updatedAt;

  String get initials {
    String head(String s, int n) => String.fromCharCodes(s.runes.take(n));
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return head(parts.first, 2).toUpperCase();
    return (head(parts.first, 1) + head(parts.last, 1)).toUpperCase();
  }

  factory MapCourier.fromJson(Map<String, dynamic> j) => MapCourier(
    memberId: j['member_id'] as String,
    name: j['name'] as String? ?? '',
    busy: j['busy'] == true,
    ready: j['ready'] != false,
    color: _i(j['color']) ?? 0,
    vehicle: j['vehicle'] as String?,
    vehicleName: j['vehicle_name'] as String?,
    position: _point(j['lat'], j['lng']),
    heading: _d(j['heading']),
    updatedAt: _date(j['updated_at']),
  );
}

/// Dostawa w toku.
class MapOrder {
  const MapOrder({
    required this.id,
    required this.number,
    required this.stage,
    this.courierId,
    this.courseId,
    this.address,
    this.addressNote,
    this.customerName,
    this.promisedAt,
    this.scheduledFor,
    this.kitchenAt,
    this.pickedUpAt,
    this.readyAt,
  });

  final String id;
  final int number;

  /// accepted, ready albo on_the_way.
  final String stage;
  final String? courierId;
  final String? courseId;
  final String? address;
  final String? addressNote;
  final String? customerName;
  final DateTime? promisedAt;
  final DateTime? scheduledFor;

  /// Zamówienie na godzinę czeka na swoją porę w kuchni.
  final DateTime? kitchenAt;
  final DateTime? pickedUpAt;
  final DateTime? readyAt;

  bool get onTheWay => stage == 'on_the_way';
  bool get ready => stage == 'ready';

  /// Zamówienie na godzinę, które jeszcze nie weszło do kuchni.
  bool waitingForKitchen(DateTime now) => kitchenAt != null && kitchenAt!.isAfter(now);

  factory MapOrder.fromJson(Map<String, dynamic> j) => MapOrder(
    id: j['id'] as String,
    number: _i(j['number']) ?? 0,
    stage: j['fulfillment'] as String? ?? 'accepted',
    courierId: j['courier_member'] as String?,
    courseId: j['course_id'] as String?,
    address: j['address'] as String?,
    addressNote: j['address_note'] as String?,
    customerName: j['customer_name'] as String?,
    promisedAt: _date(j['promised_at']),
    scheduledFor: _date(j['scheduled_for']),
    kitchenAt: _date(j['kitchen_at']),
    pickedUpAt: _date(j['picked_up_at']),
    readyAt: _date(j['ready_at']),
  );
}

/// Kurs: dostawy połączone w jeden kurs (to samo `course_id`) albo pojedyncza dostawa.
class MapCourse {
  const MapCourse({required this.key, required this.orders});

  /// `course_id` albo numer pojedynczej dostawy.
  final String key;
  final List<MapOrder> orders;

  String? get courierId => orders.map((o) => o.courierId).nonNulls.firstOrNull;
  bool get onTheWay => orders.any((o) => o.onTheWay);
  bool get ready => !onTheWay && orders.every((o) => o.ready);

  /// Jeszcze w lokalu: można go połączyć z innym kursem.
  bool get atRestaurant => !onTheWay;
  DateTime? get pickedUpAt => orders.map((o) => o.pickedUpAt).nonNulls.firstOrNull;

  /// Najwcześniejsza obiecana godzina w kursie.
  DateTime? get promisedAt {
    final times = orders.map((o) => o.promisedAt).nonNulls.toList()..sort();
    return times.firstOrNull;
  }

  List<String> get orderIds => [for (final o in orders) o.id];
}

/// Wszystko dla mapy dostawców (`panel_delivery_map`).
class DeliveryMap {
  const DeliveryMap({
    required this.restaurantName,
    required this.couriers,
    required this.orders,
    this.restaurantAddress,
    this.restaurantCity,
    this.restaurant,
  });

  final String restaurantName;
  final String? restaurantAddress;
  final String? restaurantCity;
  final LatLng? restaurant;
  final List<MapCourier> couriers;
  final List<MapOrder> orders;

  MapCourier? courier(String? memberId) =>
      memberId == null ? null : couriers.where((c) => c.memberId == memberId).firstOrNull;

  /// Kursy: najpierw w drodze, potem według obiecanej godziny.
  List<MapCourse> get courses => groupCourses(orders);

  factory DeliveryMap.fromJson(Map<String, dynamic> j) {
    final r = j['restaurant'] as Map<String, dynamic>? ?? const {};
    List<Map<String, dynamic>> list(String key) => (j[key] as List? ?? const []).cast<Map<String, dynamic>>();
    return DeliveryMap(
      restaurantName: r['name'] as String? ?? '',
      restaurantAddress: r['address'] as String?,
      restaurantCity: r['city'] as String?,
      restaurant: _point(r['lat'], r['lng']),
      couriers: [for (final c in list('couriers')) MapCourier.fromJson(c)],
      orders: [for (final o in list('orders')) MapOrder.fromJson(o)],
    );
  }
}

/// Dostawy pogrupowane w kursy (wspólne `course_id`), w kolejności: w drodze, potem obiecana godzina.
List<MapCourse> groupCourses(List<MapOrder> orders) {
  final groups = <String, List<MapOrder>>{};
  for (final o in orders) {
    groups.putIfAbsent(o.courseId ?? o.id, () => []).add(o);
  }
  final courses = [for (final e in groups.entries) MapCourse(key: e.key, orders: e.value)];
  int byPromise(MapCourse a, MapCourse b) {
    final pa = a.promisedAt;
    final pb = b.promisedAt;
    if (pa == null || pb == null) return pa == null ? (pb == null ? 0 : 1) : -1;
    return pa.compareTo(pb);
  }

  courses.sort((a, b) {
    if (a.onTheWay != b.onTheWay) return a.onTheWay ? -1 : 1;
    return byPromise(a, b);
  });
  return courses;
}

// ---------------------------------------------------------------
// Trasy
// ---------------------------------------------------------------

/// Trasa kursu z Mapbox: kolejność przystanków (najszybsza), czas i długość każdego odcinka i linia na mapę.
class MapTrip {
  const MapTrip({required this.order, required this.legSeconds, required this.legMeters, required this.geometry});

  /// Kolejność przystanków: indeksy z listy celów podanej do wyliczenia.
  final List<int> order;

  /// Odcinki w kolejności jazdy: od startu do pierwszego przystanku, od pierwszego do drugiego…
  final List<double> legSeconds;
  final List<double> legMeters;
  final List<LatLng> geometry;

  double get seconds => legSeconds.fold(0.0, (a, b) => a + b);
  double get meters => legMeters.fold(0.0, (a, b) => a + b);

  /// Czas jazdy od startu do każdego przystanku po kolei (z [stop] postoju pod każdym poprzednim adresem).
  List<Duration> cumulative({Duration stop = const Duration(minutes: 2)}) {
    var total = 0.0;
    return [
      for (var i = 0; i < legSeconds.length; i++)
        Duration(seconds: (total += legSeconds[i] + (i > 0 ? stop.inSeconds : 0)).round()),
    ];
  }
}

/// Najszybsza kolejność przystanków z czasów jazdy (wiersz 0 = start, kolejne = przystanki): dla najwyżej 7
/// przystanków sprawdza wszystkie kolejności, dla większej liczby jedzie zawsze do najbliższego. Brak czasu między
/// punktami liczy się jak bardzo długa jazda. Zwraca indeksy przystanków (0 = pierwszy cel) w kolejności jazdy.
List<int> fastestOrder(List<List<double?>> seconds) {
  final n = seconds.length - 1;
  if (n <= 0) return const [];
  double cost(int from, int to) => seconds[from][to] ?? 1e9;
  if (n > 7) {
    final order = <int>[];
    final left = {for (var i = 1; i <= n; i++) i};
    var at = 0;
    while (left.isNotEmpty) {
      final next = left.reduce((a, b) => cost(at, a) <= cost(at, b) ? a : b);
      order.add(next - 1);
      left.remove(next);
      at = next;
    }
    return order;
  }
  var best = <int>[for (var i = 0; i < n; i++) i];
  var bestCost = double.infinity;
  void walk(List<int> path, Set<int> left, double sum) {
    if (sum >= bestCost) return;
    if (left.isEmpty) {
      bestCost = sum;
      best = List.of(path);
      return;
    }
    final at = path.isEmpty ? 0 : path.last + 1;
    for (final i in left.toList()) {
      path.add(i);
      left.remove(i);
      walk(path, left, sum + cost(at, i + 1));
      left.add(i);
      path.removeLast();
    }
  }

  walk([], {for (var i = 0; i < n; i++) i}, 0);
  return best;
}

/// Odpowiedź Directions API v5: przystanki w podanej kolejności ([order]: którymi celami po kolei jechała trasa).
MapTrip? parseDirections(Map<String, dynamic> json, int stops, {List<int>? order}) {
  if (json['code'] != 'Ok') return null;
  final route = (json['routes'] as List?)?.firstOrNull as Map<String, dynamic>?;
  if (route == null) return null;
  final legs = (route['legs'] as List? ?? const []).cast<Map<String, dynamic>>();
  return MapTrip(
    order: order ?? [for (var i = 0; i < stops; i++) i],
    legSeconds: [for (final l in legs) _d(l['duration']) ?? 0],
    legMeters: [for (final l in legs) _d(l['distance']) ?? 0],
    geometry: decodePolyline(route['geometry'] as String? ?? '', precision: 6),
  );
}

/// Linia trasy z zapisu „encoded polyline” (Mapbox: 6 miejsc po przecinku, `geometries=polyline6`).
List<LatLng> decodePolyline(String encoded, {int precision = 5}) {
  final factor = math.pow(10, precision).toDouble();
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;
  while (index < encoded.length) {
    for (var coordinate = 0; coordinate < 2; coordinate++) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        if (index >= encoded.length) return points;
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      if (coordinate == 0) {
        lat += delta;
      } else {
        lng += delta;
      }
    }
    points.add(LatLng(lat / factor, lng / factor));
  }
  return points;
}

// ---------------------------------------------------------------
// Propozycje kursów
// ---------------------------------------------------------------

/// Propozycja połączenia kursów, które czekają w lokalu i mają adresy blisko siebie.
class CourseSuggestion {
  const CourseSuggestion({required this.courses, required this.gapSeconds, this.extraSeconds});

  final List<MapCourse> courses;

  /// Jazda między najbliższymi adresami obu kursów.
  final double gapSeconds;

  /// O ile później dojedzie ostatni klient niż kursem osobno (dla dwóch pojedynczych dostaw).
  final double? extraSeconds;

  String get key => (courses.expand((c) => c.orderIds).toList()..sort()).join(',');
  List<String> get orderIds => [for (final c in courses) ...c.orderIds];
}

/// Propozycje łączenia kursów (14.11.2026: „automatycznie ma zaznaczać kursy”): kursy jeszcze w lokalu (bez
/// zamówień na godzinę przed porą kuchni), z adresami znalezionymi na mapie, najwyżej [maxStops] adresów razem,
/// adresy najwyżej [maxGap] jazdy od siebie, obiecane godziny najwyżej [maxPromiseGap] od siebie, a ostatni klient
/// czeka najwyżej [maxExtra] dłużej niż kursem osobno. [seconds] daje czas jazdy między punktami: `null` to lokal,
/// inaczej numer zamówienia; null, gdy nie wiadomo. Każdy kurs w najwyżej jednej propozycji, najbliższe pierwsze.
List<CourseSuggestion> suggestCourses({
  required List<MapCourse> courses,
  required double? Function(String? from, String? to) seconds,
  required DateTime now,
  Set<String> dismissed = const {},
  int maxStops = 4,
  Duration maxGap = const Duration(minutes: 7),
  Duration maxExtra = const Duration(minutes: 10),
  Duration maxPromiseGap = const Duration(minutes: 25),
}) {
  final open = [
    for (final c in courses)
      if (c.atRestaurant &&
          !c.orders.any((o) => o.waitingForKitchen(now)) &&
          c.orders.every((o) => seconds(null, o.id) != null))
        c,
  ];
  final candidates = <CourseSuggestion>[];
  for (var i = 0; i < open.length; i++) {
    for (var j = i + 1; j < open.length; j++) {
      final a = open[i];
      final b = open[j];
      if (a.orders.length + b.orders.length > maxStops) continue;
      final pa = a.promisedAt;
      final pb = b.promisedAt;
      if (pa != null && pb != null && pa.difference(pb).abs() > maxPromiseGap) continue;
      double? gap;
      for (final x in a.orders) {
        for (final y in b.orders) {
          final there = seconds(x.id, y.id);
          final back = seconds(y.id, x.id);
          for (final s in [there, back]) {
            if (s != null && (gap == null || s < gap)) gap = s;
          }
        }
      }
      if (gap == null || gap > maxGap.inSeconds) continue;
      double? extra;
      if (a.orders.length == 1 && b.orders.length == 1) {
        final x = a.orders.single.id;
        final y = b.orders.single.id;
        final rx = seconds(null, x)!;
        final ry = seconds(null, y)!;
        final viaX = seconds(x, y);
        final viaY = seconds(y, x);
        // Kolejność z krótszą całą jazdą; ostatni klient czeka dłużej o tyle, ile trwa objazd przez pierwszy adres.
        final options = [
          if (viaX != null) (total: rx + viaX, extra: rx + viaX - ry),
          if (viaY != null) (total: ry + viaY, extra: ry + viaY - rx),
        ]..sort((p, q) => p.total.compareTo(q.total));
        if (options.isEmpty) continue;
        extra = math.max(0, options.first.extra);
        if (extra > maxExtra.inSeconds) continue;
      }
      final suggestion = CourseSuggestion(courses: [a, b], gapSeconds: gap, extraSeconds: extra);
      if (dismissed.contains(suggestion.key)) continue;
      candidates.add(suggestion);
    }
  }
  candidates.sort((p, q) => p.gapSeconds.compareTo(q.gapSeconds));
  final used = <String>{};
  final result = <CourseSuggestion>[];
  for (final s in candidates) {
    if (s.courses.any((c) => used.contains(c.key))) continue;
    result.add(s);
    used.addAll(s.courses.map((c) => c.key));
  }
  return result;
}

// ---------------------------------------------------------------
// Mapbox
// ---------------------------------------------------------------

/// Zapytania do Mapbox z publicznym kluczem z env.json: adresy (Geocoding v6), najszybsza kolejność przystanków
/// (z czasów Matrix v1), trasa (Directions v5) i czasy jazdy między punktami (Matrix v1). Wyniki adresów trzymamy
/// tylko w pamięci na czas działania panelu (wyniki tymczasowe Mapbox nie mogą trafiać do bazy).
class MapboxClient {
  MapboxClient(this.token, {http.Client? client}) : _client = client ?? http.Client();

  final String token;
  final http.Client _client;
  final _geocoded = <String, LatLng?>{};

  static const _host = 'api.mapbox.com';

  bool get configured => token.isNotEmpty;

  /// Adres kafelków stylu (512 px, `{r}` = „@2x” na ekranach o dużej gęstości).
  String tileUrl(String style) => 'https://$_host/styles/v1/$style/tiles/512/{z}/{x}/{y}{r}?access_token=$token';

  static String _coords(List<LatLng> points) =>
      points.map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}').join(';');

  Future<Map<String, dynamic>?> _get(String path, Map<String, String> query) async {
    final uri = Uri.https(_host, path, {...query, 'access_token': token});
    final res = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  /// Położenie adresu dostawy w Polsce, najpierw blisko lokalu. Null: nie znaleziono. Bez miasta w adresie dopisuje
  /// miasto lokalu. Wynik zapamiętany do końca działania panelu (także „nie znaleziono”).
  Future<LatLng?> geocode(String address, {LatLng? near, String? city}) async {
    var q = address.trim();
    if (q.isEmpty) return null;
    if (city != null && city.trim().isNotEmpty && !q.toLowerCase().contains(city.trim().toLowerCase())) {
      q = '$q, ${city.trim()}';
    }
    final key = q.toLowerCase();
    if (_geocoded.containsKey(key)) return _geocoded[key];
    final json = await _get('/search/geocode/v6/forward', {
      'q': q,
      'country': 'pl',
      'language': 'pl',
      'limit': '1',
      'types': 'address,street',
      if (near != null) 'proximity': '${near.longitude},${near.latitude}',
    });
    if (json == null) throw const MapboxUnavailable();
    final feature = (json['features'] as List?)?.firstOrNull as Map<String, dynamic>?;
    final coords = (feature?['geometry'] as Map<String, dynamic>?)?['coordinates'] as List?;
    final point = coords == null || coords.length < 2 ? null : _point(coords[1], coords[0]);
    _geocoded[key] = point;
    return point;
  }

  /// Najszybsza trasa od [start] przez wszystkie [stops]: przy kilku celach kolejność z czasów jazdy z korkami
  /// (Matrix, `fastestOrder`; Optimization API Mapbox odpowiada na tym koncie „not supported”), potem trasa po kolei
  /// (Directions) z korkami (`driving-traffic`), a przy odmowie bez nich.
  Future<MapTrip?> trip(LatLng start, List<LatLng> stops) async {
    if (stops.isEmpty) return null;
    var order = [for (var i = 0; i < stops.length; i++) i];
    if (stops.length > 1) {
      final seconds = await matrix([start, ...stops]);
      if (seconds != null) order = fastestOrder(seconds);
    }
    final points = [start, for (final i in order) stops[i]];
    for (final profile in const ['driving-traffic', 'driving']) {
      final json = await _get('/directions/v5/mapbox/$profile/${_coords(points)}', {
        'geometries': 'polyline6',
        'overview': 'full',
      });
      final trip = json == null ? null : parseDirections(json, stops.length, order: order);
      if (trip != null) return trip;
    }
    return null;
  }

  /// Czasy jazdy w sekundach między wszystkimi punktami (wiersz = skąd, kolumna = dokąd). Z korkami do 10 punktów,
  /// bez korków do 25. Null: usługa nie odpowiedziała.
  Future<List<List<double?>>?> matrix(List<LatLng> points) async {
    if (points.length < 2 || points.length > 25) return null;
    final profile = points.length <= 10 ? 'driving-traffic' : 'driving';
    final json = await _get('/directions-matrix/v1/mapbox/$profile/${_coords(points)}', {'annotations': 'duration'});
    if (json == null || json['code'] != 'Ok') return null;
    return [
      for (final row in json['durations'] as List? ?? const []) [for (final v in row as List) _d(v)],
    ];
  }
}

/// Mapbox nie odpowiedział (brak internetu, zły klucz, limit): adres spróbujemy znaleźć później.
class MapboxUnavailable implements Exception {
  const MapboxUnavailable();
}
