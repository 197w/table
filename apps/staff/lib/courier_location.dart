import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stan udostępniania lokalizacji.
enum ShareState {
  /// Nic nie jest wysyłane (poza zmianą albo lokal nie wymaga lokalizacji i nie ma kursu w drodze).
  off,
  starting,
  on,

  /// Brak zgody na lokalizację dla aplikacji.
  noPermission,

  /// Lokalizacja w telefonie jest wyłączona.
  serviceOff,
}

/// Pozycja dostawcy. Gdy lokal wymaga lokalizacji („Ustawienia lokalu” w panelu), telefon wysyła ją
/// przez całą zmianę: panel widzi dostawcę na mapie, a bez pozycji dostawca nie dostaje kursów.
/// Bez tego wymogu tylko w trakcie kursu w drodze, żeby gość widział zamówienie na mapie.
/// Na Androidzie działa w tle ze stałym powiadomieniem, na iPhonie z niebieskim wskaźnikiem.
class CourierTracker {
  CourierTracker(this._db);

  final SupabaseClient _db;

  /// Stan dla ekranów (Dostawy, Zeskanuj).
  final state = ValueNotifier(ShareState.off);

  StreamSubscription<Position>? _sub;
  StreamSubscription<ServiceStatus>? _service;
  Timer? _heartbeat;
  Position? _last;
  DateTime _lastSent = DateTime(2000);
  bool _starting = false;

  /// Pracownik, który udostępnia lokalizację przez całą zmianę (null: nie trzeba).
  String? _shiftMember;

  /// Pracownik i kursy w drodze (tryb bez wymogu lokalizacji).
  String? _courseMember;
  Set<String> _orders = const {};

  /// Tryb, w którym działa strumień: zmiana albo kurs (inne powiadomienie na Androidzie).
  bool? _runningShift;

  static const _minGap = Duration(seconds: 15);

  /// Bez ruchu telefon nie podaje nowych pozycji, a serwer uznaje pozycję starszą niż 3 minuty
  /// za brak lokalizacji. Co minutę wysyłamy więc ostatnią znaną.
  static const _heartbeatEvery = Duration(minutes: 1);

  String? get _member => _shiftMember ?? _courseMember;
  bool get _wanted => _shiftMember != null || _orders.isNotEmpty;

  /// Cała zmiana: [memberId] z wymogiem lokalizacji albo null, gdy wymogu nie ma lub zmiana się skończyła.
  /// Ten sam pracownik drugi raz niczego nie zmienia (o zgodę pyta tylko [retry]).
  Future<ShareState> shift(String? memberId) async {
    if (_shiftMember == memberId) return state.value;
    _shiftMember = memberId;
    return _apply();
  }

  /// Kursy w drodze (gdy lokal nie wymaga lokalizacji przez całą zmianę). Zwraca false, gdy brak zgody.
  Future<bool> update(String memberId, Iterable<String> onTheWay) async {
    final orders = onTheWay.toSet();
    final added = orders.difference(_orders).isNotEmpty;
    _courseMember = memberId;
    _orders = orders;
    // Nowy kurs w drodze: pozycja od razu, bez czekania na ruch.
    if (added) _lastSent = DateTime(2000);
    final s = await _apply();
    return s == ShareState.on || s == ShareState.off || s == ShareState.starting;
  }

  /// Ponowna próba po zmianie zgody albo włączeniu lokalizacji (powrót do aplikacji, przycisk na ekranie).
  Future<ShareState> retry() {
    _stopStream();
    return _apply();
  }

  Future<ShareState> _apply() async {
    if (!_wanted) {
      stop();
      return state.value;
    }
    final shiftMode = _shiftMember != null;
    if (_sub != null && _runningShift == shiftMode) return state.value;
    if (_starting) return state.value;
    _starting = true;
    if (state.value != ShareState.on) state.value = ShareState.starting;
    try {
      _stopStream();
      final ready = await _permission();
      if (ready != ShareState.on) {
        state.value = ready;
        await _reportOff();
        _watchService();
        return ready;
      }
      _runningShift = shiftMode;
      _sub = Geolocator.getPositionStream(locationSettings: _settings(shiftMode)).listen(
        _send,
        onError: (Object e) async {
          // Lokalizację wyłączono w trakcie: dostawca od razu wypada z kolejki, a po włączeniu wraca.
          _stopStream();
          state.value = e is LocationServiceDisabledException ? ShareState.serviceOff : ShareState.noPermission;
          await _reportOff();
          _watchService();
        },
      );
      _heartbeat = Timer.periodic(_heartbeatEvery, (_) {
        final last = _last;
        if (last != null && DateTime.now().difference(_lastSent) >= _heartbeatEvery) _send(last, force: true);
      });
      state.value = ShareState.on;
      _watchService();
      // Pierwsza pozycja od razu (strumień potrafi czekać na pierwszy ruch).
      unawaited(
        Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
        ).then((p) => _send(p, force: true), onError: (_) {}),
      );
      return ShareState.on;
    } finally {
      _starting = false;
    }
  }

  /// Włączenie albo wyłączenie lokalizacji w telefonie: wznawiamy albo zgłaszamy brak.
  void _watchService() {
    if (_service != null) return;
    try {
      _service = Geolocator.getServiceStatusStream().listen((s) async {
        if (s == ServiceStatus.enabled && state.value == ShareState.serviceOff && _wanted) {
          await retry();
        } else if (s == ServiceStatus.disabled && _wanted) {
          _stopStream();
          state.value = ShareState.serviceOff;
          await _reportOff();
        }
      }, onError: (_) {});
    } catch (_) {
      // Platforma bez strumienia stanu: zostaje ponowna próba z ekranu.
    }
  }

  Future<ShareState> _permission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return ShareState.serviceOff;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      return p == LocationPermission.whileInUse || p == LocationPermission.always
          ? ShareState.on
          : ShareState.noPermission;
    } catch (_) {
      return ShareState.noPermission;
    }
  }

  /// Brak zgody na zawsze: zostają ustawienia aplikacji w telefonie.
  Future<bool> deniedForever() async {
    try {
      return await Geolocator.checkPermission() == LocationPermission.deniedForever;
    } catch (_) {
      return false;
    }
  }

  LocationSettings _settings(bool shiftMode) => switch (defaultTargetPlatform) {
    TargetPlatform.android => AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      intervalDuration: const Duration(seconds: 15),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: shiftMode ? 'Udostępniasz lokalizację' : 'Kurs w drodze',
        notificationText: shiftMode
            ? 'Lokal widzi Cię na mapie do końca zmiany.'
            : 'Gość widzi na mapie, gdzie jest zamówienie.',
        setOngoing: true,
      ),
    ),
    TargetPlatform.iOS => AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      activityType: ActivityType.automotiveNavigation,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    ),
    _ => const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
  };

  Future<void> _send(Position p, {bool force = false}) async {
    _last = p;
    final now = DateTime.now();
    final member = _member;
    if (member == null || (!force && now.difference(_lastSent) < _minGap)) return;
    _lastSent = now;
    try {
      await _db.rpc<void>(
        'staff_share_location',
        params: {
          'p_member_id': member,
          'p_lat': p.latitude,
          'p_lng': p.longitude,
          'p_accuracy': p.accuracy,
          'p_heading': p.heading >= 0 ? p.heading : null,
          'p_speed': p.speed >= 0 ? p.speed : null,
        },
      );
    } catch (_) {
      // Brak sieci: następna pozycja pójdzie za chwilę.
    }
  }

  /// Serwer od razu wie, że pozycji nie będzie (dostawca nie dostaje kursów, panel pokazuje „Bez lokalizacji”).
  Future<void> _reportOff() async {
    final member = _shiftMember;
    if (member == null) return;
    try {
      await _db.rpc<void>('staff_stop_location', params: {'p_member_id': member});
    } catch (_) {
      // Bez sieci serwer i tak uzna pozycję za nieaktualną po 3 minutach.
    }
  }

  void _stopStream() {
    _sub?.cancel();
    _sub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _runningShift = null;
  }

  void stop() {
    _stopStream();
    _service?.cancel();
    _service = null;
    _orders = const {};
    _courseMember = null;
    _shiftMember = null;
    state.value = ShareState.off;
  }
}

final courierTrackerProvider = Provider<CourierTracker>((ref) {
  final tracker = CourierTracker(Supabase.instance.client);
  ref.onDispose(tracker.stop);
  return tracker;
});
