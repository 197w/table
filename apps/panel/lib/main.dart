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
import 'app/updater.dart';

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

  void startPanel() => runApp(
    ProviderScope(
      overrides: [
        themeSettingProvider.overrideWith(
          () => ThemeSettingNotifier(themeSetting),
        ),
      ],
      child: const PanelApp(),
    ),
  );

  // Przy starcie nikt jeszcze nie pracuje w panelu, więc nowa wersja instaluje się od razu.
  final pending = await PanelUpdater.check(timeout: const Duration(seconds: 4));
  if (pending != null) {
    runApp(_UpdatingApp(release: pending, onSkip: startPanel));
    return;
  }
  startPanel();
}

/// Ekran aktualizacji przy starcie: pobiera nową wersję, a instalator ją uruchamia.
class _UpdatingApp extends StatefulWidget {
  const _UpdatingApp({required this.release, required this.onSkip});

  final PanelRelease release;
  final VoidCallback onSkip;

  @override
  State<_UpdatingApp> createState() => _UpdatingAppState();
}

class _UpdatingAppState extends State<_UpdatingApp> {
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _install();
  }

  Future<void> _install() async {
    setState(() {
      _error = null;
      _progress = null;
    });
    try {
      await PanelUpdater.install(
        widget.release,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PanelTheme.build(PanelPalette.dark),
      home: Builder(
        builder: (context) {
          final text = Theme.of(context).textTheme;
          return Scaffold(
            body: Center(
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _error == null
                          ? 'Aktualizuję Table do wersji ${widget.release.version}'
                          : 'Aktualizacja się nie udała',
                      style: text.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error ??
                          'To potrwa chwilę. Panel uruchomi się sam, gdy skończy.',
                      style: text.bodyMedium?.copyWith(color: PanelPalette.dark.textMuted),
                    ),
                    const SizedBox(height: 20),
                    if (_error == null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 6,
                          color: PanelPalette.dark.accentFill,
                          backgroundColor: PanelPalette.dark.surfaceRaised,
                        ),
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: widget.onSkip,
                            child: const Text('Uruchom bez aktualizacji'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _install,
                            child: const Text('Spróbuj ponownie'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
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
