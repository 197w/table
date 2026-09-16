import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/units.dart';

/// Ustawienie zapisane w pamięci telefonu jako nazwa wartości wyliczenia.
class EnumPreferenceNotifier<T extends Enum> extends Notifier<T> {
  EnumPreferenceNotifier(this._key, this._values, this._initial);

  final String _key;
  final List<T> _values;
  final T _initial;

  @override
  T build() => _initial;

  /// Wczytywane przed startem aplikacji, żeby ekrany od razu miały właściwą wartość.
  static Future<T> load<T extends Enum>(
    String key,
    List<T> values,
    T fallback,
  ) async {
    try {
      final saved = await SharedPreferencesAsync().getString(key);
      for (final value in values) {
        if (value.name == saved) return value;
      }
    } catch (_) {
      // Brak zapisu: wartość domyślna.
    }
    return fallback;
  }

  Future<void> set(T value) async {
    if (value == state || !_values.contains(value)) return;
    state = value;
    try {
      await SharedPreferencesAsync().setString(_key, value.name);
    } catch (_) {
      // Wybór działa do zamknięcia aplikacji, nawet jeśli zapis się nie udał.
    }
  }
}

abstract final class PreferenceKeys {
  static const language = 'jezyk';
  static const distanceUnit = 'jednostki';
}

final languageProvider =
    NotifierProvider<EnumPreferenceNotifier<AppLanguage>, AppLanguage>(
      () => EnumPreferenceNotifier(
        PreferenceKeys.language,
        AppLanguage.values,
        AppLanguage.pl,
      ),
    );

final distanceUnitProvider =
    NotifierProvider<EnumPreferenceNotifier<DistanceUnit>, DistanceUnit>(
      () => EnumPreferenceNotifier(
        PreferenceKeys.distanceUnit,
        DistanceUnit.values,
        DistanceUnit.kilometers,
      ),
    );

/// Wersja aplikacji, na przykład „0.1.0+1”. Trafia do zgłoszeń błędów.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
});
