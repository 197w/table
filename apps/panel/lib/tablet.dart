import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'app/app.dart';
import 'app/reservation_alerts.dart';
import 'data/providers.dart';

/// Tablet: krótszy bok ekranu ma co najmniej 600 punktów (telefony mają mniej).
bool get isTabletScreen {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return false;
  final view = views.first;
  return (view.physicalSize / view.devicePixelRatio).shortestSide >= 600;
}

/// Pełny panel restauracji na tablecie, uruchamiany przez Table for employees (tak jak na komputerze, poziomo).
/// Supabase jest już zainicjowany przez aplikację. Okno, powiadomienia systemowe Windows i aktualizator
/// nie działają na tablecie; ich wywołania same się pomijają.
Future<void> runPanelOnTablet() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pl_PL');
  Intl.defaultLocale = 'pl_PL';
  // Dźwięki panelu leżą w pakiecie table_panel, a nie w aplikacji, która go uruchamia.
  AudioCache.instance = AudioCache(prefix: 'packages/table_panel/assets/');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await ReservationAlerts.setup();
  final themeSetting = await ThemeSettingNotifier.load();
  final fullscreen = await StartFullscreenNotifier.load();
  if (fullscreen) await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(
    ProviderScope(
      overrides: [
        themeSettingProvider.overrideWith(() => ThemeSettingNotifier(themeSetting)),
        startFullscreenProvider.overrideWith(() => StartFullscreenNotifier(fullscreen)),
      ],
      child: const PanelApp(),
    ),
  );
}
