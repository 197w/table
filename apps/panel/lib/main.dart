import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/panel_theme.dart';
import 'app/reservation_alerts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pl_PL');
  Intl.defaultLocale = 'pl_PL';

  // Panel nie zwęża się do rozmiaru telefonu: plan sali i lista rezerwacji potrzebują miejsca.
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1440, 900),
      minimumSize: Size(1100, 720),
      center: true,
      title: 'Table · Panel restauracji',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  await ReservationAlerts.setup();

  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  final themeSetting = await ThemeSettingNotifier.load();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
  );

  runApp(
    ProviderScope(
      overrides: [
        themeSettingProvider.overrideWith(
          () => ThemeSettingNotifier(themeSetting),
        ),
      ],
      child: const PanelApp(),
    ),
  );
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PanelTheme.build(AppPalette.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Brakuje konfiguracji Supabase',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Uruchom panel z pliku env.json w katalogu głównym repozytorium:',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    'flutter run -d windows --dart-define-from-file=../../env.json',
                    style: TextStyle(color: AppPalette.dark.accent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
