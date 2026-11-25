import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Wymuszona lokalizacja dostawcy (24.11.2026, prośba użytkownika): na zmianie dostawcy (stanowisko z uprawnieniem
// „deliveries”) aplikacja wysyła lokalowi pozycję telefonu, także w tle (gdy dostawca jest w nawigacji), a bez
// zgody na lokalizację zakładka „Dostawy” nie pokazuje kursów. Lokal widzi pozycję na mapie dostawców i historię
// tras w panelu (0097). Poza zmianą nic się nie wysyła.

/// Czy telefon pozwala aplikacji czytać pozycję.
enum LocationGate {
  /// Lokalizacja włączona i aplikacja ma zgodę.
  ready,

  /// Usługi lokalizacji w telefonie są wyłączone.
  serviceOff,

  /// Aplikacja nie ma jeszcze zgody (można zapytać).
  denied,

  /// Zgoda odrzucona na stałe: zmienia się ją w ustawieniach telefonu.
  deniedForever,

  /// Urządzenie bez lokalizacji z telefonu (komputer, testy): nic nie wymuszamy.
  unsupported,
}

bool get _mobile =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Zgoda na lokalizację na iPhonie wprost z CoreLocation (`AppDelegate.swift`, `LocationPermissionChannel`;
/// 25.11.2026: przez wtyczkę geolocator „Zezwól na lokalizację” nie pokazywało systemowego pytania).
const _iosLocation = MethodChannel('pl.table.staff/location');

bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Stan z CoreLocation: notDetermined, restricted, denied, whenInUse, always.
LocationGate iosLocationGate(String? status) => switch (status) {
  'whenInUse' || 'always' => LocationGate.ready,
  'denied' || 'restricted' => LocationGate.deniedForever,
  _ => LocationGate.denied,
};

/// Stan zgody na lokalizację teraz.
Future<LocationGate> checkLocationGate() async {
  if (!_mobile) return LocationGate.unsupported;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationGate.serviceOff;
    if (_ios) {
      try {
        return iosLocationGate(await _iosLocation.invokeMethod<String>('status'));
      } on MissingPluginException {
        // Wersja aplikacji bez kanału: jak dotąd przez geolocator.
      }
    }
    return switch (await Geolocator.checkPermission()) {
      LocationPermission.always || LocationPermission.whileInUse => LocationGate.ready,
      LocationPermission.deniedForever => LocationGate.deniedForever,
      _ => LocationGate.denied,
    };
  } on Object {
    return LocationGate.denied;
  }
}

/// Prosi o zgodę (systemowe pytanie) albo otwiera ustawienia telefonu, gdy zapytać już się nie da. Zwraca stan po
/// próbie. Błąd (np. brak wtyczki) idzie dalej, żeby ekran mógł go pokazać.
Future<LocationGate> requestLocationGate() async {
  final gate = await checkLocationGate();
  switch (gate) {
    case LocationGate.serviceOff:
      await Geolocator.openLocationSettings();
    case LocationGate.deniedForever:
      await Geolocator.openAppSettings();
    case LocationGate.denied:
      if (_ios) {
        try {
          final status = await _iosLocation.invokeMethod<String>('request');
          if (iosLocationGate(status) == LocationGate.deniedForever) await Geolocator.openAppSettings();
          return await checkLocationGate();
        } on MissingPluginException {
          // Wersja aplikacji bez kanału: niżej przez geolocator.
        }
      }
      await Geolocator.requestPermission();
    case LocationGate.ready || LocationGate.unsupported:
      break;
  }
  return checkLocationGate();
}

/// Zgoda na lokalizację; odświeżana po powrocie do aplikacji (`ref.invalidate`).
final locationGateProvider = FutureProvider<LocationGate>((ref) => checkLocationGate());

/// Co dzieje się z wysyłaniem pozycji: czy działa, kiedy ostatnio doszła do lokalu i ile punktów czeka na internet.
@immutable
class TrackingStatus {
  const TrackingStatus({this.active = false, this.lastSentAt, this.pending = 0});

  final bool active;
  final DateTime? lastSentAt;
  final int pending;
}

/// Punkt trasy do wysłania (jak w `staff_share_locations`).
Map<String, dynamic> trackPoint(Position p) => {
  'lat': p.latitude,
  'lng': p.longitude,
  'at': p.timestamp.toUtc().toIso8601String(),
  'accuracy': p.accuracy,
  if (p.speed >= 0) 'speed': p.speed,
  if (p.heading >= 0) 'heading': p.heading,
};

/// Ustawienia odczytu pozycji: dokładnie, co ok. 15 m. Android z powiadomieniem stałej usługi (wtedy pozycja idzie też
/// w tle), iOS z niebieskim wskaźnikiem i bez automatycznego wstrzymywania.
LocationSettings courierLocationSettings() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
      intervalDuration: const Duration(seconds: 10),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Zmiana dostawcy',
        notificationText: 'Lokal widzi Twoją pozycję i trasę do końca zmiany.',
        notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.best,
      activityType: ActivityType.automotiveNavigation,
      distanceFilter: 15,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
    );
  }
  return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15);
}

/// Wysyła pozycję dostawcy na zmianie: zbiera punkty ze strumienia i co [flushEvery] (albo po [batch] punktach)
/// odsyła je paczką. Bez internetu punkty czekają (najwyżej [maxPending], najstarsze wypadają) i idą przy następnej
/// próbie.
class CourierLocationService {
  CourierLocationService({
    required this.send,
    Stream<Position> Function()? positions,
    this.flushEvery = const Duration(seconds: 20),
    this.batch = 15,
    this.maxPending = 2000,
  }) : _positions = positions ?? (() => Geolocator.getPositionStream(locationSettings: courierLocationSettings()));

  /// Wysyła punkty pracownika; zwraca, ile baza zapisała.
  final Future<int> Function(String memberId, List<Map<String, dynamic>> points) send;
  final Stream<Position> Function() _positions;
  final Duration flushEvery;
  final int batch;
  final int maxPending;

  final status = ValueNotifier(const TrackingStatus());

  String? _memberId;
  StreamSubscription<Position>? _sub;
  Timer? _timer;
  final _pending = <Map<String, dynamic>>[];
  bool _sending = false;

  String? get memberId => _memberId;

  /// Dostawca na zmianie ([memberId]) albo nikt (null): uruchamia, przełącza albo zatrzymuje wysyłanie.
  void update(String? memberId) {
    if (memberId == _memberId) return;
    _stop();
    if (memberId != null) _start(memberId);
  }

  void _start(String memberId) {
    _memberId = memberId;
    _sub = _positions().listen(_add, onError: (Object _) {});
    _timer = Timer.periodic(flushEvery, (_) => unawaited(flush()));
    status.value = TrackingStatus(active: true, lastSentAt: status.value.lastSentAt, pending: _pending.length);
  }

  void _stop() {
    final member = _memberId;
    unawaited(_sub?.cancel());
    _sub = null;
    _timer?.cancel();
    _timer = null;
    // Ostatnie punkty zmiany jeszcze do lokalu.
    if (member != null && _pending.isNotEmpty) unawaited(_flushFor(member));
    _memberId = null;
    status.value = TrackingStatus(lastSentAt: status.value.lastSentAt, pending: _pending.length);
  }

  void _add(Position p) {
    _pending.add(trackPoint(p));
    if (_pending.length > maxPending) _pending.removeRange(0, _pending.length - maxPending);
    status.value = TrackingStatus(active: true, lastSentAt: status.value.lastSentAt, pending: _pending.length);
    if (_pending.length >= batch) unawaited(flush());
  }

  /// Wysyła zebrane punkty teraz.
  Future<void> flush() async {
    final member = _memberId;
    if (member != null) await _flushFor(member);
  }

  Future<void> _flushFor(String member) async {
    if (_sending || _pending.isEmpty) return;
    _sending = true;
    final chunk = List.of(_pending.take(500));
    try {
      await send(member, chunk);
      _pending.removeRange(0, chunk.length);
      status.value = TrackingStatus(active: _memberId != null, lastSentAt: DateTime.now(), pending: _pending.length);
    } on Object {
      // Bez internetu: punkty zostają do następnej próby.
    } finally {
      _sending = false;
    }
  }

  void dispose() {
    _stop();
    status.dispose();
  }
}

/// Usługa wysyłania pozycji, jedna na całą aplikację.
final courierLocationProvider = Provider<CourierLocationService>((ref) {
  final db = Supabase.instance.client;
  final service = CourierLocationService(
    send: (memberId, points) async =>
        await db.rpc<int>('staff_share_locations', params: {'p_member_id': memberId, 'p_points': points}),
  );
  ref.onDispose(service.dispose);
  return service;
});
