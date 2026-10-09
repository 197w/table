import 'package:latlong2/latlong.dart';

double? _d(Object? v) => v is num ? v.toDouble() : null;
int? _i(Object? v) => v is num ? v.toInt() : null;
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
LatLng? _point(Object? lat, Object? lng) {
  final a = _d(lat);
  final b = _d(lng);
  return a == null || b == null ? null : LatLng(a, b);
}

/// Dostawca na zmianie na mapie: stan w kolejce i ostatnia pozycja z telefonu.
class MapCourier {
  const MapCourier({
    required this.memberId,
    required this.name,
    required this.busy,
    required this.located,
    this.color = 0,
    this.vehicle,
    this.position,
    this.accuracy,
    this.heading,
    this.updatedAt,
  });

  final String memberId;
  final String name;

  /// Ma kurs (przyjęty, gotowy albo w drodze).
  final bool busy;

  /// Widać go na mapie (świeża pozycja) albo lokal nie wymaga lokalizacji: może dostać kurs.
  final bool located;
  final int color;

  /// Pojazd przypisany we Flocie: car, scooter, bike, other.
  final String? vehicle;
  final LatLng? position;
  final double? accuracy;
  final double? heading;
  final DateTime? updatedAt;

  /// Pozycja sprzed ponad 3 minut: telefon przestał ją wysyłać.
  bool stale(DateTime now) => updatedAt == null || now.difference(updatedAt!) > const Duration(minutes: 3);

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
    located: j['located'] == true,
    color: _i(j['color']) ?? 0,
    vehicle: j['vehicle'] as String?,
    position: _point(j['lat'], j['lng']),
    accuracy: _d(j['accuracy']),
    heading: _d(j['heading']),
    updatedAt: _date(j['updated_at']),
  );
}

/// Dostawa w toku: cel na mapie i etap.
class MapOrder {
  const MapOrder({
    required this.id,
    required this.number,
    required this.stage,
    this.courierId,
    this.courseId,
    this.address,
    this.customerName,
    this.target,
    this.geo,
    this.promisedAt,
    this.scheduledFor,
    this.kitchenAt,
  });

  final String id;
  final int number;

  /// accepted, ready albo on_the_way.
  final String stage;
  final String? courierId;
  final String? courseId;
  final String? address;
  final String? customerName;
  final LatLng? target;

  /// Skąd współrzędne: google, osm, none (adresu nie znaleziono), null (jeszcze nie szukano).
  final String? geo;
  final DateTime? promisedAt;
  final DateTime? scheduledFor;

  /// Zamówienie na godzinę czeka na swoją porę w kuchni.
  final DateTime? kitchenAt;

  bool get onTheWay => stage == 'on_the_way';
  bool get needsGeocode => target == null && geo == null && (address ?? '').trim().isNotEmpty;
  bool get notFound => geo == 'none';

  factory MapOrder.fromJson(Map<String, dynamic> j) => MapOrder(
    id: j['id'] as String,
    number: _i(j['number']) ?? 0,
    stage: j['fulfillment'] as String? ?? 'accepted',
    courierId: j['courier_member'] as String?,
    courseId: j['course_id'] as String?,
    address: j['address'] as String?,
    customerName: j['customer_name'] as String?,
    target: _point(j['lat'], j['lng']),
    geo: j['geo'] as String?,
    promisedAt: _date(j['promised_at']),
    scheduledFor: _date(j['scheduled_for']),
    kitchenAt: _date(j['kitchen_at']),
  );
}

/// Trasa dostawcy do celu (z Google albo, bez klucza, z OSRM).
class MapRoute {
  const MapRoute({
    required this.memberId,
    required this.orderId,
    required this.points,
    required this.provider,
    required this.computedAt,
    this.durationS,
    this.distanceM,
  });

  final String memberId;
  final String orderId;
  final List<LatLng> points;
  final String provider;
  final DateTime computedAt;
  final int? durationS;
  final int? distanceM;

  /// Przewidywany przyjazd: chwila wyliczenia trasy plus czas jazdy.
  DateTime? get arrival => durationS == null ? null : computedAt.add(Duration(seconds: durationS!));

  factory MapRoute.fromJson(Map<String, dynamic> j) => MapRoute(
    memberId: j['member_id'] as String,
    orderId: j['order_id'] as String,
    points: decodePolyline(j['polyline'] as String? ?? ''),
    provider: j['provider'] as String? ?? 'osm',
    computedAt: _date(j['computed_at']) ?? DateTime.now(),
    durationS: _i(j['duration_s']),
    distanceM: _i(j['distance_m']),
  );
}

/// Wszystko dla mapy dostawców (`panel_courier_map`).
class CourierMap {
  const CourierMap({
    required this.tracking,
    required this.restaurantName,
    required this.couriers,
    required this.orders,
    required this.routes,
    this.restaurantAddress,
    this.restaurant,
  });

  /// Lokal wymaga lokalizacji dostawców przez całą zmianę.
  final bool tracking;
  final String restaurantName;
  final String? restaurantAddress;
  final LatLng? restaurant;
  final List<MapCourier> couriers;
  final List<MapOrder> orders;
  final List<MapRoute> routes;

  MapCourier? courier(String? memberId) => couriers.where((c) => c.memberId == memberId).firstOrNull;

  MapRoute? routeFor(MapOrder order) =>
      routes.where((r) => r.orderId == order.id && r.memberId == order.courierId).firstOrNull;

  /// Kursy dostawcy: najpierw te w drodze.
  List<MapOrder> ordersOf(String memberId) =>
      orders.where((o) => o.courierId == memberId).toList()
        ..sort((a, b) => (b.onTheWay ? 1 : 0) - (a.onTheWay ? 1 : 0));

  /// Zamówienia przyjęte, które jeszcze czekają na wolnego dostawcę.
  List<MapOrder> get waiting => orders.where((o) => o.courierId == null).toList();

  factory CourierMap.fromJson(Map<String, dynamic> j) {
    final r = j['restaurant'] as Map<String, dynamic>? ?? const {};
    List<Map<String, dynamic>> list(String key) => (j[key] as List? ?? const []).cast<Map<String, dynamic>>();
    return CourierMap(
      tracking: j['tracking'] == true,
      restaurantName: r['name'] as String? ?? '',
      restaurantAddress: r['address'] as String?,
      restaurant: _point(r['lat'], r['lng']),
      couriers: [for (final c in list('couriers')) MapCourier.fromJson(c)],
      orders: [for (final o in list('orders')) MapOrder.fromJson(o)],
      routes: [for (final x in list('routes')) MapRoute.fromJson(x)],
    );
  }
}

/// Linia trasy z zapisu „encoded polyline” (dokładność 5 miejsc), tego samego u Google i w OSRM.
List<LatLng> decodePolyline(String encoded) {
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
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}
