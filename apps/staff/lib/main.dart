import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Table Praca: aplikacja dla pracowników lokalu. Zmianę zaczyna się skanem kodu QR
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
  runApp(const ProviderScope(child: StaffApp()));
}

class StaffApp extends ConsumerWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final palette = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
    AppColors.use(palette);
    final signedIn = ref.watch(sessionProvider) != null;

    return MaterialApp(
      key: ValueKey(brightness),
      title: 'Table Praca',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(palette),
      locale: const Locale('pl', 'PL'),
      supportedLocales: const [Locale('pl', 'PL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: signedIn ? const HomeScreen() : const LoginScreen(),
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
