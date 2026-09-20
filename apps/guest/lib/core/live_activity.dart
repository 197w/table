import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:table_core/table_core.dart';

import '../data/models.dart';

/// Kafel rezerwacji na ekranie blokady iPhone'a i iPada (Live Activity).
/// Pokazuje się 1,5 godziny przed rezerwacją i znika godzinę po jej godzinie.
/// Na Androidzie nic nie robi.
class LiveActivity {
  LiveActivity._();

  static final instance = LiveActivity._();

  static const _channel = MethodChannel('pl.table.app/live_activity');

  /// Ile przed godziną rezerwacji ma się pojawić kafel.
  static const window = Duration(minutes: 90);

  Timer? _timer;
  String? _shownId;

  bool get _supported {
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Patrzy na rezerwacje gościa i pilnuje, żeby na ekranie blokady był kafel
  /// tej najbliższej. Wywołuj po każdym wczytaniu listy rezerwacji.
  Future<void> sync(List<Reservation> reservations) async {
    if (!_supported) return;

    final now = DateTime.now();
    Reservation? next;
    for (final r in reservations) {
      if (r.status != ReservationStatus.confirmed) continue;
      if (!r.startsAt.isAfter(now.subtract(const Duration(hours: 1)))) continue;
      if (next == null || r.startsAt.isBefore(next.startsAt)) next = r;
    }

    if (next == null) {
      await _end();
      return;
    }

    final untilStart = next.startsAt.difference(now);
    if (untilStart > window) {
      // Za wcześnie: kafel ma się pojawić dopiero w oknie 1,5 godziny.
      await _end();
      _scheduleAt(untilStart - window, reservations);
      return;
    }

    await _show(next);
    _scheduleAt(next.startsAt.add(const Duration(hours: 1)).difference(now), reservations);
  }

  void _scheduleAt(Duration delay, List<Reservation> reservations) {
    _timer?.cancel();
    if (delay.isNegative) return;
    // Timer działa, dopóki aplikacja żyje w tle. Po jej zamknięciu kafel
    // pojawi się przy następnym otwarciu aplikacji.
    _timer = Timer(delay + const Duration(seconds: 1), () => sync(reservations));
  }

  Future<void> _show(Reservation r) async {
    final details = [
      Fmt.people(r.partySize),
      if (r.occasion != null) r.occasion!.label,
    ].join(' · ');
    try {
      await _channel.invokeMethod<bool>('show', {
        'reservationId': r.id,
        'restaurantName': r.restaurantName,
        'address': r.restaurantAddress,
        'startsAtMs': r.startsAt.millisecondsSinceEpoch,
        'details': details,
      });
      _shownId = r.id;
    } on PlatformException {
      // Brak zgody na kafle albo starszy system: aplikacja działa dalej bez nich.
    } on MissingPluginException {
      // Wersja bez rozszerzenia z widżetem.
    }
  }

  Future<void> _end() async {
    if (_shownId == null) return;
    _shownId = null;
    try {
      await _channel.invokeMethod<bool>('end', const <String, dynamic>{});
    } on PlatformException {
      // Nie ma czego zamykać.
    } on MissingPluginException {
      // Wersja bez rozszerzenia z widżetem.
    }
  }

  void dispose() => _timer?.cancel();
}
