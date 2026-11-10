import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/email_auth.dart';
import 'package:table_core/table_core.dart';
import 'package:table_panel/tablet.dart';

import 'data.dart';
import 'login_screen.dart';
import 'shell.dart';

/// Table for employees: aplikacja dla pracowników lokalu. Zmianę zaczyna się skanem kodu QR
/// z panelu restauracji, tutaj też widać przepracowane godziny.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pl_PL');
  Intl.defaultLocale = 'pl_PL';

  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabasePublishableKey);
  // Na tablecie pełny panel restauracji, tak jak na komputerze (logowanie kontem lokalu, pracownicy kodem albo QR).
  if (isTabletScreen) {
    await runPanelOnTablet();
    return;
  }
  // Logowanie przerwane między kodem z e-maila a hasłem wylogowuje.
  await AuthPending.restore();
  // Motyw wczytany przed startem, żeby nie mignął zły (Konto → Motyw, 9.11.2026).
  final themeSetting = await ThemeSettingNotifier.load();
  runApp(
    ProviderScope(
      overrides: [themeSettingProvider.overrideWith(() => ThemeSettingNotifier(themeSetting))],
      child: const StaffApp(),
    ),
  );
}

class StaffApp extends ConsumerWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = switch (ref.watch(themeSettingProvider)) {
      AppThemeSetting.light => Brightness.light,
      AppThemeSetting.dark => Brightness.dark,
      AppThemeSetting.system => MediaQuery.platformBrightnessOf(context),
    };
    final palette = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
    AppColors.use(palette);
    final session = ref.watch(sessionProvider);

    // Zmiana motywu przechodzi płynnie jak w Table: ThemeFade wygasza zdjęcie starego wyglądu.
    return ThemeFade(
      child: MaterialApp(
      key: ValueKey(brightness),
      title: 'Table for employees',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(palette),
      locale: const Locale('pl', 'PL'),
      supportedLocales: const [Locale('pl', 'PL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Powiadomienia w stylu Table nad całą aplikacją. Natywne szkło (Liquid Glass) bierze jasność z telefonu,
      // więc dostaje jasność motywu aplikacji: jasny motyw przy ciemnym telefonie miał ciemne szkło (9.11.2026).
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(platformBrightness: brightness),
        child: ToastHost(child: child ?? const SizedBox.shrink()),
      ),
      // Sesja z kodu z e-maila liczy się dopiero po haśle.
      home: ValueListenableBuilder<bool>(
        valueListenable: AuthPending.instance,
        builder: (context, pending, _) => session != null && !pending ? const StaffShell() : const LoginScreen(),
      ),
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
      theme: AppTheme.build(AppPalette.dark),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Brakuje konfiguracji Supabase. Uruchom z --dart-define-from-file=../../env.json'),
          ),
        ),
      ),
    );
  }
}
