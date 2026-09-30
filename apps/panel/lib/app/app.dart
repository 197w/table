import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import '../features/auth/login_screen.dart';
import '../features/floor/floor_screen.dart';
import '../features/gift_cards/gift_cards_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/kitchen/kitchen_screen.dart';
import '../features/menu/menu_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/reservations/reservations_screen.dart';
import '../features/reviews/reviews_screen.dart';
import '../features/staff/staff_screen.dart';
import '../features/stats/stats_screen.dart';
import 'panel_theme.dart';
import 'shell.dart';

class PanelApp extends ConsumerStatefulWidget {
  const PanelApp({super.key});

  @override
  ConsumerState<PanelApp> createState() => _PanelAppState();
}

class _PanelAppState extends ConsumerState<PanelApp>
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
        ? PanelPalette.dark
        : AppPalette.light;
    AppColors.use(palette);

    // Zmiana motywu przechodzi płynnie: ThemeFade wygasza zdjęcie starego wyglądu.
    return ThemeFade(
      child: MaterialApp.router(
      key: ValueKey(brightness),
      title: 'Table · Panel restauracji',
      debugShowCheckedModeBanner: false,
      theme: PanelTheme.build(palette),
      locale: const Locale('pl', 'PL'),
      supportedLocales: const [Locale('pl', 'PL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
      ),
    );
  }
}

GoRouter _buildRouter(Listenable refresh) {
  return GoRouter(
    initialLocation: PanelRoutes.reservations,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = Supabase.instance.client.auth.currentSession != null;
      final onLogin = state.uri.path == PanelRoutes.login;
      // Po wygaśnięciu sesji zapamiętujemy, gdzie była obsługa, i po zalogowaniu tam wracamy.
      if (!loggedIn && !onLogin) {
        return Uri(
          path: PanelRoutes.login,
          queryParameters: {'dalej': state.uri.toString()},
        ).toString();
      }
      if (loggedIn && onLogin) {
        final next = state.uri.queryParameters['dalej'];
        final safe = next != null &&
            next.startsWith('/') &&
            !next.startsWith(PanelRoutes.login);
        return safe ? next : PanelRoutes.reservations;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: PanelRoutes.login,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: LoginScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            PanelShell(location: state.uri.path, child: child),
        routes: [
          _page(PanelRoutes.reservations, const ReservationsScreen()),
          GoRoute(
            path: PanelRoutes.floor,
            // Wyjście z edycji z niezapisanymi zmianami wymaga potwierdzenia.
            onExit: (context, state) => confirmLeaveFloor(context),
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: FloorScreen()),
          ),
          GoRoute(
            path: PanelRoutes.orders,
            // ?stolik=<id> otwiera od razu rachunek stolika klikniętego na planie sali.
            pageBuilder: (context, state) => NoTransitionPage(
              child: OrdersScreen(tableId: state.uri.queryParameters['stolik']),
            ),
          ),
          _page(PanelRoutes.kitchen, const KitchenScreen()),
          _page(PanelRoutes.staff, const StaffScreen()),
          _page(PanelRoutes.giftCards, const GiftCardsScreen()),
          _page(PanelRoutes.menu, const MenuScreen()),
          _page(PanelRoutes.inventory, const InventoryScreen()),
          _page(PanelRoutes.profile, const ProfileScreen()),
          _page(PanelRoutes.reviews, const ReviewsScreen()),
          _page(PanelRoutes.stats, const StatsScreen()),
        ],
      ),
    ],
  );
}

/// Zmiana sekcji bez animacji: w panelu przełącza się często, animacja by spowalniała.
GoRoute _page(String path, Widget child) => GoRoute(
  path: path,
  pageBuilder: (context, state) => NoTransitionPage(child: child),
);

abstract final class PanelRoutes {
  static const login = '/logowanie';
  static const reservations = '/rezerwacje';
  static const floor = '/sala';
  static const orders = '/zamowienia';
  static const kitchen = '/kuchnia';
  static const staff = '/pracownicy';
  static const giftCards = '/karty';
  static const menu = '/menu';
  static const inventory = '/inwentaryzacja';
  static const profile = '/lokal';
  static const reviews = '/opinie';
  static const stats = '/statystyki';
}

/// Uprawnienia, z których wystarczy jedno, żeby otworzyć zakładkę.
const _routePermissions = {
  PanelRoutes.reservations: {'reservations'},
  PanelRoutes.orders: {'orders'},
  PanelRoutes.kitchen: {'kitchen'},
  PanelRoutes.floor: {'floor_edit'},
  // W Pracownikach każda część ma własne uprawnienie: zespół, loginy, grafik, czas pracy, stanowiska.
  PanelRoutes.staff: {'staff', 'staff_logins', 'schedule', 'timesheet', 'positions'},
  PanelRoutes.profile: {'profile'},
  PanelRoutes.menu: {'menu'},
  PanelRoutes.inventory: {'inventory_edit', 'inventory_count'},
  PanelRoutes.giftCards: {'gift_cards'},
  PanelRoutes.reviews: {'reviews'},
  PanelRoutes.stats: {'stats'},
};

/// Nazwy zakładek, np. w logowaniu do zakładki.
const panelTabLabels = {
  PanelRoutes.reservations: 'Rezerwacje',
  PanelRoutes.orders: 'Zamówienia',
  PanelRoutes.kitchen: 'Kuchnia',
  PanelRoutes.floor: 'Edycja sali',
  PanelRoutes.staff: 'Pracownicy',
  PanelRoutes.profile: 'Dane lokalu',
  PanelRoutes.menu: 'Menu',
  PanelRoutes.inventory: 'Inwentaryzacja',
  PanelRoutes.giftCards: 'Karty podarunkowe',
  PanelRoutes.reviews: 'Opinie',
  PanelRoutes.stats: 'Statystyki',
};

/// Zakładka (jej ścieżka) dla adresu. Null: adres poza zakładkami.
String? tabForRoute(String location) {
  for (final tab in _routePermissions.keys) {
    if (location.startsWith(tab)) return tab;
  }
  return null;
}

/// Uprawnienia, z których wystarczy jedno, żeby otworzyć zakładkę. Null: zakładka dla każdego.
Set<String>? permissionsForRoute(String location) => _routePermissions[tabForRoute(location)];

/// Czy osoba z [permissions] może otworzyć zakładkę. Bez uprawnienia zakładki nie widać w menu.
bool canOpenRoute(String location, Set<String> permissions) {
  final need = permissionsForRoute(location);
  return need == null || need.any(permissions.contains);
}

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
