import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Panel na komputerze (Windows, macOS). Fałsz: pełny panel na tablecie w Table for employees.
bool get panelOnDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Pełny ekran: na komputerze okno, na tablecie ukryte paski systemu.
Future<void> setPanelFullscreen(bool value) async {
  try {
    if (panelOnDesktop) {
      await windowManager.setFullScreen(value);
      if (!value) await windowManager.maximize();
    } else {
      await SystemChrome.setEnabledSystemUIMode(value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  } catch (_) {
    // Bez trybu pełnoekranowego zostaje samo ukrycie menu.
  }
}
