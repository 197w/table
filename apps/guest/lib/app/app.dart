import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import '../features/auth/auth_screens.dart';
import '../features/booking/booking_screen.dart';
import '../features/discover/discover_screen.dart';
import '../features/reservations/reservation_detail_screen.dart';
import '../features/reservations/reservations_screen.dart';
import '../features/restaurant/menu_screen.dart';
import '../features/restaurant/restaurant_screen.dart';
import '../features/reviews/write_review_screen.dart';
import '../features/settings/account_screens.dart';
import '../features/settings/general_settings_screen.dart';
import '../features/settings/help_screens.dart';
import '../features/settings/notification_settings_screen.dart';
import 'guest_theme.dart';
import '../features/settings/settings_screen.dart';
import 'shell.dart';

class TableApp extends ConsumerStatefulWidget {
  const TableApp({super.key});

  @override
  ConsumerState<TableApp> createState() => _TableAppState();
}

class _TableAppState extends ConsumerState<TableApp>
    with WidgetsBindingObserver {
  late final _AuthRefresh _authRefresh;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authRefresh = _AuthRefresh(
      Supabase.instance.client.auth.onAuthStateChange,
    );
    _router = _buildRouter(_authRefresh);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    _authRefresh.dispose();
    super.dispose();
  }

  /// Motyw systemowy zmienia się razem z jasnością telefonu, także przy otwartej aplikacji.
  @override
  void didChangePlatformBrightness() {
    if (ref.read(themeSettingProvider) == AppThemeSetting.system) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final setting = ref.watch(themeSettingProvider);
    final brightness = switch (setting) {
      AppThemeSetting.light => Brightness.light,
      AppThemeSetting.dark => Brightness.dark,
      AppThemeSetting.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    final palette = brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    AppColors.use(palette);

    // Ekrany czytają kolory z palety, więc klucz odbudowuje całe drzewo przy zmianie motywu.
    // Zmiana jest natychmiastowa, bez smużenia kolorów, a stan nawigacji trzyma router.
    // Zmiana motywu przechodzi płynnie: ThemeFade wygasza zdjęcie starego wyglądu.
    return ThemeFade(
      child: MaterialApp.router(
        key: ValueKey(brightness),
        title: 'Table',
        debugShowCheckedModeBanner: false,
        theme: GuestTheme.build(palette),
        locale: const Locale('pl', 'PL'),
        supportedLocales: const [Locale('pl', 'PL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: _router,
      ),
    );
  }
}

/// Ekrany wymagające zalogowania. Zakładki dolnego menu same pokazują prośbę o logowanie,
/// bo przekierowanie z zakładki zabierało gościowi dolne menu.
bool _requiresLogin(String path) {
  return path.endsWith('/rezerwuj') ||
      path.endsWith('/opinia') ||
      path.endsWith('/karta');
}

bool _isAuthScreen(String path) =>
    path.startsWith(AppRoutes.login) || path.startsWith(AppRoutes.register);

GoRouter _buildRouter(Listenable refresh) {
  return GoRouter(
    initialLocation: AppRoutes.discover,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = Supabase.instance.client.auth.currentSession != null;
      // Sama ścieżka, bo parametry adresu psuły sprawdzanie końcówki.
      final path = state.uri.path;
      final location = state.uri.toString();

      if (!loggedIn && _requiresLogin(path)) {
        return Uri(
          path: AppRoutes.login,
          queryParameters: {'next': location},
        ).toString();
      }

      if (loggedIn && _isAuthScreen(location)) {
        final next = state.uri.queryParameters['next'];
        return (next != null && next.startsWith('/'))
            ? next
            : AppRoutes.discover;
      }

      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.discover,
                builder: (context, state) => const DiscoverScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.reservations,
                builder: (context, state) => const ReservationsScreen(),
                routes: [
                  // Wewnątrz zakładki, więc dolne menu zostaje na ekranie.
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => ReservationDetailScreen(
                      reservationId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
                // Podstrony w zakładce, więc dolne menu zostaje na ekranie.
                routes: [
                  GoRoute(
                    path: 'ogolne',
                    builder: (_, _) => const GeneralSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'motyw',
                    builder: (_, _) => const ThemeSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'powiadomienia',
                    builder: (_, _) => const NotificationSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'pomoc',
                    builder: (_, _) => const HelpScreen(),
                    routes: [
                      GoRoute(
                        path: 'zglos-blad',
                        builder: (_, _) => const ReportBugScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'konto',
                    builder: (_, _) => const AccountScreen(),
                    routes: [
                      GoRoute(
                        path: 'szczegoly',
                        builder: (_, _) => const AccountDetailsScreen(),
                      ),
                      GoRoute(
                        path: 'logowanie',
                        builder: (_, _) => const LoginInfoScreen(),
                        routes: [
                          GoRoute(
                            path: 'haslo',
                            builder: (_, _) => const ChangePasswordScreen(),
                          ),
                          GoRoute(
                            path: 'telefon',
                            builder: (_, _) => const ChangePhoneScreen(),
                            routes: [
                              GoRoute(
                                path: 'kod',
                                builder: (context, state) => SmsCodeScreen(
                                  phone:
                                      state.uri.queryParameters['telefon'] ??
                                      '',
                                  mode: SmsCodeMode.phoneChange,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'zaawansowane',
                    builder: (_, _) => const AdvancedSettingsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/restauracja/:id',
        builder: (context, state) =>
            RestaurantScreen(restaurantId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'rezerwuj',
            builder: (context, state) =>
                BookingScreen(restaurantId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'menu',
            builder: (context, state) =>
                RestaurantMenuScreen(restaurantId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'opinia',
            builder: (context, state) => WriteReviewScreen(
              restaurantId: state.pathParameters['id']!,
              reservationId: state.uri.queryParameters['rezerwacja'],
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) =>
            PhoneLoginScreen(next: state.uri.queryParameters['next']),
        routes: [
          GoRoute(
            path: 'haslo',
            builder: (context, state) => PasswordLoginScreen(
              phone: state.uri.queryParameters['telefon'] ?? '',
              next: state.uri.queryParameters['next'],
            ),
          ),
          GoRoute(
            path: 'kod',
            builder: (context, state) => SmsCodeScreen(
              phone: state.uri.queryParameters['telefon'] ?? '',
              next: state.uri.queryParameters['next'],
              mode: SmsCodeMode.login,
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) =>
            RegisterScreen(next: state.uri.queryParameters['next']),
        routes: [
          GoRoute(
            path: 'kod',
            builder: (context, state) => SmsCodeScreen(
              phone: state.uri.queryParameters['telefon'] ?? '',
              next: state.uri.queryParameters['next'],
              mode: SmsCodeMode.register,
            ),
          ),
        ],
      ),
    ],
  );
}

abstract final class AppRoutes {
  static const discover = '/odkrywaj';
  static const reservations = '/rezerwacje';
  static const settings = '/ustawienia';
  static const settingsGeneral = '/ustawienia/ogolne';
  static const settingsTheme = '/ustawienia/motyw';
  static const settingsNotifications = '/ustawienia/powiadomienia';
  static const settingsHelp = '/ustawienia/pomoc';
  static const reportBug = '/ustawienia/pomoc/zglos-blad';
  static const settingsAccount = '/ustawienia/konto';
  static const accountDetails = '/ustawienia/konto/szczegoly';
  static const loginInfo = '/ustawienia/konto/logowanie';
  static const changePassword = '/ustawienia/konto/logowanie/haslo';
  static const changePhone = '/ustawienia/konto/logowanie/telefon';
  static const changePhoneCode = '/ustawienia/konto/logowanie/telefon/kod';
  static const settingsAdvanced = '/ustawienia/zaawansowane';
  static const login = '/logowanie';
  static const register = '/rejestracja';

  static String restaurant(String id) => '/restauracja/$id';
  static String reservationDetail(String id) => '/rezerwacje/$id';
  static String booking(String id) => '/restauracja/$id/rezerwuj';
  static String menu(String id) => '/restauracja/$id/menu';
  static String review(String id, {String? reservationId}) => Uri(
    path: '/restauracja/$id/opinia',
    queryParameters: reservationId == null
        ? null
        : {'rezerwacja': reservationId},
  ).toString();

  static String withNext(String path, String? next, {String? phone}) => Uri(
    path: path,
    queryParameters: {'telefon': ?phone, 'next': ?next},
  ).toString();
}

/// Odświeża router przy zmianie sesji.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<AuthState> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
