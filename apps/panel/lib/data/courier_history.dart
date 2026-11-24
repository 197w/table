import 'package:latlong2/latlong.dart';

import 'delivery_map.dart' show MapTrip;

/// Historia tras dostawców (24.11.2026, prośba użytkownika: „historia tras, które wykonał dany kierowca … żeby
/// sprawdzić np. czy dany kierowca nie pojechał naokoło”). Baza daje punkty z telefonu dostawcy na zmianie
/// (`courier_track_points`, 0097) i jego dostawy z dnia lokalu, a kursy, przejechane kilometry, postoje
/// i porównanie z najkrótszą trasą z Mapbox liczy panel.

double? _d(Object? v) => v is num ? v.toDouble() : null;
int? _i(Object? v) => v is num ? v.toInt() : null;
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

const _earth = DistanceHaversine(roundResult: false);

/// Odległość w metrach.
double metersBetween(LatLng a, LatLng b) => _earth.distance(a, b);

/// Dostawca z trasą z telefonu albo dostawami w danym dniu lokalu (`panel_courier_days`).
class CourierDay {
  const CourierDay({
    required this.memberId,
    required this.name,
    this.color = 0,
    this.points = 0,
    this.deliveries = 0,
  });

  final String memberId;
  final String name;
  final int color;

  /// Punkty trasy z telefonu w tym dniu.
  final int points;
  final int deliveries;

  factory CourierDay.fromJson(Map<String, dynamic> j) => CourierDay(
    memberId: j['member_id'] as String,
    name: j['name'] as String? ?? '',
    color: _i(j['color']) ?? 0,
    points: _i(j['points']) ?? 0,
    deliveries: _i(j['deliveries']) ?? 0,
  );
}

/// Punkt trasy z telefonu.
class TrackPoint {
  const TrackPoint(this.at, this.point, {this.speed});

  final DateTime at;
  final LatLng point;

  /// Prędkość w m/s, gdy telefon ją podał.
  final double? speed;
}

/// Dostawa dostawcy w tym dniu.
class TrackOrder {
  const TrackOrder({
    required this.id,
    required this.number,
    this.courseId,
    this.stage = 'delivered',
    this.address,
    this.customer,
    this.pickedUpAt,
    this.deliveredAt,
    this.promisedAt,
    this.openedAt,
  });

  final String id;
  final int number;
  final String? courseId;
  final String stage;
  final String? address;
  final String? customer;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime? promisedAt;
  final DateTime? openedAt;

  /// Kurs: wspólne `course_id` albo sama dostawa.
  String get courseKey => courseId ?? id;

  factory TrackOrder.fromJson(Map<String, dynamic> j) => TrackOrder(
    id: j['id'] as String,
    number: _i(j['number']) ?? 0,
    courseId: j['course_id'] as String?,
    stage: j['fulfillment'] as String? ?? 'delivered',
    address: j['address'] as String?,
    customer: j['customer'] as String?,
    pickedUpAt: _date(j['picked_up_at']),
    deliveredAt: _date(j['delivered_at']),
    promisedAt: _date(j['promised_at']),
    openedAt: _date(j['opened_at']),
  );
}

/// Trasa dostawcy w dniu lokalu: punkty z telefonu po kolei i jego dostawy (`panel_courier_history`).
class CourierTrack {
  const CourierTrack({required this.points, required this.orders});

  final List<TrackPoint> points;
  final List<TrackOrder> orders;

  static const empty = CourierTrack(points: [], orders: []);

  factory CourierTrack.fromJson(Map<String, dynamic> j) => CourierTrack(
    points: [
      for (final p in j['points'] as List? ?? const [])
        if (p is List && p.length >= 3 && _d(p[1]) != null && _d(p[2]) != null)
          TrackPoint(
            DateTime.fromMillisecondsSinceEpoch(_i(p[0]) ?? 0),
            LatLng(_d(p[1])!, _d(p[2])!),
            speed: p.length > 3 ? _d(p[3]) : null,
          ),
    ],
    orders: [for (final o in (j['orders'] as List? ?? const []).cast<Map<String, dynamic>>()) TrackOrder.fromJson(o)],
  );
}

/// Długość trasy w metrach (suma odcinków między kolejnymi punktami).
double trackMeters(List<TrackPoint> points) {
  var sum = 0.0;
  for (var i = 1; i < points.length; i++) {
    sum += metersBetween(points[i - 1].point, points[i].point);
  }
  return sum;
}

/// Punkty z chwil od [from] do [to] włącznie.
List<TrackPoint> trackBetween(List<TrackPoint> points, DateTime from, DateTime to) => [
  for (final p in points)
    if (!p.at.isBefore(from) && !p.at.isAfter(to)) p,
];

/// Punkt najbliższy chwili [at], najwyżej [within] od niej.
TrackPoint? pointNear(List<TrackPoint> points, DateTime at, {Duration within = const Duration(minutes: 5)}) {
  TrackPoint? best;
  var bestGap = within.inMilliseconds + 1;
  for (final p in points) {
    final gap = p.at.difference(at).inMilliseconds.abs();
    if (gap < bestGap) {
      best = p;
      bestGap = gap;
    }
  }
  return best;
}

/// Postój: dostawca stał w jednym miejscu (w promieniu kilkudziesięciu metrów) przez kilka minut.
class TrackStop {
  const TrackStop({required this.point, required this.from, required this.to});

  final LatLng point;
  final DateTime from;
  final DateTime to;

  Duration get duration => to.difference(from);
}

/// Postoje na trasie: co najmniej [minimum] w promieniu [radius] metrów. Telefon nie wysyła punktów, gdy dostawca
/// stoi (co 15 m ruchu), więc postój to też długa przerwa między dwoma bliskimi punktami. Miejsca z [skip] (lokal,
/// adresy dostaw) nie są postojami.
List<TrackStop> trackStops(
  List<TrackPoint> points, {
  double radius = 60,
  Duration minimum = const Duration(minutes: 4),
  List<LatLng> skip = const [],
  double skipRadius = 120,
}) {
  final stops = <TrackStop>[];
  var i = 0;
  while (i < points.length) {
    final anchor = points[i];
    var j = i + 1;
    while (j < points.length && metersBetween(anchor.point, points[j].point) <= radius) {
      j++;
    }
    final last = points[j - 1];
    if (last.at.difference(anchor.at) >= minimum) {
      if (!skip.any((s) => metersBetween(s, anchor.point) <= skipRadius)) {
        stops.add(TrackStop(point: anchor.point, from: anchor.at, to: last.at));
      }
      i = j;
    } else {
      i++;
    }
  }
  return stops;
}

/// Przerwy w danych: telefon nic nie wysłał przez co najmniej [minimum], a dostawca w tym czasie przejechał ponad
/// [moved] metrów (wyłączony telefon albo lokalizacja). Trasa w tym miejscu to prosta kreska, więc kilometry są
/// zaniżone.
int trackGaps(List<TrackPoint> points, {Duration minimum = const Duration(minutes: 3), double moved = 500}) {
  var gaps = 0;
  for (var i = 1; i < points.length; i++) {
    if (points[i].at.difference(points[i - 1].at) >= minimum &&
        metersBetween(points[i - 1].point, points[i].point) > moved) {
      gaps++;
    }
  }
  return gaps;
}

/// Odcinek dnia dostawcy: kurs (od odbioru w lokalu do ostatniego dowiezienia) albo powrót do lokalu.
class CourierRide {
  const CourierRide({
    required this.key,
    required this.orders,
    required this.from,
    required this.to,
    required this.points,
    this.back = false,
    this.finished = true,
  });

  /// Klucz kursu (`course_id` albo numer dostawy); powrót: „back:” i klucz kursu przed nim.
  final String key;

  /// Dostawy w kolejności dowiezienia (powrót: pusta).
  final List<TrackOrder> orders;
  final DateTime from;
  final DateTime to;

  /// Punkty z telefonu z czasu odcinka.
  final List<TrackPoint> points;

  /// Powrót do lokalu po kursie.
  final bool back;

  /// Wszystkie dostawy dowiezione (inaczej kurs trwał jeszcze przy ostatnim punkcie).
  final bool finished;

  Duration get duration => to.difference(from);
  double get meters => trackMeters(points);
  bool get hasTrack => points.length >= 2;
  int get gaps => trackGaps(points);

  /// Miejsce dowiezienia każdej dostawy: punkt z telefonu z chwili „Dostarczone” (najwyżej 5 min obok).
  List<LatLng?> dropPoints(List<TrackPoint> all) => [
    for (final o in orders) o.deliveredAt == null ? null : pointNear(all, o.deliveredAt!)?.point,
  ];
}

/// Kursy i powroty dostawcy w kolejności dnia. Kurs bez odbioru („Odebrałem”) się nie liczy. Kurs w drodze trwa do
/// ostatniego punktu z telefonu (albo [now]). Powrót: od ostatniego dowiezienia do pierwszego punktu przy lokalu
/// ([restaurant], 150 m), najpóźniej do odbioru następnego kursu; bez położenia lokalu powrotów nie ma.
List<CourierRide> courierRides(CourierTrack track, {LatLng? restaurant, DateTime? now}) {
  final groups = <String, List<TrackOrder>>{};
  for (final o in track.orders) {
    if (o.pickedUpAt == null) continue;
    groups.putIfAbsent(o.courseKey, () => []).add(o);
  }
  final lastPoint = track.points.isEmpty ? null : track.points.last.at;
  final rides = <CourierRide>[];
  for (final e in groups.entries) {
    final orders = [...e.value]
      ..sort((a, b) {
        final da = a.deliveredAt;
        final db = b.deliveredAt;
        if (da == null || db == null) return da == null ? (db == null ? 0 : 1) : -1;
        return da.compareTo(db);
      });
    final from = orders.map((o) => o.pickedUpAt!).reduce((a, b) => a.isBefore(b) ? a : b);
    final finished = orders.every((o) => o.deliveredAt != null);
    var to = finished
        ? orders.map((o) => o.deliveredAt!).reduce((a, b) => a.isAfter(b) ? a : b)
        : (lastPoint != null && lastPoint.isAfter(from) ? lastPoint : (now ?? DateTime.now()));
    if (to.isBefore(from)) to = from;
    rides.add(
      CourierRide(
        key: e.key,
        orders: orders,
        from: from,
        to: to,
        points: trackBetween(track.points, from, to),
        finished: finished,
      ),
    );
  }
  rides.sort((a, b) => a.from.compareTo(b.from));
  if (restaurant == null) return rides;

  final result = <CourierRide>[];
  for (var i = 0; i < rides.length; i++) {
    final ride = rides[i];
    result.add(ride);
    if (!ride.finished) continue;
    final until = i + 1 < rides.length ? rides[i + 1].from : lastPoint;
    if (until == null || !until.isAfter(ride.to)) continue;
    final after = trackBetween(track.points, ride.to, until);
    final home = after.indexWhere((p) => metersBetween(p.point, restaurant) <= 150);
    // Bez dojazdu do lokalu (koniec zmiany gdzie indziej) powrotu nie sprawdzamy.
    if (home <= 0) continue;
    final points = after.sublist(0, home + 1);
    result.add(
      CourierRide(key: 'back:${ride.key}', orders: const [], from: ride.to, to: points.last.at, points: points, back: true),
    );
  }
  return result;
}

/// Ocena odcinka: przejechane kilometry wobec najkrótszej trasy przez te same miejsca.
class RideCheck {
  const RideCheck({required this.driven, required this.planned, this.otherOrder = false});

  /// Przejechane metry (z telefonu).
  final double driven;

  /// Najkrótsza trasa w metrach (Mapbox, najszybsza kolejność przystanków).
  final double planned;

  /// Dostawca rozwiózł adresy w innej kolejności niż najszybsza.
  final bool otherOrder;

  double get extra => driven - planned;

  /// O ile procent dłużej niż najkrótsza trasa.
  int get extraPercent => planned <= 0 ? 0 : ((driven / planned - 1) * 100).round();

  /// Objazd: ponad 30% i ponad 1 km dłużej niż najkrótsza trasa.
  bool get detour => planned > 0 && driven > planned * 1.3 && extra > 1000;
}

/// Ocena odcinka z trasą z Mapbox. Null, gdy brak trasy z telefonu albo z Mapbox.
RideCheck? checkRide(CourierRide ride, MapTrip? trip) {
  if (trip == null || !ride.hasTrack || trip.meters <= 0) return null;
  final order = trip.order;
  var other = false;
  for (var i = 0; i < order.length; i++) {
    if (order[i] != i) other = true;
  }
  return RideCheck(driven: ride.meters, planned: trip.meters, otherOrder: other && !ride.back);
}

/// Podsumowanie dnia dostawcy: przejechane metry, czas w kursach, liczba kursów.
({double meters, Duration riding, int courses}) daySummary(List<CourierRide> rides, List<TrackPoint> points) {
  var riding = Duration.zero;
  var courses = 0;
  for (final r in rides) {
    if (r.back) continue;
    courses++;
    riding += r.duration;
  }
  return (meters: trackMeters(points), riding: riding, courses: courses);
}
