/// Kurs dostawcy na ekranie samochodu: Android Auto i CarPlay.
///
/// Aplikacja Table for employees podaje tu bieżący kurs ([TableCar.show]). Wtyczka trzyma go po stronie
/// natywnej, więc ekran samochodu pokazuje go od razu po podłączeniu telefonu, także gdy aplikacja
/// jest w tle. [TableCar.connection] mówi, czy telefon jest podłączony do samochodu (automatyczne rozpoznanie).
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// Rodzaj połączenia z samochodem.
enum CarConnection {
  none,

  /// Android Auto na ekranie samochodu (albo w emulatorze DHU).
  androidAuto,

  /// CarPlay na ekranie samochodu (albo w symulatorze CarPlay w Xcode).
  carPlay,
}

/// Kurs w formie gotowej do pokazania w samochodzie: krótkie teksty, bez logiki.
class CarCourse {
  const CarCourse({
    required this.number,
    required this.stage,
    required this.address,
    required this.customer,
    required this.phone,
    required this.payment,
    required this.items,
    this.note,
    this.promised,
  });

  /// Numer zamówienia, np. 12.
  final int number;

  /// Etap, np. „Gotowe do odbioru”, „W drodze”.
  final String stage;
  final String address;
  final String customer;
  final String phone;

  /// Np. „Pobierz 87,00 zł gotówką” albo „Opłacone kartą online”.
  final String payment;

  /// Np. „3 pozycje”.
  final String items;
  final String? note;

  /// Np. „na 19:20”.
  final String? promised;

  Map<String, Object?> toMap() => {
    'number': number,
    'stage': stage,
    'address': address,
    'customer': customer,
    'phone': phone,
    'payment': payment,
    'items': items,
    'note': note,
    'promised': promised,
  };
}

abstract final class TableCar {
  static const _channel = MethodChannel('pl.table.car');
  static const _events = EventChannel('pl.table.car/connection');

  /// Pokazuje kurs w samochodzie. Bez kursu ekran pokazuje [status], np. „Czekasz na kurs · 2. w kolejce”.
  /// [next] to liczba kolejnych kursów po bieżącym.
  static Future<void> show({CarCourse? course, required String status, int next = 0}) async {
    try {
      await _channel.invokeMethod<void>('show', {
        'course': course?.toMap(),
        'status': status,
        'next': next,
      });
    } on MissingPluginException {
      // Platforma bez samochodu (testy, komputer): nic do zrobienia.
    } on PlatformException {
      // Ekran samochodu nie jest dostępny.
    }
  }

  /// Czy telefon jest teraz podłączony do samochodu. Nowa wartość przy każdej zmianie.
  /// Bez wtyczki (testy, platforma bez samochodu) strumień od razu się kończy.
  static Stream<CarConnection> get connection async* {
    try {
      await _channel.invokeMethod<void>('ping');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
    yield* _events.receiveBroadcastStream().map(
      (value) => switch (value) {
        'android_auto' => CarConnection.androidAuto,
        'carplay' => CarConnection.carPlay,
        _ => CarConnection.none,
      },
    ).handleError((Object _) {});
  }
}
