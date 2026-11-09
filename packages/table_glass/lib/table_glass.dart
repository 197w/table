/// Natywne przyciski Liquid Glass (iOS 26) w oknie aplikacji, nad widokiem Fluttera.
///
/// Inaczej niż widoki platformy (UiKitView) Flutter ich nie składa z treścią i nie przechwytuje ich dotyku:
/// to zwykłe przyciski UIKit leżące nad ekranem Fluttera. Dlatego mogą stać w oknach od dołu, w których
/// natywny widok platformy blokował na iPhonie całe okno (9.11.2026). Strona Dart podaje położenie w punktach
/// (logiczne piksele Fluttera) i chowa przycisk, gdy jego miejsce się rusza.
library;

import 'package:flutter/services.dart';

/// Kanał „pl.table.glass” do natywnych przycisków nad Flutterem.
abstract final class TableGlass {
  static const _channel = MethodChannel('pl.table.glass');
  static final _handlers = <int, VoidCallback>{};
  static var _ready = false;
  static var _nextId = 0;

  static void _init() {
    if (_ready) return;
    _ready = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pressed') _handlers[call.arguments as int]?.call();
    });
    // Przyciski z poprzedniego uruchomienia Darta (hot restart) znikają.
    _invoke('reset');
  }

  /// Nowy przycisk. [onPressed]: stuknięcie w natywny przycisk (sam się wtedy chowa).
  static int register(VoidCallback onPressed) {
    _init();
    final id = _nextId++;
    _handlers[id] = onPressed;
    return id;
  }

  /// Pokazuje przycisk [id] w miejscu [rect] (współrzędne ekranu Fluttera). False: nie udało się, np. starszy
  /// iOS albo brak wtyczki; wtedy zostaje szkło rysowane przez Fluttera.
  static Future<bool> show(
    int id, {
    required Rect rect,
    required String symbol,
    required double symbolSize,
    required bool dark,
    required Color color,
  }) async {
    final ok = await _invoke<bool>('show', {
      'id': id,
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
      'symbol': symbol,
      'symbolSize': symbolSize,
      'dark': dark,
      'color': color.toARGB32(),
    });
    return ok ?? false;
  }

  /// Chowa przycisk [id] od razu (np. okno zaczyna jechać).
  static void hide(int id) => _invoke('hide', {'id': id});

  /// Usuwa przycisk [id] na stałe.
  static void remove(int id) {
    _handlers.remove(id);
    _invoke('remove', {'id': id});
  }

  static Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
