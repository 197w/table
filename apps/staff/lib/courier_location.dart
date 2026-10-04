import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pozycja dostawcy dla gościa: gdy kurs jest w drodze, telefon wysyła położenie (co ~25 m, najwyżej co 15 s).
/// Na Androidzie działa też w tle (powiadomienie „Kurs w drodze”), na iPhonie z niebieskim wskaźnikiem.
class CourierTracker {
  CourierTracker(this._db);

  final SupabaseClient _db;
  StreamSubscription<Position>? _sub;
  Set<String> _orders = const {};
  String? _memberId;
  DateTime _lastSent = DateTime(2000);
  bool _starting = false;

  static const _minGap = Duration(seconds: 15);

  bool get active => _sub != null;

  /// Włącza albo wyłącza wysyłanie według kursów w drodze. Zwraca false, gdy brak zgody na lokalizację.
  Future<bool> update(String memberId, Iterable<String> onTheWay) async {
    _memberId = memberId;
    final orders = onTheWay.toSet();
    final added = orders.difference(_orders).isNotEmpty;
    _orders = orders;
    if (orders.isEmpty) {
      stop();
      return true;
    }
    if (_sub != null) {
      // Nowy kurs w drodze: pozycja od razu, bez czekania na ruch.
      if (added) _lastSent = DateTime(2000);
      return true;
    }
    if (_starting) return true;
    _starting = true;
    try {
      if (!await _permission()) return false;
      _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(_send, onError: (_) {});
      return true;
    } finally {
      _starting = false;
    }
  }

  Future<bool> _permission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      return p == LocationPermission.whileInUse || p == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  LocationSettings _settings() => switch (defaultTargetPlatform) {
    TargetPlatform.android => AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 25,
      intervalDuration: const Duration(seconds: 10),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Kurs w drodze',
        notificationText: 'Gość widzi na mapie, gdzie jest zamówienie.',
        setOngoing: true,
      ),
    ),
    TargetPlatform.iOS => AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 25,
      activityType: ActivityType.automotiveNavigation,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    ),
    _ => const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25),
  };

  Future<void> _send(Position p) async {
    final now = DateTime.now();
    final member = _memberId;
    if (member == null || now.difference(_lastSent) < _minGap) return;
    _lastSent = now;
    for (final id in _orders) {
      try {
        await _db.rpc<void>('staff_courier_position', params: {
          'p_order_id': id,
          'p_member_id': member,
          'p_lat': p.latitude,
          'p_lng': p.longitude,
          'p_accuracy': p.accuracy,
        });
      } catch (_) {
        // Brak sieci: następna pozycja pójdzie za chwilę.
      }
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _orders = const {};
  }
}

final courierTrackerProvider = Provider<CourierTracker>((ref) {
  final tracker = CourierTracker(Supabase.instance.client);
  ref.onDispose(tracker.stop);
  return tracker;
});
