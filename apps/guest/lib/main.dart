import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import 'app/app.dart';
import 'app/preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pl_PL');
  Intl.defaultLocale = 'pl_PL';

  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  final themeSetting = await ThemeSettingNotifier.load();
  final language = await EnumPreferenceNotifier.load(
    PreferenceKeys.language,
    AppLanguage.values,
    AppLanguage.pl,
  );
  final distanceUnit = await EnumPreferenceNotifier.load(
    PreferenceKeys.distanceUnit,
    DistanceUnit.values,
    DistanceUnit.kilometers,
  );
  final discoverLayout = await EnumPreferenceNotifier.load(
    PreferenceKeys.discoverLayout,
    DiscoverLayout.values,
    DiscoverLayout.cards,
  );

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
        languageProvider.overrideWith(
          () => EnumPreferenceNotifier(
            PreferenceKeys.language,
            AppLanguage.values,
            language,
          ),
        ),
        distanceUnitProvider.overrideWith(
          () => EnumPreferenceNotifier(
            PreferenceKeys.distanceUnit,
            DistanceUnit.values,
            distanceUnit,
          ),
        ),
        discoverLayoutProvider.overrideWith(
          () => EnumPreferenceNotifier(
            PreferenceKeys.discoverLayout,
            DiscoverLayout.values,
            discoverLayout,
          ),
        ),
      ],
      child: const TableApp(),
    ),
  );
}

/// Pokazywane, gdy aplikację uruchomiono bez pliku env.json.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppPalette.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Brakuje konfiguracji Supabase',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Skopiuj env.example.json do env.json, wpisz adres projektu '
                    'i klucz publikowalny, a potem uruchom aplikację poleceniem:',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    'flutter run --dart-define-from-file=env.json',
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
