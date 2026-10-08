import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_icons.dart';

enum AppThemeSetting {
  system('Systemowy', AppIcons.monitor),
  light('Jasny', AppIcons.sun),
  dark('Ciemny', AppIcons.moon);

  const AppThemeSetting(this.label, this.icon);

  final String label;
  final AppIconData icon;
}

/// Wybrany motyw, zapamiętany na urządzeniu.
class ThemeSettingNotifier extends Notifier<AppThemeSetting> {
  ThemeSettingNotifier([this._initial = AppThemeSetting.system]);

  final AppThemeSetting _initial;

  static const _key = 'motyw';

  @override
  AppThemeSetting build() => _initial;

  /// Wczytywane przed startem aplikacji, żeby nie mignął zły motyw.
  static Future<AppThemeSetting> load() async {
    try {
      final saved = await SharedPreferencesAsync().getString(_key);
      for (final setting in AppThemeSetting.values) {
        if (setting.name == saved) return setting;
      }
    } catch (_) {
      // Brak zapisanego wyboru: motyw systemowy.
    }
    return AppThemeSetting.system;
  }

  Future<void> set(AppThemeSetting value) async {
    if (value == state) return;
    state = value;
    try {
      await SharedPreferencesAsync().setString(_key, value.name);
    } catch (_) {
      // Wybór działa do zamknięcia aplikacji, nawet jeśli zapis się nie udał.
    }
  }
}

final themeSettingProvider =
    NotifierProvider<ThemeSettingNotifier, AppThemeSetting>(
      ThemeSettingNotifier.new,
    );
